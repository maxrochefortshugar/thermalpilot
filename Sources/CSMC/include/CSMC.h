#ifndef CSMC_H
#define CSMC_H

#include <stdint.h>
#include <IOKit/IOKitLib.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    uint32_t key;
    uint32_t dataSize;
    uint32_t dataType;
    uint8_t bytes[32];
} CSMCValue;

kern_return_t CSMCOpen(io_connect_t *connection);
void CSMCClose(io_connect_t connection);
kern_return_t CSMCReadKey(io_connect_t connection, uint32_t key, CSMCValue *outValue);
kern_return_t CSMCReadKeyAtIndex(io_connect_t connection, uint32_t index, uint32_t *outKey);

#ifdef __cplusplus
}
#endif

#endif
