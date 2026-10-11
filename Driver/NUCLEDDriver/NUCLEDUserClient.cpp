#include "NUCLEDUserClient.hpp"
#include "NUCLEDDriver.hpp"

OSDefineMetaClassAndStructors(NUCLEDUserClient, IOUserClient)

namespace {
constexpr UInt32 kWireSize = 4;

const IOExternalMethodDispatch kMethods[] = {
    {NUCLEDUserClient::readInventoryAction, 0, 0, 0, kWireSize},
    {NUCLEDUserClient::readIndicatorAction, 0, kWireSize, 0, kWireSize},
    {NUCLEDUserClient::setIndicatorAction, 0, kWireSize, 0, 0}
};

bool hasOnlyFourBytePayload(IOExternalMethodArguments *arguments) {
    return arguments != nullptr && arguments->structureInput != nullptr &&
           arguments->structureInputSize == kWireSize;
}
}

bool NUCLEDUserClient::initWithTask(task_t owningTask, void *securityID, UInt32 type,
                                    OSDictionary *properties) {
    if (!IOUserClient::initWithTask(owningTask, securityID, type, properties)) return false;
    mDriver = nullptr;
    return true;
}

bool NUCLEDUserClient::start(IOService *provider) {
    if (!IOUserClient::start(provider)) return false;
    mDriver = OSDynamicCast(NUCLEDDriver, provider);
    if (mDriver == nullptr) return false;
    mDriver->retain();
    return true;
}

void NUCLEDUserClient::stop(IOService *provider) {
    if (mDriver != nullptr) {
        mDriver->release();
        mDriver = nullptr;
    }
    IOUserClient::stop(provider);
}

IOReturn NUCLEDUserClient::clientClose(void) {
    terminate(); // drops this connection and its retained provider
    return kIOReturnSuccess;
}

IOReturn NUCLEDUserClient::externalMethod(uint32_t selector,
                                          IOExternalMethodArguments *arguments,
                                          IOExternalMethodDispatch *,
                                          OSObject *, void *) {
    if (selector >= (sizeof(kMethods) / sizeof(kMethods[0]))) return kIOReturnUnsupported;
    return IOUserClient::externalMethod(selector, arguments,
                                        const_cast<IOExternalMethodDispatch *>(&kMethods[selector]),
                                        this, nullptr);
}

IOReturn NUCLEDUserClient::readInventoryAction(OSObject *target, void *,
                                               IOExternalMethodArguments *arguments) {
    NUCLEDUserClient *client = OSDynamicCast(NUCLEDUserClient, target);
    if (client == nullptr || client->mDriver == nullptr || arguments == nullptr ||
        arguments->structureOutput == nullptr || arguments->structureOutputSize != kWireSize) {
        return kIOReturnBadArgument;
    }
    UInt8 present = 0;
    UInt8 disable = 0;
    UInt8 powerState = 0;
    IOReturn status = client->mDriver->readInventory(&present, &disable, &powerState);
    if (status != kIOReturnSuccess) return status;
    UInt8 *output = static_cast<UInt8 *>(arguments->structureOutput);
    output[0] = 1; // protocol version
    output[1] = present;
    output[2] = disable;
    output[3] = powerState;
    return kIOReturnSuccess;
}

IOReturn NUCLEDUserClient::readIndicatorAction(OSObject *target, void *,
                                               IOExternalMethodArguments *arguments) {
    NUCLEDUserClient *client = OSDynamicCast(NUCLEDUserClient, target);
    if (client == nullptr || client->mDriver == nullptr || !hasOnlyFourBytePayload(arguments) ||
        arguments->structureOutput == nullptr || arguments->structureOutputSize != kWireSize) {
        return kIOReturnBadArgument;
    }
    const UInt8 *input = static_cast<const UInt8 *>(arguments->structureInput);
    if (input[1] != 0 || input[2] != 0 || input[3] != 0) return kIOReturnBadArgument;
    UInt8 indicator = 0;
    IOReturn status = client->mDriver->readIndicator(input[0], &indicator);
    if (status != kIOReturnSuccess) return status;
    UInt8 *output = static_cast<UInt8 *>(arguments->structureOutput);
    output[0] = indicator;
    output[1] = output[2] = output[3] = 0;
    return kIOReturnSuccess;
}

IOReturn NUCLEDUserClient::setIndicatorAction(OSObject *target, void *,
                                              IOExternalMethodArguments *arguments) {
    NUCLEDUserClient *client = OSDynamicCast(NUCLEDUserClient, target);
    if (client == nullptr || client->mDriver == nullptr || !hasOnlyFourBytePayload(arguments)) {
        return kIOReturnBadArgument;
    }
    const UInt8 *input = static_cast<const UInt8 *>(arguments->structureInput);
    if (input[2] != 0 || input[3] != 0) return kIOReturnBadArgument;
    return client->mDriver->setIndicator(input[0], input[1]);
}
