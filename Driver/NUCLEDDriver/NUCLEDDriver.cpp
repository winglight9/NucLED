#include "NUCLEDDriver.hpp"
#include "NUCLEDUserClient.hpp"

#include <IOKit/IOKitKeys.h>
#include <IOKit/acpi/IOACPITypes.h>
#include <libkern/c++/OSData.h>
#include <libkern/c++/OSNumber.h>
#include <libkern/c++/OSString.h>

OSDefineMetaClassAndStructors(NUCLEDDriver, IOService)

namespace {
constexpr UInt8 kWmiMethodQueryLED = 3;
constexpr UInt8 kWmiMethodNewGetLEDStatus = 4;
constexpr UInt8 kWmiMethodSetIndicator = 5;
constexpr UInt8 kActionQueryPresentZones = 0;
constexpr UInt8 kActionQueryIndicatorSupport = 2;
constexpr UInt8 kIndicatorPowerState = 0;
constexpr UInt8 kIndicatorDisable = 6;
constexpr UInt8 kPowerStateMask = 1U << kIndicatorPowerState;
constexpr UInt8 kDisableMask = 1U << kIndicatorDisable;
constexpr UInt8 kKnownZoneMask = 0x7f;
constexpr UInt8 kExpectedWdgFlagsMethod = 0x02;
constexpr UInt8 kExpectedWdgFlagsString = 0x04;
constexpr UInt8 kExpectedWdgFlagsEvent = 0x08;

// WDG GUID bytes use the ACPI/WMI mixed-endian encoding of
// 8C5DA44C-CDC3-46B3-8619-4E26D34390B7.
constexpr UInt8 kNucLEDGuid[16] = {
    0x4c, 0xa4, 0x5d, 0x8c, 0xc3, 0xcd, 0xb3, 0x46,
    0x86, 0x19, 0x4e, 0x26, 0xd3, 0x43, 0x90, 0xb7
};

bool bytesEqual(const UInt8 *left, const UInt8 *right, UInt32 count) {
    for (UInt32 i = 0; i < count; ++i) {
        if (left[i] != right[i]) return false;
    }
    return true;
}

bool readUIDZero(IOACPIPlatformDevice *device) {
    OSObject *result = nullptr;
    if (device->evaluateObject("_UID", &result) != kIOReturnSuccess || result == nullptr) {
        OSSafeReleaseNULL(result);
        return false;
    }

    bool isZero = false;
    if (OSNumber *number = OSDynamicCast(OSNumber, result)) {
        isZero = number->unsigned64BitValue() == 0;
    } else if (OSString *string = OSDynamicCast(OSString, result)) {
        isZero = string->isEqualTo("0");
    }
    result->release();
    return isZero;
}
}

bool NUCLEDDriver::init(OSDictionary *properties) {
    if (!IOService::init(properties)) return false;
    mWmiDevice = nullptr;
    mWmiLock = nullptr;
    mPresentMask = 0;
    mDisableSupportedMask = 0;
    mPowerStateSupportedMask = 0;
    mInventoryInitialized = false;
    for (UInt8 zone = 0; zone < 7; ++zone) mIndicatorSupportMasks[zone] = 0;
    return true;
}

bool NUCLEDDriver::providerIsTarget(IOACPIPlatformDevice *device) {
    if (device == nullptr) return false;
    const char *acpiName = device->getName(gIOACPIPlane);
    if (acpiName == nullptr || acpiName[0] != 'A' || acpiName[1] != 'M' ||
        acpiName[2] != 'W' || acpiName[3] != '0' || acpiName[4] != '\0' ||
        !readUIDZero(device)) {
        return false;
    }

    OSObject *result = nullptr;
    if (device->evaluateObject("_WDG", &result) != kIOReturnSuccess || result == nullptr) {
        OSSafeReleaseNULL(result);
        return false;
    }
    OSData *wdg = OSDynamicCast(OSData, result);
    bool found = false;
    if (wdg != nullptr) {
        const UInt8 *bytes = static_cast<const UInt8 *>(wdg->getBytesNoCopy());
        const UInt32 length = wdg->getLength();
        constexpr UInt32 kWdgRecordLength = 20;
        for (UInt32 offset = 0; bytes != nullptr && offset + kWdgRecordLength <= length;
             offset += kWdgRecordLength) {
            const UInt8 *record = bytes + offset;
            const bool matchingGuid = bytesEqual(record, kNucLEDGuid, sizeof(kNucLEDGuid));
            const bool matchingObject = record[16] == 'A' && record[17] == 'A';
            const bool singleInstance = record[18] == 1;
            const bool methodSupported = (record[19] & kExpectedWdgFlagsMethod) != 0;
            const bool notStringOrEvent =
                (record[19] & (kExpectedWdgFlagsString | kExpectedWdgFlagsEvent)) == 0;
            if (matchingGuid && matchingObject && singleInstance && methodSupported && notStringOrEvent) {
                found = true;
                break;
            }
        }
    }
    result->release();
    if (!found || device->validateObject("WMAA") != kIOReturnSuccess) return false;

    UInt8 input[4] = {kActionQueryPresentZones, 0, 0, 0};
    // This is a read-only probe. A second independent method confirms the
    // GUID is actually backed by the NUC LED management interface.
    OSNumber *zero = OSNumber::withNumber(static_cast<unsigned long long>(0), 32);
    OSNumber *method = OSNumber::withNumber(kWmiMethodQueryLED, 32);
    OSData *payload = OSData::withBytes(input, sizeof(input));
    if (zero == nullptr || method == nullptr || payload == nullptr) {
        OSSafeReleaseNULL(zero);
        OSSafeReleaseNULL(method);
        OSSafeReleaseNULL(payload);
        return false;
    }
    OSObject *parameters[3] = {zero, method, payload};
    OSObject *response = nullptr;
    const IOReturn status = device->evaluateObject("WMAA", &response, parameters, 3, 0);
    zero->release();
    method->release();
    payload->release();
    if (status != kIOReturnSuccess || response == nullptr) {
        OSSafeReleaseNULL(response);
        return false;
    }
    OSData *responseData = OSDynamicCast(OSData, response);
    const bool validResponse = responseData != nullptr && responseData->getLength() >= 2 &&
                               static_cast<const UInt8 *>(responseData->getBytesNoCopy())[0] == 0;
    UInt8 detectedMask = validResponse
        ? static_cast<const UInt8 *>(responseData->getBytesNoCopy())[1] : 0;
    response->release();
    if (!validResponse) return false;
    mPresentMask = detectedMask;
    return (mPresentMask & ~kKnownZoneMask) == 0 && mPresentMask != 0;
}

