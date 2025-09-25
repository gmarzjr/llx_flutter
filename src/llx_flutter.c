#include "llx_flutter.h"
#include <llama/llama.h>

FFI_PLUGIN_EXPORT const char* llx_get_system_info(void) {
    return llama_print_system_info();
}
