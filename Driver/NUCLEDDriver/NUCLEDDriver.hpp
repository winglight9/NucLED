#ifndef NUCLED_DRIVER_HPP
#define NUCLED_DRIVER_HPP

#include <IOKit/IOService.h>
#include <IOKit/IOUserClient.h>
#include <IOKit/acpi/IOACPIPlatformDevice.h>
#include <IOKit/IOLocks.h>

class NUCLEDDriver : public IOService {
    OSDeclareDefaultStructors(NUCLEDDriver)

public:
    bool init(OSDictionary *properties) APPLE_KEXT_OVERRIDE;
    bool start(IOService *provider) APPLE_KEXT_OVERRIDE;
    void stop(IOService *provider) APPLE_KEXT_OVERRIDE;
    IOReturn newUserClient(task_t owningTask, void *securityID, UInt32 type,
                           OSDictionary *properties,
                           LIBKERN_RETURNS_RETAINED IOUserClient **handler) APPLE_KEXT_OVERRIDE;

    // Internal, deliberately narrow WMI accessors. Only the fixed NUC LED
    // method IDs and four-byte argument shape are accepted here.
    IOReturn readInventory(UInt8 *presentMask, UInt8 *disableSupportedMask,
                           UInt8 *powerStateSupportedMask);
    IOReturn readIndicator(UInt8 zone, UInt8 *indicator);
    IOReturn setIndicator(UInt8 zone, UInt8 indicator);

private:
    IOACPIPlatformDevice *mWmiDevice;
    IOLock *mWmiLock;
    UInt8 mPresentMask;
    UInt8 mDisableSupportedMask;
    UInt8 mPowerStateSupportedMask;
    UInt8 mIndicatorSupportMasks[7];
    bool mInventoryInitialized;

    bool providerIsTarget(IOACPIPlatformDevice *device);
    IOReturn evaluateWMI(UInt8 method, const UInt8 input[4], UInt8 output[4]);
    IOReturn queryByte(UInt8 action, UInt8 zone, UInt8 *value);
};

#endif
