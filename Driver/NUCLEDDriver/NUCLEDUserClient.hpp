#ifndef NUCLED_USER_CLIENT_HPP
#define NUCLED_USER_CLIENT_HPP

#include <IOKit/IOUserClient.h>

class NUCLEDDriver;

class NUCLEDUserClient : public IOUserClient {
    OSDeclareDefaultStructors(NUCLEDUserClient)

public:
    bool initWithTask(task_t owningTask, void *securityID, UInt32 type,
                      OSDictionary *properties) APPLE_KEXT_OVERRIDE;
    bool start(IOService *provider) APPLE_KEXT_OVERRIDE;
    void stop(IOService *provider) APPLE_KEXT_OVERRIDE;
    IOReturn clientClose(void) APPLE_KEXT_OVERRIDE;
    IOReturn externalMethod(uint32_t selector, IOExternalMethodArguments *arguments,
                            IOExternalMethodDispatch *dispatch = nullptr,
                            OSObject *target = nullptr,
                            void *reference = nullptr) APPLE_KEXT_OVERRIDE;

    static IOReturn readInventoryAction(OSObject *target, void *reference,
                                        IOExternalMethodArguments *arguments);
    static IOReturn readIndicatorAction(OSObject *target, void *reference,
                                        IOExternalMethodArguments *arguments);
    static IOReturn setIndicatorAction(OSObject *target, void *reference,
                                      IOExternalMethodArguments *arguments);

private:
    NUCLEDDriver *mDriver;
};

#endif
