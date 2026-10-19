'use strict';

// Deb2IPA web inspector — parses .deb packages entirely in the browser.
//
// Container: Unix ar (60-byte member headers).
// Members:   debian-binary, control.tar.{gz,xz,zst,bz2,lzma}, data.tar.{...}
// Backends:  gzip members (and plain tar) are handled natively with
//            DecompressionStream + a small tar reader. Other compressions
//            (xz, zstd, bzip2, lzma) lazy-load libarchive.js (WASM) from a
//            CDN as a fallback backend. Nothing is ever uploaded.

var CDNS = [
  'https://cdn.jsdelivr.net/npm/libarchive.js@2.0.2/dist/',
  'https://unpkg.com/libarchive.js@2.0.2/dist/'
];
var libarchivePromise = null;
var workerBlobUrl = null;

function loadLibarchive() {
  if (libarchivePromise) return libarchivePromise;
  libarchivePromise = (async function () {
    var lastErr = null;
    for (var i = 0; i < CDNS.length; i++) {
      var base = CDNS[i];
      try {
        var mod = await import(base + 'libarchive.js');
        var res = await fetch(base + 'worker-bundle.js');
        if (!res.ok) throw new Error('HTTP ' + res.status + ' fetching worker-bundle.js');
        var src = await res.text();
        // The worker resolves libarchive.wasm relative to its own script URL.
        // We instantiate the worker from a blob URL, so pin the wasm to the CDN.
        src = src.replace(/(['"])libarchive\.wasm\1/g, function (m, q) {
          return q + base + 'libarchive.wasm' + q;
        });
        workerBlobUrl = URL.createObjectURL(new Blob([src], { type: 'text/javascript' }));
        mod.Archive.init({
          getWorker: function () { return new Worker(workerBlobUrl, { type: 'module' }); }
        });
        return mod.Archive;
      } catch (e) {
        lastErr = e;
      }
    }
    throw new Error('Could not load the archive helper from any CDN (' +
      (lastErr && lastErr.message ? lastErr.message : 'unknown error') + ').');
  })();
  return libarchivePromise;
}

// ---------- small utilities ----------

function $(id) { return document.getElementById(id); }

function fmtSize(n) {
  if (typeof n !== 'number' || isNaN(n) || n < 0) return '—';
  if (n < 1024) return n + ' B';
  var units = ['KiB', 'MiB', 'GiB'];
  var i = -1;
  do { n /= 1024; i++; } while (n >= 1024 && i < units.length - 1);
  return (n >= 100 ? Math.round(n) : n.toFixed(1)) + ' ' + units[i];
}

function esc(s) {
  return String(s).replace(/[&<>"']/g, function (c) {
    return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
  });
}

function normPath(p) {
  return String(p).replace(/^\.\//, '').replace(/^\//, '');
}

function basename(p) {
  var i = p.lastIndexOf('/');
  return i === -1 ? p : p.slice(i + 1);
}

function ascii(bytes) {
  var s = '';
  for (var i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i]);
  return s;
}

function fmtList(arr) {
  return arr.slice(0, 5).join(', ') + (arr.length > 5 ? ' and ' + (arr.length - 5) + ' more' : '');
}

function setStatus(msg) {
  $('status').hidden = false;
  $('statusText').textContent = msg;
}

function showError(msg) {
  $('status').hidden = true;
  var box = $('error');
  box.hidden = false;
  box.innerHTML = '<div class="err">' + esc(msg) + '</div>';
}

// ---------- ar container ----------

async function parseAr(file) {
  var magic = ascii(new Uint8Array(await file.slice(0, 8).arrayBuffer()));
  if (magic !== '!<arch>\n') {
    throw new Error('Not a Debian package: the ar archive magic is missing. Is this really a .deb file?');
  }
  var members = [];
  var off = 8;
  while (off + 60 <= file.size) {
    var head = ascii(new Uint8Array(await file.slice(off, off + 60).arrayBuffer()));
    var name = head.slice(0, 16).trim().replace(/\/$/, '');
    var size = parseInt(head.slice(48, 58).trim(), 10);
    if (!name || !isFinite(size)) {
      throw new Error('Corrupt ar member header at byte ' + off + '.');
    }
    members.push({ name: name, start: off + 60, size: size });
    off += 60 + size + (size % 2);
  }
  return members;
}

// ---------- tar (native blob backend) ----------

function makeChunkReader(blob) {
  var CHUNK = 1 << 20;
  var bufStart = -1;
  var buf = new Uint8Array(0);
  return async function read(off, len) {
    if (off < bufStart || off + len > bufStart + buf.length) {
      bufStart = off;
      var end = Math.min(off + Math.max(len, CHUNK), blob.size);
      buf = new Uint8Array(await blob.slice(bufStart, end).arrayBuffer());
    }
    return buf.subarray(off - bufStart, off - bufStart + len);
  };
}

function field(bytes, off, len) {
  var s = '';
  for (var i = off; i < off + len && i < bytes.length; i++) {
    if (bytes[i] === 0) break;
    s += String.fromCharCode(bytes[i]);
  }
  return s;
}

function isZeroBlock(b) {
  for (var i = 0; i < b.length; i++) if (b[i] !== 0) return false;
  return true;
}

async function parseTarBlob(blob) {
  var read = makeChunkReader(blob);
  var entries = [];
  var off = 0;
  var longName = null;
  var paxPath = null;
  while (off + 512 <= blob.size) {
    var h = await read(off, 512);
    if (h.length < 512 || isZeroBlock(h)) break;
    var name = field(h, 0, 100);
    var prefix = field(h, 345, 155);
    var typeflag = String.fromCharCode(h[156] || 48);
    var size = 0;
    if (h[124] & 0x80) {
      // GNU base-256 encoded size
      size = h[124] & 0x7f;
      for (var k = 125; k < 136; k++) size = size * 256 + h[k];
    } else {
      var sizeStr = field(h, 124, 12).trim();
      if (sizeStr) size = parseInt(sizeStr, 8) || 0;
    }
    var dataOff = off + 512;
    var advance = dataOff + Math.ceil(size / 512) * 512;

    if (typeflag === 'L') {
      // GNU long name: the data holds the name of the *next* entry
      var nb = new Uint8Array(await blob.slice(dataOff, dataOff + Math.min(size, 4096)).arrayBuffer());
      longName = new TextDecoder().decode(nb).replace(/\0+$/, '');
      off = advance;
      continue;
    }
    if (typeflag === 'x' || typeflag === 'X' || typeflag === 'g' || typeflag === 'K') {
      // pax / GNU extension header (grab a pax path override if present)
      if (size <= 8192) {
        var pb = new TextDecoder().decode(new Uint8Array(await blob.slice(dataOff, dataOff + size).arrayBuffer()));
        var m = pb.match(/\d+ path=([^\n]*)/);
        if (m) paxPath = m[1];
      }
      off = advance;
      continue;
    }
    if (longName) { name = longName; longName = null; }
    if (paxPath) { name = paxPath; paxPath = null; }
    if (prefix && !longName) name = prefix + '/' + name;

    var path = normPath(name);
    var type = (typeflag === '5') ? 'dir' : (typeflag === '1' || typeflag === '2') ? 'link' : 'file';
    if (path && type !== 'dir') {
      entries.push({ path: path, size: size, type: type, off: dataOff });
    }
    off = advance;
    if (entries.length > 20000) break; // safety valve
  }
  return { entries: entries, blob: blob };
}

function blobSource(tar) {
  return {
    kind: 'blob',
    entries: tar.entries,
    readText: async function (entry) {
      var ab = await tar.blob.slice(entry.off, entry.off + entry.size).arrayBuffer();
      return new TextDecoder().decode(new Uint8Array(ab));
    },
    readBlob: async function (entry) {
      return tar.blob.slice(entry.off, entry.off + entry.size);
    },
    readHead: async function (entry, n) {
      return new Uint8Array(await tar.blob.slice(entry.off, entry.off + n).arrayBuffer());
    }
  };
}

// ---------- libarchive backend (xz / zstd / bzip2 / lzma) ----------

async function libarchiveSource(file, member) {
  var Archive = await loadLibarchive();
  var raw = file.slice(member.start, member.start + member.size);
  var f = new File([raw], member.name, { type: 'application/octet-stream' });
  var archive = await Archive.open(f);
  var arr = await archive.getFilesArray();
  var entries = [];
  for (var i = 0; i < arr.length; i++) {
    var cf = arr[i].file;
    var dir = arr[i].path || '';
    var p = dir === '' ? cf.name : (dir.slice(-1) === '/' ? dir + cf.name : dir + '/' + cf.name);
    entries.push({ path: normPath(p), size: cf.size, type: 'file', cf: cf });
  }
  return {
    kind: 'libarchive',
    entries: entries,
    archive: archive,
    readText: async function (entry) {
      var b = await entry.cf.extract();
      return new TextDecoder().decode(new Uint8Array(await b.arrayBuffer()));
    },
    readBlob: async function (entry) {
      return await entry.cf.extract();
    },
    readHead: async function (entry, n) {
      var b = await entry.cf.extract();
      return new Uint8Array(await b.slice(0, n).arrayBuffer());
    }
  };
}

async function openMember(file, member) {
  var name = member.name;
  var m = name.match(/\.(gz|bz2|xz|lzma|zst|z)$/);
  if (m) {
    if (m[1] === 'gz' && typeof DecompressionStream !== 'undefined') {
      var raw = file.slice(member.start, member.start + member.size);
      var stream = raw.stream().pipeThrough(new DecompressionStream('gzip'));
      var blob = await new Response(stream).blob();
      return blobSource(await parseTarBlob(blob));
    }
    try {
      return await libarchiveSource(file, member);
    } catch (e) {
      throw new Error('Could not decode ' + name + ' (' + m[1] + ' compression). ' +
        'The browser has no native decoder for it and the libarchive.js helper could not be used: ' +
        ((e && e.message) ? e.message : e));
    }
  }
  if (name.indexOf('.tar') !== -1) {
    // uncompressed tar member (data.tar / control.tar)
    var rawBlob = file.slice(member.start, member.start + member.size);
    return blobSource(await parseTarBlob(rawBlob));
  }
  throw new Error('Unrecognised archive member: ' + name);
}

// ---------- control file parsing ----------

function parseControl(text) {
  var fields = {};
  var lines = text.split(/\r?\n/);
  var curKey = null;
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i];
    if (!line) { curKey = null; continue; }
    if (line.charAt(0) === ' ' || line.charAt(0) === '\t') {
      if (curKey) fields[curKey] += '\n' + line.replace(/^[ \t]+/, '');
      continue;
    }
    var idx = line.indexOf(':');
    if (idx === -1) continue;
    curKey = line.slice(0, idx).trim();
    fields[curKey] = line.slice(idx + 1).trim();
  }
  return fields;
}