bool NUCLEDDriver::start(IOService *provider) {
    if (!IOService::start(provider)) return false;
    IOACPIPlatformDevice *device = OSDynamicCast(IOACPIPlatformDevice, provider);
    if (!providerIsTarget(device)) {
        IOService::stop(provider);
        return false;
    }
    mWmiDevice = device;
    mWmiDevice->retain();
    mWmiLock = IOLockAlloc();
    if (mWmiLock == nullptr) {
        mWmiDevice->release();
        mWmiDevice = nullptr;
        IOService::stop(provider);
        return false;
    }

    UInt8 present = 0;
    UInt8 disable = 0;
    UInt8 powerState = 0;
    if (readInventory(&present, &disable, &powerState) != kIOReturnSuccess || present != mPresentMask) {
        IOLockFree(mWmiLock);
        mWmiLock = nullptr;
        mWmiDevice->release();
        mWmiDevice = nullptr;
        IOService::stop(provider);
        return false;
    }
    mPresentMask = present;
    mDisableSupportedMask = disable;
    mPowerStateSupportedMask = powerState;
    mInventoryInitialized = true;
    setProperty("NUCLEDDriverVersion", 1, 32);
    setProperty("NUCLEDPresentMask", mPresentMask, 8);
    setProperty("NUCLEDDisableSupportedMask", mDisableSupportedMask, 8);
    setProperty("NUCLEDPowerStateSupportedMask", mPowerStateSupportedMask, 8);
    registerService();
    return true;
}

void NUCLEDDriver::stop(IOService *provider) {
    if (mWmiLock != nullptr) {
        IOLockFree(mWmiLock);
        mWmiLock = nullptr;
    }
    if (mWmiDevice != nullptr) {
        mWmiDevice->release();
        mWmiDevice = nullptr;
    }
    IOService::stop(provider);
}

IOReturn NUCLEDDriver::newUserClient(task_t owningTask, void *securityID, UInt32 type,
                                     OSDictionary *properties,
                                     IOUserClient **handler) {
    if (handler == nullptr || type != 0) return kIOReturnBadArgument;
    *handler = nullptr;
    if (NUCLEDUserClient::clientHasPrivilege(securityID, kIOClientPrivilegeLocalUser) != kIOReturnSuccess) {
        return kIOReturnNotPermitted;
    }

    NUCLEDUserClient *client = OSTypeAlloc(NUCLEDUserClient);
    if (client == nullptr) return kIOReturnNoMemory;
    if (!client->initWithTask(owningTask, securityID, type, properties)) {
        client->release();
        return kIOReturnNoResources;
    }
    if (!client->attach(this)) {
        client->release();
        return kIOReturnNoResources;
    }
    if (!client->start(this)) {
        client->detach(this);
        client->release();
        return kIOReturnNoResources;
    }
    *handler = client;
    return kIOReturnSuccess;
}

