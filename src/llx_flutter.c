#include "llx_flutter.h"
#if defined(__has_include)
#  if __has_include(<llama/llama.h>)
#    include <llama/llama.h>
#  elif __has_include(<llama.h>)
#    include <llama.h>
#  else
#    error "Unable to find llama.cpp public header"
#  endif
#else
#  include <llama/llama.h>
#endif
#if defined(__has_include)
#  if __has_include(<llama/ggml-backend.h>)
#    include <llama/ggml-backend.h>
#  elif __has_include(<ggml-backend.h>)
#    include <ggml-backend.h>
#  else
#    error "Unable to find ggml backend public header"
#  endif
#else
#  include <ggml-backend.h>
#endif
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

// Internal structures (hidden from API users)
struct llx_model {
    struct llama_model* model;
};

struct llx_context {
    struct llama_context* context;
    struct llama_sampler* sampler;
    const struct llama_vocab* vocab;
    int32_t n_threads;
};

static void append_format(char* buffer, size_t size, size_t* offset, const char* format, ...) {
    if (!buffer || !offset || *offset >= size) return;

    va_list args;
    va_start(args, format);
    int written = vsnprintf(buffer + *offset, size - *offset, format, args);
    va_end(args);

    if (written < 0) return;

    size_t remaining = size - *offset;
    if ((size_t)written >= remaining) {
        *offset = size - 1;
    } else {
        *offset += (size_t)written;
    }
}

// UTF-8 validation helper (from Android example)
static bool is_valid_utf8(const char* string) {
    if (!string) return true;
    
    const unsigned char* bytes = (const unsigned char*)string;
    int num;
    
    while (*bytes != 0x00) {
        if ((*bytes & 0x80) == 0x00) {
            num = 1;
        } else if ((*bytes & 0xE0) == 0xC0) {
            num = 2;
        } else if ((*bytes & 0xF0) == 0xE0) {
            num = 3;
        } else if ((*bytes & 0xF8) == 0xF0) {
            num = 4;
        } else {
            return false;
        }
        
        bytes += 1;
        for (int i = 1; i < num; ++i) {
            if ((*bytes & 0xC0) != 0x80) {
                return false;
            }
            bytes += 1;
        }
    }
    
    return true;
}

// =============================================================================
// Backend Management
// =============================================================================

FFI_PLUGIN_EXPORT void llx_backend_init(void) {
    ggml_backend_load_all();
    llama_backend_init();
}

FFI_PLUGIN_EXPORT void llx_backend_free(void) {
    llama_backend_free();
}

FFI_PLUGIN_EXPORT const char* llx_system_info(void) {
    return llama_print_system_info();
}

FFI_PLUGIN_EXPORT const char* llx_backend_info(void) {
    static char buffer[2048];
    size_t offset = 0;

    buffer[0] = '\0';

    append_format(buffer, sizeof(buffer), &offset, "backends:");
    size_t backend_count = ggml_backend_reg_count();
    if (backend_count == 0) {
        append_format(buffer, sizeof(buffer), &offset, " none");
    } else {
        for (size_t i = 0; i < backend_count; i++) {
            ggml_backend_reg_t reg = ggml_backend_reg_get(i);
            append_format(
                buffer,
                sizeof(buffer),
                &offset,
                "%s%s",
                i == 0 ? " " : ", ",
                reg ? ggml_backend_reg_name(reg) : "unknown"
            );
        }
    }

    append_format(buffer, sizeof(buffer), &offset, "; devices:");
    size_t device_count = ggml_backend_dev_count();
    if (device_count == 0) {
        append_format(buffer, sizeof(buffer), &offset, " none");
    } else {
        for (size_t i = 0; i < device_count; i++) {
            ggml_backend_dev_t dev = ggml_backend_dev_get(i);
            append_format(
                buffer,
                sizeof(buffer),
                &offset,
                "%s%s",
                i == 0 ? " " : ", ",
                dev ? ggml_backend_dev_name(dev) : "unknown"
            );
        }
    }

    return buffer;
}

// =============================================================================
// Default Parameters
// =============================================================================

FFI_PLUGIN_EXPORT llx_model_params llx_default_model_params(void) {
    llx_model_params params = {0};
    params.n_gpu_layers = 0;  // CPU-only by default for compatibility
    return params;
}

FFI_PLUGIN_EXPORT llx_context_params llx_default_context_params(void) {
    llx_context_params params = {0};
    params.n_ctx = 2048;
    params.n_threads = 0;  // Auto-detect
    return params;
}

