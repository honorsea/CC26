// Path-macro compatibility shim.
//
// Rootless builds resolve ROOT_PATH()/ROOT_PATH_NS() to a fixed /var/jb prefix.
// Roothide has no fixed prefix (the jailbreak root is randomised per boot/install),
// so paths must go through jbroot() from libroothide instead.
#ifndef CC26_ROOT_COMPAT_H
#define CC26_ROOT_COMPAT_H

#if defined(THEOS_PACKAGE_SCHEME_ROOTHIDE)
#include <roothide.h>
#ifndef ROOT_PATH
#define ROOT_PATH(path) jbroot(path)
#endif
#ifndef ROOT_PATH_NS
#define ROOT_PATH_NS(path) jbroot(path)
#endif
#else
#include <rootless.h>
#endif

#endif /* CC26_ROOT_COMPAT_H */
