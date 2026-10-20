#!/usr/bin/env bash
# Build unsigned .ipa files from the .deb packages in incoming/.
#
# Honest pipeline, mirroring the web inspector:
#   - .app bundles containing ARM64 Mach-O executables  -> packaged as unsigned .ipa
#   - Linux ELF payloads, MobileSubstrate tweaks,
#     non-ARM64 Mac builds, data-only packages           -> rejected with a report
#
# No signing happens here — the user applies their own Apple ID signature
# at sideload time (SideStore / AltStore / Sideloadly).
set -uo pipefail

OUTDIR_ABS="$PWD/out"
mkdir -p "$OUTDIR_ABS" "$OUTDIR_ABS/selftest"
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/stdout}"
OUT_FILE="${GITHUB_OUTPUT:-/dev/null}"

log() { printf '%s\n' "$*" >> "$SUMMARY"; printf '%s\n' "$*" >&2; }

# ---------- binary sniffing (magic bytes, like the web inspector) ----------

bin_kind() {
  local f="$1" m c hex n i ct
  m=$(head -c 4 "$f" 2>/dev/null | od -An -tx1 | tr -d ' \n')
  case "$m" in
    7f454c46) echo ELF ;;
    cffaedfe) # MH_MAGIC_64, little-endian; cputype at offset 4 (ARM64 = 0x0100000C)
      c=$(tail -c +5 "$f" | head -c 4 | od -An -tx1 | tr -d ' \n')
      if [ "$c" = "0c000001" ]; then echo MACHO_ARM64; else echo MACHO_OTHER; fi ;;
    cefaedfe) echo MACHO_OTHER ;; # MH_MAGIC_32
    cafebabe) # fat/universal binary; big-endian arch table, 20 bytes per arch
      hex=$(tail -c +5 "$f" | head -c 4 | od -An -tx1 | tr -d ' \n')
      n=0
      if [[ "$hex" =~ ^[0-9a-f]{8}$ ]]; then n=$((16#$hex)); fi
      if [ "$n" -gt 0 ] && [ "$n" -le 8 ]; then
        for ((i = 0; i < n; i++)); do
          ct=$(dd if="$f" bs=1 skip=$((8 + 20 * i)) count=4 2>/dev/null | od -An -tx1 | tr -d ' \n')
          if [ "$ct" = "0100000c" ]; then echo MACHO_ARM64; return; fi
        done
      fi
      echo MACHO_OTHER ;;
    *) echo UNKNOWN ;;
  esac
}

# ---------- conversion ----------