FFI_PLUGIN_EXPORT llx_generate_params llx_default_generate_params(void) {
    llx_generate_params params = {0};
    params.n_predict = 32;
    params.temperature = 0.0f;
    return params;
}

// =============================================================================
// Model Management
// =============================================================================

FFI_PLUGIN_EXPORT llx_error llx_load_model(
    const char* model_path,
    const llx_model_params* params,
    llx_model** out_model
) {
    if (!model_path || !params || !out_model) {
        return LLX_ERROR_INVALID_PARAMS;
    }
    
    *out_model = NULL;
    
    // Allocate wrapper
    llx_model* wrapper = malloc(sizeof(llx_model));
    if (!wrapper) {
        return LLX_ERROR_MODEL_LOAD_FAILED;
    }
    
    // Set up llama model parameters
    struct llama_model_params model_params = llama_model_default_params();
    model_params.n_gpu_layers = params->n_gpu_layers;
    
    // Load the model
    wrapper->model = llama_model_load_from_file(model_path, model_params);
    if (!wrapper->model) {
        free(wrapper);
        return LLX_ERROR_MODEL_LOAD_FAILED;
    }
    
    *out_model = wrapper;
    return LLX_SUCCESS;
}

FFI_PLUGIN_EXPORT void llx_free_model(llx_model* model) {
    if (!model) return;
    
    if (model->model) {
        llama_model_free(model->model);
    }
    free(model);
}

// =============================================================================
// Context Management  
// =============================================================================

FFI_PLUGIN_EXPORT llx_error llx_create_context(
    llx_model* model,
    const llx_context_params* params,
    llx_context** out_context
) {
    if (!model || !model->model || !params || !out_context) {
        return LLX_ERROR_INVALID_PARAMS;
    }
    
    *out_context = NULL;
    
    // Allocate wrapper
    llx_context* wrapper = malloc(sizeof(llx_context));
    if (!wrapper) {
        return LLX_ERROR_CONTEXT_CREATION_FAILED;
    }
    memset(wrapper, 0, sizeof(llx_context));
    
    // Set up context parameters
    struct llama_context_params ctx_params = llama_context_default_params();
    ctx_params.n_ctx = params->n_ctx;
    ctx_params.n_batch = 512;  // Good default from your main.cpp
    ctx_params.no_perf = false;
    
    // Handle threading
    if (params->n_threads <= 0) {
        // Auto-detect: use available cores minus 2, minimum 1
        int n_cores = (int)sysconf(_SC_NPROCESSORS_ONLN);
        ctx_params.n_threads = n_cores > 2 ? n_cores - 2 : 1;
        ctx_params.n_threads_batch = ctx_params.n_threads;
    } else {
        ctx_params.n_threads = params->n_threads;
        ctx_params.n_threads_batch = params->n_threads;
    }
    wrapper->n_threads = ctx_params.n_threads;
    
    // Create context
    wrapper->context = llama_init_from_model(model->model, ctx_params);
    if (!wrapper->context) {
        free(wrapper);
        return LLX_ERROR_CONTEXT_CREATION_FAILED;
    }
    
    // Create sampler (from your main.cpp approach)
    struct llama_sampler_chain_params sparams = llama_sampler_chain_default_params();
    sparams.no_perf = false;
    wrapper->sampler = llama_sampler_chain_init(sparams);
    if (!wrapper->sampler) {
        llama_free(wrapper->context);
        free(wrapper);
        return LLX_ERROR_CONTEXT_CREATION_FAILED;
    }
    
    // Get vocab reference
    wrapper->vocab = llama_model_get_vocab(model->model);
    
    *out_context = wrapper;
    return LLX_SUCCESS;
}

FFI_PLUGIN_EXPORT void llx_free_context(llx_context* context) {
    if (!context) return;
    
    if (context->sampler) {
        llama_sampler_free(context->sampler);
    }
    if (context->context) {
        llama_free(context->context);
    }
    free(context);
}

FFI_PLUGIN_EXPORT int32_t llx_context_n_threads(const llx_context* context) {
    return context ? context->n_threads : 0;
}

// =============================================================================
// Text Generation
// =============================================================================