// ---------- classification ----------

function classifyMagic(h) {
  if (h.length >= 4 && h[0] === 0x7f && h[1] === 0x45 && h[2] === 0x4c && h[3] === 0x46) {
    return { kind: 'elf' };
  }
  if (h.length >= 8 && h[0] === 0xCA && h[1] === 0xFE && h[2] === 0xBA && h[3] === 0xBE) {
    // fat / universal Mach-O; arch table is big-endian, 20 bytes per arch
    var arm64 = false;
    var nfat = (h[4] << 24) | (h[5] << 16) | (h[6] << 8) | h[7];
    if (nfat > 0 && nfat <= 5) {
      for (var i = 0; i < nfat; i++) {
        var c = 8 + i * 20;
        if (h[c] === 0x01 && h[c + 1] === 0x00 && h[c + 2] === 0x00 && h[c + 3] === 0x0C) arm64 = true;
      }
    }
    return { kind: 'macho', arm64: arm64 };
  }
  if (h.length >= 8 && h[0] === 0xCF && h[1] === 0xFA && h[2] === 0xED && h[3] === 0xFE) {
    // MH_MAGIC_64 little-endian; cputype at offset 4 (ARM64 = 0x0100000C LE)
    return { kind: 'macho', arm64: h[4] === 0x0C && h[5] === 0x00 && h[6] === 0x00 && h[7] === 0x01 };
  }
  if (h.length >= 4 && h[0] === 0xCE && h[1] === 0xFA && h[2] === 0xED && h[3] === 0xFE) {
    return { kind: 'macho', arm64: false }; // 32-bit
  }
  return null;
}

