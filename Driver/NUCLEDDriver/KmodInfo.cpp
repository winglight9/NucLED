#include <mach/kmod.h>

extern "C" {
// libkmod.a supplies the standard Mach-O __start/__stop entry stubs.
kern_return_t _start(kmod_info_t *info, void *data);
kern_return_t _stop(kmod_info_t *info, void *data);

// I/O Kit owns C++ runtime setup/teardown for this driver. The generic
// libkmod entry stubs therefore have no custom main/antimain callbacks.
__private_extern__ kmod_start_func_t *_realmain = nullptr;
__private_extern__ kmod_stop_func_t *_antimain = nullptr;
__private_extern__ int _kext_apple_cc = __APPLE_CC__;

__attribute__((visibility("default")))
KMOD_EXPLICIT_DECL(com.nucled.driver, "0.1.0", _start, _stop)
}
