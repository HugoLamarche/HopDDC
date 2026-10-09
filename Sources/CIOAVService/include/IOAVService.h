// Private IOKit API used to talk I2C (and so DDC/CI) to external displays on
// Apple Silicon. Not in any public header, but exported by IOKit.framework.
#pragma once

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>

typedef CFTypeRef IOAVServiceRef;

IOAVServiceRef IOAVServiceCreateWithService(CFAllocatorRef allocator, io_service_t service) CF_RETURNS_RETAINED;
IOReturn IOAVServiceReadI2C(IOAVServiceRef service, uint32_t chip, uint32_t offset, void *buf, uint32_t len);
IOReturn IOAVServiceWriteI2C(IOAVServiceRef service, uint32_t chip, uint32_t offset, void *buf, uint32_t len);
