#ifndef LLX_FLUTTER_H
#define LLX_FLUTTER_H

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#if _WIN32
#include <windows.h>
#else
#include <pthread.h>
#include <unistd.h>
#endif

#if _WIN32
#define FFI_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FFI_PLUGIN_EXPORT 
#endif

#ifdef __cplusplus
extern "C" {
#endif

// Forward declarations - opaque pointers for FFI
typedef struct llx_model llx_model;
typedef struct llx_context llx_context;

// Error codes
typedef int32_t llx_error;
#define LLX_SUCCESS 0
#define LLX_ERROR_MODEL_LOAD_FAILED -1
#define LLX_ERROR_CONTEXT_CREATION_FAILED -2
#define LLX_ERROR_GENERATION_FAILED -3
#define LLX_ERROR_INVALID_PARAMS -4

// Model loading parameters
typedef struct {
    int32_t n_gpu_layers;     // Number of layers to offload to GPU (0 for CPU-only)
} llx_model_params;

// Context parameters  
typedef struct {
    int32_t n_ctx;            // Context size (default: 2048)
    int32_t n_threads;        // Number of threads (0 = auto-detect)
} llx_context_params;

// Generation parameters
typedef struct {
    int32_t n_predict;        // Maximum tokens to generate
    float temperature;        // Sampling temperature (0.0 = greedy)
} llx_generate_params;

// Generation timing/statistics from the most recent generation call
typedef struct {
    int32_t prompt_tokens;       // Number of prompt tokens processed
    int32_t generated_tokens;    // Number of output tokens generated
    double prompt_seconds;       // Prompt processing time
    double decode_seconds;       // Output token generation time
    double tokens_per_second;    // generated_tokens / decode_seconds
} llx_generation_stats;

// Token callback function type for streaming
// Returns false to stop generation
typedef bool (*llx_token_callback)(const char* token_piece, void* user_data);

// =============================================================================
// Core API Functions
// =============================================================================

// Initialize/shutdown the backend
FFI_PLUGIN_EXPORT void llx_backend_init(void);
FFI_PLUGIN_EXPORT void llx_backend_free(void);

// Runtime diagnostics
FFI_PLUGIN_EXPORT const char* llx_system_info(void);
FFI_PLUGIN_EXPORT const char* llx_backend_info(void);

// Get default parameters
FFI_PLUGIN_EXPORT llx_model_params llx_default_model_params(void);
FFI_PLUGIN_EXPORT llx_context_params llx_default_context_params(void);
FFI_PLUGIN_EXPORT llx_generate_params llx_default_generate_params(void);

// Model management
FFI_PLUGIN_EXPORT llx_error llx_load_model(
    const char* model_path,
    const llx_model_params* params,
    llx_model** out_model
);

FFI_PLUGIN_EXPORT void llx_free_model(llx_model* model);

// Context management
FFI_PLUGIN_EXPORT llx_error llx_create_context(
    llx_model* model,
    const llx_context_params* params,
    llx_context** out_context
);

FFI_PLUGIN_EXPORT void llx_free_context(llx_context* context);

FFI_PLUGIN_EXPORT int32_t llx_context_n_threads(const llx_context* context);
FFI_PLUGIN_EXPORT llx_generation_stats llx_context_generation_stats(const llx_context* context);

// Text Generation - Streaming with callback
FFI_PLUGIN_EXPORT llx_error llx_generate_stream(
    llx_context* context,
    const char* prompt,
    const llx_generate_params* params,
    llx_token_callback token_cb,
    void* user_data
);

// Utility Functions
FFI_PLUGIN_EXPORT const char* llx_error_string(llx_error error);

#ifdef __cplusplus
}
#endif

#endif // LLX_FLUTTER_H
