#include "CSMC.h"

#include <mach/mach.h>
#include <string.h>

enum {
    KERNEL_INDEX_SMC = 2,
    SMC_CMD_READ_BYTES = 5,
    SMC_CMD_READ_INDEX = 8,
    SMC_CMD_READ_KEYINFO = 9
};

typedef struct {
    uint8_t major;
    uint8_t minor;
    uint8_t build;
    uint8_t reserved;
    uint16_t release;
} SMCKeyDataVersion;

typedef struct {
    uint16_t version;
    uint16_t length;
    uint32_t cpuPLimit;
    uint32_t gpuPLimit;
    uint32_t memPLimit;
} SMCKeyDataPLimitData;

typedef struct {
    uint32_t dataSize;
    uint32_t dataType;
    uint8_t dataAttributes;
} SMCKeyDataKeyInfo;

typedef struct {
    uint32_t key;
    SMCKeyDataVersion version;
    SMCKeyDataPLimitData pLimitData;
    SMCKeyDataKeyInfo keyInfo;
    uint8_t result;
    uint8_t status;
    uint8_t data8;
    uint32_t data32;
    uint8_t bytes[32];
} SMCKeyData;

static kern_return_t csmc_call(io_connect_t connection, SMCKeyData *input, SMCKeyData *output) {
    size_t outputSize = sizeof(SMCKeyData);
    return IOConnectCallStructMethod(
        connection,
        KERNEL_INDEX_SMC,
        input,
        sizeof(SMCKeyData),
        output,
        &outputSize
    );
}

kern_return_t CSMCOpen(io_connect_t *connection) {
    if (connection == NULL) {
        return kIOReturnBadArgument;
    }

    const char *serviceNames[] = {
        "AppleSMC",
        "AppleSMCKeysEndpoint"
    };

    kern_return_t lastResult = kIOReturnNotFound;

    for (size_t index = 0; index < sizeof(serviceNames) / sizeof(serviceNames[0]); index++) {
        CFMutableDictionaryRef matching = IOServiceMatching(serviceNames[index]);
        if (matching == NULL) {
            continue;
        }

        io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, matching);
        if (service == IO_OBJECT_NULL) {
            continue;
        }

        lastResult = IOServiceOpen(service, mach_task_self(), 0, connection);
        IOObjectRelease(service);

        if (lastResult == KERN_SUCCESS) {
            return KERN_SUCCESS;
        }
    }

    return lastResult;
}

void CSMCClose(io_connect_t connection) {
    if (connection != IO_OBJECT_NULL) {
        IOServiceClose(connection);
    }
}

kern_return_t CSMCReadKey(io_connect_t connection, uint32_t key, CSMCValue *outValue) {
    if (outValue == NULL) {
        return kIOReturnBadArgument;
    }

    SMCKeyData input;
    SMCKeyData output;
    memset(&input, 0, sizeof(input));
    memset(&output, 0, sizeof(output));

    input.key = key;
    input.data8 = SMC_CMD_READ_KEYINFO;

    kern_return_t result = csmc_call(connection, &input, &output);
    if (result != KERN_SUCCESS) {
        return result;
    }
    if (output.result != 0) {
        return kIOReturnError;
    }

    SMCKeyDataKeyInfo keyInfo = output.keyInfo;

    memset(&input, 0, sizeof(input));
    memset(&output, 0, sizeof(output));

    input.key = key;
    input.keyInfo.dataSize = keyInfo.dataSize;
    input.data8 = SMC_CMD_READ_BYTES;

    result = csmc_call(connection, &input, &output);
    if (result != KERN_SUCCESS) {
        return result;
    }
    if (output.result != 0) {
        return kIOReturnError;
    }

    memset(outValue, 0, sizeof(*outValue));
    outValue->key = key;
    outValue->dataSize = keyInfo.dataSize > 32 ? 32 : keyInfo.dataSize;
    outValue->dataType = keyInfo.dataType;
    memcpy(outValue->bytes, output.bytes, outValue->dataSize);

    return KERN_SUCCESS;
}

kern_return_t CSMCReadKeyAtIndex(io_connect_t connection, uint32_t index, uint32_t *outKey) {
    if (outKey == NULL) {
        return kIOReturnBadArgument;
    }

    SMCKeyData input;
    SMCKeyData output;
    memset(&input, 0, sizeof(input));
    memset(&output, 0, sizeof(output));

    input.data8 = SMC_CMD_READ_INDEX;
    input.data32 = index;

    kern_return_t result = csmc_call(connection, &input, &output);
    if (result != KERN_SUCCESS) {
        return result;
    }
    if (output.result != 0) {
        return kIOReturnError;
    }

    *outKey = output.key;
    return KERN_SUCCESS;
}
