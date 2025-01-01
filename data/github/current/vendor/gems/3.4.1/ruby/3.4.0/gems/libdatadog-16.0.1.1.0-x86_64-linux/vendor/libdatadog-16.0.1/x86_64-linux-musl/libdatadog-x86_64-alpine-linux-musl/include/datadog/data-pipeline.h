// Copyright 2021-Present Datadog, Inc. https://www.datadoghq.com/
// SPDX-License-Identifier: Apache-2.0


#ifndef DDOG_DATA_PIPELINE_H
#define DDOG_DATA_PIPELINE_H

#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include "common.h"

#ifdef __cplusplus
extern "C" {
#endif // __cplusplus

/**
 * Frees `error` and all its contents. After being called error will not point to a valid memory
 * address so any further actions on it could lead to undefined behavior.
 */
void ddog_trace_exporter_error_free(struct ddog_TraceExporterError *error);

void ddog_trace_exporter_config_new(struct ddog_TraceExporterConfig **out_handle);

/**
 * Frees TraceExporterConfig handle internal resources.
 */
void ddog_trace_exporter_config_free(struct ddog_TraceExporterConfig *handle);

/**
 * Sets traces destination.
 */
struct ddog_TraceExporterError *ddog_trace_exporter_config_set_url(struct ddog_TraceExporterConfig *config,
                                                                   ddog_CharSlice url);

/**
 * Sets tracer's version to be included in the headers request.
 */
struct ddog_TraceExporterError *ddog_trace_exporter_config_set_tracer_version(struct ddog_TraceExporterConfig *config,
                                                                              ddog_CharSlice version);

/**
 * Sets tracer's language to be included in the headers request.
 */
struct ddog_TraceExporterError *ddog_trace_exporter_config_set_language(struct ddog_TraceExporterConfig *config,
                                                                        ddog_CharSlice lang);

/**
 * Sets tracer's language version to be included in the headers request.
 */
struct ddog_TraceExporterError *ddog_trace_exporter_config_set_lang_version(struct ddog_TraceExporterConfig *config,
                                                                            ddog_CharSlice version);

/**
 * Sets tracer's language interpreter to be included in the headers request.
 */
struct ddog_TraceExporterError *ddog_trace_exporter_config_set_lang_interpreter(struct ddog_TraceExporterConfig *config,
                                                                                ddog_CharSlice interpreter);

/**
 * Sets hostname information to be included in the headers request.
 */
struct ddog_TraceExporterError *ddog_trace_exporter_config_set_hostname(struct ddog_TraceExporterConfig *config,
                                                                        ddog_CharSlice hostname);

/**
 * Sets environmet information to be included in the headers request.
 */
struct ddog_TraceExporterError *ddog_trace_exporter_config_set_env(struct ddog_TraceExporterConfig *config,
                                                                   ddog_CharSlice env);

struct ddog_TraceExporterError *ddog_trace_exporter_config_set_version(struct ddog_TraceExporterConfig *config,
                                                                       ddog_CharSlice version);

/**
 * Sets service name to be included in the headers request.
 */
struct ddog_TraceExporterError *ddog_trace_exporter_config_set_service(struct ddog_TraceExporterConfig *config,
                                                                       ddog_CharSlice service);

/**
 * Create a new TraceExporter instance.
 *
 * # Arguments
 *
 * * `out_handle` - The handle to write the TraceExporter instance in.
 * * `config` - The configuration used to set up the TraceExporter handle.
 */
struct ddog_TraceExporterError *ddog_trace_exporter_new(struct ddog_TraceExporter **out_handle,
                                                        const struct ddog_TraceExporterConfig *config);

/**
 * Free the TraceExporter instance.
 *
 * # Arguments
 *
 * * handle - The handle to the TraceExporter instance.
 */
void ddog_trace_exporter_free(struct ddog_TraceExporter *handle);

/**
 * Send traces to the Datadog Agent.
 *
 * # Arguments
 *
 * * `handle` - The handle to the TraceExporter instance.
 * * `trace` - The traces to send to the Datadog Agent in the input format used to create the
 *   TraceExporter. The memory for the trace must be valid for the life of the call to this
 *   function.
 * * `trace_count` - The number of traces to send to the Datadog Agent.
 * * `response` - Optional parameter that will ontain the agent response information.
 */
struct ddog_TraceExporterError *ddog_trace_exporter_send(const struct ddog_TraceExporter *handle,
                                                         ddog_ByteSlice trace,
                                                         uintptr_t trace_count,
                                                         struct ddog_AgentResponse *response);

#ifdef __cplusplus
}  // extern "C"
#endif  // __cplusplus

#endif  /* DDOG_DATA_PIPELINE_H */