convert_deb() {
  local deb="$1" outdir="$2"
  local name; name=$(basename "$deb"); name="${name%.deb}"
  mkdir -p "$outdir"
  local report="$outdir/${name}-report.md"
  local work; work=$(mktemp -d)
  {
    echo "## $name"
    echo ""
  } > "$report"

  # 1) ar container
  if ! (cd "$work" && ar x "$deb" 2>"$work/ar.err"); then
    echo "Not a valid Debian package (the ar container is missing or corrupt)." | tee -a "$report"
    return 1
  fi
  local datafile
  datafile=$(cd "$work" && ls data.tar* 2>/dev/null | head -n1)
  if [ -z "$datafile" ]; then
    echo "No data.tar* member found — not a Debian package." | tee -a "$report"
    return 1
  fi

  # 2) payload extraction (GNU tar auto-detects gzip/xz/bzip2/zstd/lzma)
  if ! mkdir "$work/payload" 2>/dev/null || \
     ! tar -xf "$work/$datafile" -C "$work/payload" 2>"$work/tar.err"; then
    echo "Could not extract $datafile (unsupported compression or corrupt member): $(tr '\n' ' ' < "$work/tar.err")" | tee -a "$report"
    return 1
  fi

  # 3) classification
  local apps tweakcount elf=0 arm64=0 other=0 checked=0 kind size f app
  apps=$(cd "$work/payload" && find . -type d -name '*.app' | sed 's|^\./||')
  tweakcount=$(cd "$work/payload" && find . -path '*MobileSubstrate*' | wc -l)
  while IFS= read -r -d '' f; do
    size=$(stat -c%s "$f" 2>/dev/null || echo 0)
    [ "$size" -gt 16777216 ] && continue
    case "$f" in
      *.dylib|*.so|*.app/*|*/MacOS/*|*/bin/*|*/sbin/*|*/libexec/*) ;;
      *) continue ;;
    esac
    checked=$((checked + 1))
    [ "$checked" -gt 200 ] && break
    kind=$(bin_kind "$f")
    case "$kind" in
      ELF) elf=$((elf + 1)) ;;
      MACHO_ARM64) arm64=$((arm64 + 1)) ;;
      MACHO_OTHER) other=$((other + 1)) ;;
    esac
  done < <(cd "$work/payload" && find . -type f -print0)

  {
    echo "- App bundles: ${apps:-none}"
    echo "- Binaries checked: $checked — ARM64 Mach-O: $arm64, other Mach-O: $other, ELF: $elf"
    echo "- MobileSubstrate files: $tweakcount"
    echo ""
  } >> "$report"

  # 4) honest verdict
  if [ "$elf" -gt 0 ]; then
    echo "Contains $elf Linux ELF binary(ies) — Linux code cannot run on iOS. Not converted." | tee -a "$report"
    return 1
  fi
  if [ -z "$apps" ]; then
    if [ "$tweakcount" -gt 0 ]; then
      echo "MobileSubstrate tweak ($tweakcount files) — needs a jailbreak; cannot run on a stock device. Not converted." | tee -a "$report"
    else
      echo "No .app bundle in the payload — CLI tool, library or data package. Not converted." | tee -a "$report"
    fi
    return 1
  fi
  if [ "$arm64" -eq 0 ]; then
    echo "App bundle(s) found but no ARM64 Mach-O code detected — likely an Intel/PPC Mac build. Not converted." | tee -a "$report"
    return 1
  fi

  # 5) package unsigned .ipa
  local built=0 appname ipafile bundle
  while IFS= read -r app; do
    [ -z "$app" ] && continue
    bundle=$(basename "$app")
    appname="${bundle%.app}"
    rm -rf "$work/ipa"; mkdir -p "$work/ipa/Payload"
    cp -R "$work/payload/$app" "$work/ipa/Payload/$bundle"
    if [ ! -f "$work/ipa/Payload/$bundle/Info.plist" ]; then
      echo "Note: the bundle has no Info.plist — v1's plist repair is out of scope here; the sideloader may need one." >> "$report"
    fi
    ipafile="$outdir/${name}-${appname}-unsigned.ipa"
    (cd "$work/ipa" && zip -qry "$ipafile" Payload)
    built=$((built + 1))
    echo "Built ${name}-${appname}-unsigned.ipa (unsigned — your own signature is applied at sideload time)." | tee -a "$report"
  done <<< "$apps"

  [ "$built" -gt 0 ] || { echo "No bundle could be packaged." | tee -a "$report"; return 1; }
  return 0
}

# ---------- self-test (synthetic ARM64 app bundle) ----------

run_selftest() {
  log "### Built-in self-test"
  local st; st=$(mktemp -d)
  mkdir -p "$st/payload/TestApp.app/Contents/MacOS"
  printf '\xcf\xfa\xed\xfe\x0c\x00\x00\x01\x02\x00\x00\x00\x68\x00\x00\x00\x07\x00\x00\x00\x00\x00\x00\x01' > "$st/payload/TestApp.app/Contents/MacOS/TestApp"
  printf '<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>TestApp</string></dict></plist>' > "$st/payload/TestApp.app/Info.plist"
  printf '2.0\n' > "$st/debian-binary"
  (cd "$st/payload" && tar -cf "$st/data.tar" .)
  (cd "$st" && ar rc selftest.deb debian-binary data.tar)
  if convert_deb "$st/selftest.deb" "$OUTDIR_ABS/selftest" && ls "$OUTDIR_ABS/selftest"/*-unsigned.ipa >/dev/null 2>&1; then
    log "Self-test passed — a synthetic ARM64 app bundle produced an unsigned .ipa."
  else
    log "Self-test FAILED — the pipeline did not produce an .ipa from a known-good package."
    exit 1
  fi
}

# ---------- main ----------

shopt -s nullglob
debs=(incoming/*.deb)

# optional direct URL (workflow_dispatch input)
if [ -n "${DEB_URL:-}" ]; then
  mkdir -p incoming
  fn=$(basename "${DEB_URL%%\?*}")
  if curl -fsSL "$DEB_URL" -o "incoming/$fn"; then
    debs+=("incoming/$fn")
  else
    log "Could not download $DEB_URL"
    echo "any=false" >> "$OUT_FILE"
    exit 1
  fi
fi

if [ "${#debs[@]}" -eq 0 ]; then
  log "### Nothing to build"
  log "No .deb files in incoming/ — drop one there via GitHub's web upload, or dispatch the workflow with a .deb URL."
  echo "any=false" >> "$OUT_FILE"
  echo "nothing=true" >> "$OUT_FILE"
  exit 0
fi

ok=0; fail=0
for deb in "${debs[@]}"; do
  log "### Converting $(basename "$deb")"
  if convert_deb "$deb" "$OUTDIR_ABS"; then ok=$((ok + 1)); else fail=$((fail + 1)); fi
done

if [ -f incoming/.selftest ]; then
  run_selftest
fi

log ""
log "**Converted:** $ok package(s) — **rejected honestly:** $fail."

if [ "$ok" -gt 0 ]; then
  echo "any=true" >> "$OUT_FILE"
else
  echo "any=false" >> "$OUT_FILE"
fi
exit 0