async function classify(source, controlEntries) {
  var stats = { apps: [], tweaks: 0, dylibs: 0, elf: 0, machoArm64: 0, machoOther: 0, maintainerScripts: [] };
  var seenApp = {};
  var i, e, p;
  for (i = 0; i < source.entries.length; i++) {
    e = source.entries[i];
    p = e.path;
    var ma = p.match(/(^|\/)([^\/]+\.app)\//i);
    if (ma && !seenApp[ma[2]]) { seenApp[ma[2]] = true; stats.apps.push(ma[2]); }
    if (/(^|\/)(usr\/)?lib(rary)?\/MobileSubstrate\//i.test(p)) stats.tweaks++;
    if (/\.dylib$/i.test(p)) stats.dylibs++;
  }
  if (controlEntries) {
    for (i = 0; i < controlEntries.length; i++) {
      var n = basename(controlEntries[i].path);
      if (/^(postinst|preinst|prerm|postrm|config|triggers)$/.test(n)) stats.maintainerScripts.push(n);
    }
  }
  // sniff magic bytes of plausible executables (cap: 40 files, 16 MiB each)
  var candidates = [];
  for (i = 0; i < source.entries.length && candidates.length < 40; i++) {
    e = source.entries[i];
    p = e.path;
    if (e.type !== 'file' || !e.size || e.size > 16 * 1024 * 1024) continue;
    if (/\.(dylib|so)$/i.test(p) ||
        /(^|\/)[^\/]+\.app\//i.test(p) ||
        /(^|\/)Contents\/MacOS\//i.test(p) ||
        /(^|\/)(bin|sbin|libexec)\//i.test(p)) {
      candidates.push(e);
    }
  }
  for (i = 0; i < candidates.length; i++) {
    var h = null;
    try { h = await source.readHead(candidates[i], 112); } catch (err) { h = null; }
    if (!h) continue;
    var v = classifyMagic(h);
    if (!v) continue;
    if (v.kind === 'elf') stats.elf++;
    else if (v.arm64) stats.machoArm64++;
    else stats.machoOther++;
  }
  return stats;
}

function verdict(stats) {
  var level, title, reasons = [];
  if (stats.elf > 0) {
    level = 'bad';
    title = 'Contains Linux ELF binaries — cannot run on iOS';
    reasons.push('Found ' + stats.elf + ' ELF executable(s). Linux binaries cannot execute on iOS; the v1 pipeline will reject this package instead of shipping a broken IPA.');
  } else if (stats.apps.length > 0) {
    if (stats.machoArm64 > 0) {
      level = 'good';
      title = 'App bundle with ARM64 code — a conversion candidate';
      reasons.push('Found app bundle(s): ' + fmtList(stats.apps) + '.');
      reasons.push('ARM64 Mach-O executables were detected — this is exactly the payload the v1 deb→ipa pipeline is built to convert.');
    } else {
      level = 'warn';
      title = 'App bundle found, but no ARM64 code detected';
      reasons.push('Found app bundle(s): ' + fmtList(stats.apps) + '.');
      reasons.push('No ARM64 Mach-O slice was detected in the sampled binaries — this may be an Intel/PPC Mac build or a data-only bundle.');
    }
  } else if (stats.tweaks > 0) {
    level = 'warn';
    title = 'Jailbreak tweak — needs MobileSubstrate, not a standalone app';
    reasons.push('The payload installs ' + stats.tweaks + ' file(s) into a MobileSubstrate directory. Substrate tweaks hook other processes through code injection, which stock iOS forbids — they cannot run on a non-jailbroken device.');
  } else {
    level = 'warn';
    title = 'No app bundle found — likely a CLI tool, library or data package';
    reasons.push('The payload contains no .app bundle, so there is nothing to turn into a sideloadable .ipa.');
  }
  if (stats.maintainerScripts.length) {
    reasons.push('Maintainer scripts present (' + fmtList(stats.maintainerScripts) + ') — v1 will translate or flag them, never execute them.');
  }
  return { level: level, title: title, reasons: reasons };
}

// ---------- rendering ----------

function renderVerdict(v) {
  var el = $('verdict');
  el.className = 'card verdict ' + v.level;
  var html = ['<h3>' + esc(v.title) + '</h3><ul>'];
  for (var i = 0; i < v.reasons.length; i++) html.push('<li>' + esc(v.reasons[i]) + '</li>');
  html.push('</ul>');
  el.innerHTML = html.join('');
}

function renderPackage(fields) {
  if (!fields || !fields.Package) { $('package').hidden = true; return; }
  var keys = ['Package', 'Version', 'Architecture', 'Installed-Size', 'Maintainer', 'Depends'];
  var html = [];
  for (var i = 0; i < keys.length; i++) {
    var k = keys[i];
    if (!fields[k]) continue;
    var val = fields[k];
    if (k === 'Installed-Size') {
      var kb = parseInt(val, 10);
      val = val + ' (' + (isFinite(kb) ? fmtSize(kb * 1024) : '?') + ')';
    }
    html.push('<dt>' + esc(k) + '</dt><dd>' + esc(val) + '</dd>');
  }
  if (fields.Description) {
    var d = fields.Description.split('\n');
    html.push('<dt>Description</dt><dd>' + esc(d[0]) +
      (d.length > 1 ? '<br><span style="color:var(--sub)">' + esc(d.slice(1).join(' ')) + '</span>' : '') + '</dd>');
  }
  $('pkgFields').innerHTML = html.join('');
  $('package').hidden = false;
}

function renderChips(stats, source, count, totalSize) {
  var chips = [];
  chips.push(count + ' files');
  chips.push(fmtSize(totalSize) + ' uncompressed');
  if (stats.apps.length) chips.push(stats.apps.length + ' .app bundle' + (stats.apps.length > 1 ? 's' : ''));
  if (stats.machoArm64) chips.push(stats.machoArm64 + ' ARM64 Mach-O');
  if (stats.machoOther) chips.push(stats.machoOther + ' non-ARM64 Mach-O');
  if (stats.elf) chips.push(stats.elf + ' Linux ELF');
  if (stats.tweaks) chips.push(stats.tweaks + ' MobileSubstrate file' + (stats.tweaks > 1 ? 's' : ''));
  if (stats.dylibs) chips.push(stats.dylibs + ' .dylib');
  if (stats.maintainerScripts.length) chips.push('maintainer scripts: ' + stats.maintainerScripts.join(', '));
  chips.push(source.kind === 'blob' ? 'decoded natively (gzip)' : 'decoded via libarchive.js helper');
  $('chips').innerHTML = chips.map(function (c) {
    return '<span class="chip">' + esc(c) + '</span>';
  }).join('');
}

function renderMembers(members) {
  var html = [];
  for (var i = 0; i < members.length; i++) {
    var m = members[i];
    html.push('<div class="row"><div class="path">' + esc(m.name) + '</div>' +
      '<div class="meta">' + fmtSize(m.size) +
      ' <button class="dl dlm" data-i="' + i + '">Download</button></div></div>');
  }
  $('memberList').innerHTML = html.join('');
}

var MAX_LIST = 500;

function renderFileList() {
  if (!currentData) return;
  var q = $('filter').value.trim().toLowerCase();
  var list = currentData.source.entries;
  var shown = 0;
  var matched = 0;
  var html = [];
  for (var i = 0; i < list.length; i++) {
    var e = list[i];
    if (q && e.path.toLowerCase().indexOf(q) === -1) continue;
    matched++;
    if (shown >= MAX_LIST) continue;
    shown++;
    html.push('<div class="row"><div class="path"><span class="tag">' + e.type + '</span>' +
      esc(e.path) + '</div><div class="meta">' + fmtSize(e.size) +
      ' <button class="dl dlf" data-i="' + i + '">Download</button></div></div>');
  }
  if (!matched) {
    html.push('<div class="more">No files match the filter.</div>');
  } else if (matched > shown) {
    html.push('<div class="more">Showing ' + shown + ' of ' + matched + ' matching files — use the filter to narrow down.</div>');
  }
  $('fileList').innerHTML = html.join('');
}

function downloadBlob(blob, name) {
  var url = URL.createObjectURL(blob);
  var a = document.createElement('a');
  a.href = url;
  a.download = name || 'file';
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(function () { URL.revokeObjectURL(url); }, 20000);
}

// ---------- main flow ----------

var currentFile = null;
var currentData = null;
var currentSources = [];

async function closeSources() {
  for (var i = 0; i < currentSources.length; i++) {
    var s = currentSources[i];
    if (s.kind === 'libarchive' && s.archive) {
      try { await s.archive.close(); } catch (e) { /* already closed */ }
    }
  }
  currentSources = [];
}

async function run(file) {
  $('error').hidden = true;
  $('results').hidden = true;
  await closeSources();
  currentFile = file;
  currentData = null;
  try {
    setStatus('Reading archive headers…');
    var members = await parseAr(file);
    if (!members.length) throw new Error('The file has an ar magic header but no members — not a valid Debian package.');

    var controlMember = null, dataMember = null, binaryMember = null;
    for (var i = 0; i < members.length; i++) {
      var n = members[i].name;
      if (n === 'debian-binary') binaryMember = members[i];
      else if (n.indexOf('control.tar') === 0) controlMember = members[i];
      else if (n.indexOf('data.tar') === 0) dataMember = members[i];
    }
    if (!dataMember) throw new Error('No data.tar* member found — this does not look like a Debian package.');

    var debVersion = null;
    if (binaryMember) {
      var vb = new TextDecoder().decode(
        new Uint8Array(await file.slice(binaryMember.start, binaryMember.start + binaryMember.size).arrayBuffer()));
      debVersion = vb.trim();
    }

    var controlFields = null;
    var controlEntries = null;
    if (controlMember) {
      setStatus('Parsing control files…');
      var csrc = await openMember(file, controlMember);
      currentSources.push(csrc);
      controlEntries = csrc.entries;
      for (i = 0; i < csrc.entries.length; i++) {
        if (normPath(csrc.entries[i].path) === 'control') {
          controlFields = parseControl(await csrc.readText(csrc.entries[i]));
          break;
        }
      }
    }

    setStatus('Scanning payload…');
    var dsrc = await openMember(file, dataMember);
    currentSources.push(dsrc);
    if (!dsrc.entries.length) {
      throw new Error('The payload archive (' + dataMember.name + ') could not be decoded. Its compression may be unsupported or the file is corrupt.');
    }

    setStatus('Sniffing binaries…');
    var stats = await classify(dsrc, controlEntries);
    var totalSize = 0;
    for (i = 0; i < dsrc.entries.length; i++) totalSize += dsrc.entries[i].size || 0;
    var v = verdict(stats);
    if (debVersion && debVersion !== '2.0') {
      v.reasons.unshift('debian-binary declares format version "' + debVersion + '" (expected 2.0) — parsing may be inaccurate.');
    }

    currentData = { file: file, members: members, source: dsrc, stats: stats };

    $('status').hidden = true;
    $('results').hidden = false;
    renderVerdict(v);
    renderPackage(controlFields);
    renderChips(stats, dsrc, dsrc.entries.length, totalSize);
    renderMembers(members);
    $('filter').value = '';
    renderFileList();
  } catch (e) {
    showError((e && e.message) ? e.message : String(e));
  }
}

// ---------- wiring ----------

$('pick').addEventListener('click', function () { $('file').click(); });

$('file').addEventListener('change', function (ev) {
  var f = ev.target.files && ev.target.files[0];
  ev.target.value = '';
  if (f) run(f);
});

$('filter').addEventListener('input', renderFileList);

document.body.addEventListener('click', async function (ev) {
  var btn = ev.target && ev.target.closest ? ev.target.closest('button.dl') : null;
  if (!btn) return;
  var idx = parseInt(btn.getAttribute('data-i'), 10);
  if (isNaN(idx)) return;
  btn.disabled = true;
  var label = btn.textContent;
  btn.textContent = '…';
  try {
    if (btn.classList.contains('dlm')) {
      var m = currentData.members[idx];
      downloadBlob(currentFile.slice(m.start, m.start + m.size), m.name);
    } else if (btn.classList.contains('dlf')) {
      var e = currentData.source.entries[idx];
      downloadBlob(await currentData.source.readBlob(e), basename(e.path) || 'file');
    }
    btn.textContent = label;
  } catch (err) {
    btn.textContent = 'Failed';
  }
  btn.disabled = false;
});
