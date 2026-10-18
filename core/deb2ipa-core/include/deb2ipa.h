#ifndef DEB2IPA_H
#define DEB2IPA_H

#ifdef __cplusplus
extern "C" {
#endif

/* Version of deb2ipa-core as a nul-terminated string. */
const char *deb2ipa_version(void);

typedef enum {
    DEB2IPA_OK = 0,
    DEB2IPA_NOT_DEB = 1,
    DEB2IPA_UNSUPPORTED_CLASS = 2,
    DEB2IPA_OUT_OF_SPACE = 3,
    DEB2IPA_INTERNAL_ERROR = 4
} deb2ipa_status;

/* Analyze a .deb at the given path.
 * TODO(v1): will return an owned analysis handle (payload class, warnings,
 * dependency map) to be freed with deb2ipa_free_analysis. */
int deb2ipa_analyze(const char *deb_path);

#ifdef __cplusplus
}
#endif

#endif /* DEB2IPA_H */