IOReturn NUCLEDDriver::evaluateWMI(UInt8 methodID, const UInt8 input[4], UInt8 output[4]) {
    if (mWmiDevice == nullptr || input == nullptr || output == nullptr) return kIOReturnNotReady;
    OSNumber *zero = OSNumber::withNumber(static_cast<unsigned long long>(0), 32);
    OSNumber *method = OSNumber::withNumber(methodID, 32);
    OSData *payload = OSData::withBytes(input, 4);
    if (zero == nullptr || method == nullptr || payload == nullptr) {
        OSSafeReleaseNULL(zero);
        OSSafeReleaseNULL(method);
        OSSafeReleaseNULL(payload);
        return kIOReturnNoMemory;
    }
    OSObject *parameters[3] = {zero, method, payload};
    OSObject *response = nullptr;
    IOLockLock(mWmiLock);
    IOReturn status = mWmiDevice->evaluateObject("WMAA", &response, parameters, 3, 0);
    IOLockUnlock(mWmiLock);
    zero->release();
    method->release();
    payload->release();
    if (status != kIOReturnSuccess || response == nullptr) {
        OSSafeReleaseNULL(response);
        return status == kIOReturnSuccess ? kIOReturnBadMedia : status;
    }
    OSData *data = OSDynamicCast(OSData, response);
    if (data == nullptr || data->getLength() < 2) {
        response->release();
        return kIOReturnBadMedia;
    }
    const UInt8 *bytes = static_cast<const UInt8 *>(data->getBytesNoCopy());
    if (bytes[0] != 0) {
        response->release();
        return kIOReturnError;
    }
    for (UInt32 i = 0; i < 4; ++i) output[i] = (i < data->getLength()) ? bytes[i] : 0;
    response->release();
    return kIOReturnSuccess;
}

IOReturn NUCLEDDriver::queryByte(UInt8 action, UInt8 zone, UInt8 *value) {
    if (value == nullptr) return kIOReturnBadArgument;
    UInt8 input[4] = {action, zone, 0, 0};
    UInt8 output[4] = {0, 0, 0, 0};
    IOReturn status = evaluateWMI(kWmiMethodQueryLED, input, output);
    if (status == kIOReturnSuccess) *value = output[1];
    return status;
}

IOReturn NUCLEDDriver::readInventory(UInt8 *presentMask, UInt8 *disableSupportedMask,
                                     UInt8 *powerStateSupportedMask) {
    if (presentMask == nullptr || disableSupportedMask == nullptr ||
        powerStateSupportedMask == nullptr) return kIOReturnBadArgument;
    UInt8 present = 0;
    IOReturn status = queryByte(kActionQueryPresentZones, 0, &present);
    if (status != kIOReturnSuccess) return status;
    if (present == 0 || (present & ~kKnownZoneMask) != 0) return kIOReturnUnsupported;

    UInt8 supported = 0;
    UInt8 powerStateSupported = 0;
    UInt8 supportMasks[7] = {0, 0, 0, 0, 0, 0, 0};
    for (UInt8 zone = 0; zone < 7; ++zone) {
        if ((present & (1U << zone)) == 0) continue;
        UInt8 indicators = 0;
        status = queryByte(kActionQueryIndicatorSupport, zone, &indicators);
        if (status != kIOReturnSuccess) return status;
        supportMasks[zone] = indicators;
        if ((indicators & kDisableMask) != 0) supported |= (1U << zone);
        if ((indicators & kPowerStateMask) != 0) powerStateSupported |= (1U << zone);
    }
    if (!mInventoryInitialized) {
        for (UInt8 zone = 0; zone < 7; ++zone) mIndicatorSupportMasks[zone] = supportMasks[zone];
    } else {
        if (present != mPresentMask) return kIOReturnNotReady;
        for (UInt8 zone = 0; zone < 7; ++zone) {
            if (supportMasks[zone] != mIndicatorSupportMasks[zone]) return kIOReturnNotReady;
        }
    }
    *presentMask = present;
    *disableSupportedMask = supported;
    *powerStateSupportedMask = powerStateSupported;
    return kIOReturnSuccess;
}

IOReturn NUCLEDDriver::readIndicator(UInt8 zone, UInt8 *indicator) {
    if (zone >= 7 || indicator == nullptr || (mPresentMask & (1U << zone)) == 0) {
        return kIOReturnBadArgument;
    }
    UInt8 input[4] = {0, zone, 0, 0};
    UInt8 output[4] = {0, 0, 0, 0};
    IOReturn status = evaluateWMI(kWmiMethodNewGetLEDStatus, input, output);
    if (status == kIOReturnSuccess) {
        if (output[1] > 6) return kIOReturnUnsupported;
        *indicator = output[1];
    }
    return status;
}

IOReturn NUCLEDDriver::setIndicator(UInt8 zone, UInt8 indicator) {
    if (zone >= 7 || indicator > 6 || (mPresentMask & (1U << zone)) == 0) {
        return kIOReturnBadArgument;
    }
    if ((mIndicatorSupportMasks[zone] & (1U << indicator)) == 0) {
        return kIOReturnUnsupported;
    }
    UInt8 input[4] = {zone, indicator, 0, 0};
    UInt8 output[4] = {0, 0, 0, 0};
    return evaluateWMI(kWmiMethodSetIndicator, input, output);
}