FFI_PLUGIN_EXPORT llx_error llx_generate_stream(
    llx_context* context,
    const char* prompt,
    const llx_generate_params* params,
    llx_token_callback token_cb,
    void* user_data
) {
    if (!context || !context->context || !prompt || !params || !token_cb) {
        return LLX_ERROR_INVALID_PARAMS;
    }
    
    // Clear any existing sampler configuration and set up new one
    llama_sampler_free(context->sampler);
    struct llama_sampler_chain_params sparams = llama_sampler_chain_default_params();
    sparams.no_perf = false;
    context->sampler = llama_sampler_chain_init(sparams);
    
    if (params->temperature <= 0.0f) {
        // Greedy sampling
        llama_sampler_chain_add(context->sampler, llama_sampler_init_greedy());
    } else {
        // Temperature sampling
        llama_sampler_chain_add(context->sampler, llama_sampler_init_temp(params->temperature));
        llama_sampler_chain_add(context->sampler, llama_sampler_init_dist(LLAMA_DEFAULT_SEED));
    }

    // Tokenize the prompt
    const int n_prompt = -llama_tokenize(context->vocab, prompt, (int32_t)strlen(prompt), NULL, 0, true, true);
    if (n_prompt <= 0) {
        return LLX_ERROR_GENERATION_FAILED;
    }
    
    // Allocate tokens array
    llama_token* prompt_tokens = malloc(n_prompt * sizeof(llama_token));
    if (!prompt_tokens) {
        return LLX_ERROR_GENERATION_FAILED;
    }
    
    // Actually tokenize
    if (llama_tokenize(context->vocab, prompt, (int32_t)strlen(prompt), prompt_tokens, n_prompt, true, true) < 0) {
        free(prompt_tokens);
        return LLX_ERROR_GENERATION_FAILED;
    }
    
    // Process prompt in batch (from your main.cpp)
    llama_batch batch = llama_batch_get_one(prompt_tokens, n_prompt);
    if (llama_decode(context->context, batch) != 0) {
        free(prompt_tokens);
        return LLX_ERROR_GENERATION_FAILED;
    }
    
    free(prompt_tokens);
    
    // Generation loop (adapted from your main.cpp)
    int n_decode = 0;
    llama_token new_token_id;
    char cached_chars[256] = {0};  // For UTF-8 accumulation
    int cached_len = 0;
    
    for (int n_pos = n_prompt; n_pos < n_prompt + params->n_predict; n_pos++) {
        // Sample next token
        new_token_id = llama_sampler_sample(context->sampler, context->context, -1);
        
        // Check for end of generation
        if (llama_vocab_is_eog(context->vocab, new_token_id)) {
            break;
        }
        
        // Convert token to piece
        char buf[128];
        int n = llama_token_to_piece(context->vocab, new_token_id, buf, sizeof(buf), 0, true);
        if (n < 0) {
            return LLX_ERROR_GENERATION_FAILED;
        }
        
        // Accumulate characters for UTF-8 validation (from Android example)
        if (cached_len + n < sizeof(cached_chars) - 1) {
            memcpy(cached_chars + cached_len, buf, n);
            cached_len += n;
            cached_chars[cached_len] = '\0';
        }
        
        // Check if we have valid UTF-8
        if (is_valid_utf8(cached_chars)) {
            // Call user callback with valid UTF-8 string
            if (!token_cb(cached_chars, user_data)) {
                break;  // User requested stop
            }
            // Reset cache
            cached_len = 0;
            cached_chars[0] = '\0';
        }
        
        // Prepare next batch with sampled token
        batch = llama_batch_get_one(&new_token_id, 1);
        if (llama_decode(context->context, batch) != 0) {
            return LLX_ERROR_GENERATION_FAILED;
        }
        
        n_decode++;
    }
    
    // Send any remaining cached characters
    if (cached_len > 0) {
        token_cb(cached_chars, user_data);
    }
    
    return LLX_SUCCESS;
}

// =============================================================================
// Utility Functions
// =============================================================================

FFI_PLUGIN_EXPORT const char* llx_error_string(llx_error error) {
    switch (error) {
        case LLX_SUCCESS:
            return "Success";
        case LLX_ERROR_MODEL_LOAD_FAILED:
            return "Failed to load model";
        case LLX_ERROR_CONTEXT_CREATION_FAILED:
            return "Failed to create context";
        case LLX_ERROR_GENERATION_FAILED:
            return "Text generation failed";
        case LLX_ERROR_INVALID_PARAMS:
            return "Invalid parameters";
        default:
            return "Unknown error";
    }
}
