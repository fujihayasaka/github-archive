// Copyright 2021-Present Datadog, Inc. https://www.datadoghq.com/
// SPDX-License-Identifier: Apache-2.0


#ifndef DDOG_COMMON_H
#define DDOG_COMMON_H

#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define DDOG_CHARSLICE_C(string) \
/* NOTE: Compilation fails if you pass in a char* instead of a literal */ ((ddog_CharSlice){ .ptr = "" string, .len = sizeof(string) - 1 })

#define DDOG_CHARSLICE_C_BARE(string) \
/* NOTE: Compilation fails if you pass in a char* instead of a literal */ { .ptr = "" string, .len = sizeof(string) - 1 }

#if defined __GNUC__
#  define DDOG_GNUC_VERSION(major) __GNUC__ >= major
#else
#  define DDOG_GNUC_VERSION(major) (0)
#endif

#if defined __has_attribute
#  define DDOG_HAS_ATTRIBUTE(attribute, major) __has_attribute(attribute)
#else
#  define DDOG_HAS_ATTRIBUTE(attribute, major) DDOG_GNUC_VERSION(major)
#endif

#if defined(__cplusplus) && (__cplusplus >= 201703L)
#  define DDOG_CHECK_RETURN [[nodiscard]]
#elif defined(_Check_return_) /* SAL */
#  define DDOG_CHECK_RETURN _Check_return_
#elif DDOG_HAS_ATTRIBUTE(warn_unused_result, 4)
#  define DDOG_CHECK_RETURN __attribute__((__warn_unused_result__))
#else
#  define DDOG_CHECK_RETURN
#endif

/**
 * Default value for the timeout field in milliseconds.
 */
#define ddog_Endpoint_DEFAULT_TIMEOUT 3000

typedef struct ddog_Endpoint ddog_Endpoint;

typedef struct ddog_Tag ddog_Tag;

/**
 * Holds the raw parts of a Rust Vec; it should only be created from Rust,
 * never from C.
 */
typedef struct ddog_Vec_U8 {
  const uint8_t *ptr;
  uintptr_t len;
  uintptr_t capacity;
} ddog_Vec_U8;

/**
 * Please treat this as opaque; do not reach into it, and especially don't
 * write into it! The most relevant APIs are:
 * * `ddog_Error_message`, to get the message as a slice.
 * * `ddog_Error_drop`.
 */
typedef struct ddog_Error {
  /**
   * This is a String stuffed into the vec.
   */
  struct ddog_Vec_U8 message;
} ddog_Error;

typedef struct ddog_Slice_CChar {
  /**
   * Should be non-null and suitably aligned for the underlying type. It is
   * allowed but not recommended for the pointer to be null when the len is
   * zero.
   */
  const char *ptr;
  /**
   * The number of elements (not bytes) that `.ptr` points to. Must be less
   * than or equal to [isize::MAX].
   */
  uintptr_t len;
} ddog_Slice_CChar;

/**
 * Use to represent strings -- should be valid UTF-8.
 */
typedef struct ddog_Slice_CChar ddog_CharSlice;

typedef enum ddog_Option_Error_Tag {
  DDOG_OPTION_ERROR_SOME_ERROR,
  DDOG_OPTION_ERROR_NONE_ERROR,
} ddog_Option_Error_Tag;

typedef struct ddog_Option_Error {
  ddog_Option_Error_Tag tag;
  union {
    struct {
      struct ddog_Error some;
    };
  };
} ddog_Option_Error;

typedef struct ddog_Option_Error ddog_MaybeError;

typedef struct ddog_ArrayQueue {
  struct ddog_ArrayQueue *inner;
  void (*item_delete_fn)(void*);
} ddog_ArrayQueue;

typedef enum ddog_ArrayQueue_NewResult_Tag {
  DDOG_ARRAY_QUEUE_NEW_RESULT_OK,
  DDOG_ARRAY_QUEUE_NEW_RESULT_ERR,
} ddog_ArrayQueue_NewResult_Tag;

typedef struct ddog_ArrayQueue_NewResult {
  ddog_ArrayQueue_NewResult_Tag tag;
  union {
    struct {
      struct ddog_ArrayQueue *ok;
    };
    struct {
      struct ddog_Error err;
    };
  };
} ddog_ArrayQueue_NewResult;

/**
 * Data structure for the result of the push() and force_push() functions.
 * force_push() replaces the oldest element if the queue is full, while push() returns the given
 * value if the queue is full. For push(), it's redundant to return the value since the caller
 * already has it, but it's returned for consistency with crossbeam API and with force_push().
 */
typedef enum ddog_ArrayQueue_PushResult_Tag {
  DDOG_ARRAY_QUEUE_PUSH_RESULT_OK,
  DDOG_ARRAY_QUEUE_PUSH_RESULT_FULL,
  DDOG_ARRAY_QUEUE_PUSH_RESULT_ERR,
} ddog_ArrayQueue_PushResult_Tag;

typedef struct ddog_ArrayQueue_PushResult {
  ddog_ArrayQueue_PushResult_Tag tag;
  union {
    struct {
      void *full;
    };
    struct {
      struct ddog_Error err;
    };
  };
} ddog_ArrayQueue_PushResult;

typedef enum ddog_ArrayQueue_PopResult_Tag {
  DDOG_ARRAY_QUEUE_POP_RESULT_OK,
  DDOG_ARRAY_QUEUE_POP_RESULT_EMPTY,
  DDOG_ARRAY_QUEUE_POP_RESULT_ERR,
} ddog_ArrayQueue_PopResult_Tag;

typedef struct ddog_ArrayQueue_PopResult {
  ddog_ArrayQueue_PopResult_Tag tag;
  union {
    struct {
      void *ok;
    };
    struct {
      struct ddog_Error err;
    };
  };
} ddog_ArrayQueue_PopResult;

typedef enum ddog_ArrayQueue_BoolResult_Tag {
  DDOG_ARRAY_QUEUE_BOOL_RESULT_OK,
  DDOG_ARRAY_QUEUE_BOOL_RESULT_ERR,
} ddog_ArrayQueue_BoolResult_Tag;

typedef struct ddog_ArrayQueue_BoolResult {
  ddog_ArrayQueue_BoolResult_Tag tag;
  union {
    struct {
      bool ok;
    };
    struct {
      struct ddog_Error err;
    };
  };
} ddog_ArrayQueue_BoolResult;

typedef enum ddog_ArrayQueue_UsizeResult_Tag {
  DDOG_ARRAY_QUEUE_USIZE_RESULT_OK,
  DDOG_ARRAY_QUEUE_USIZE_RESULT_ERR,
} ddog_ArrayQueue_UsizeResult_Tag;

typedef struct ddog_ArrayQueue_UsizeResult {
  ddog_ArrayQueue_UsizeResult_Tag tag;
  union {
    struct {
      uintptr_t ok;
    };
    struct {
      struct ddog_Error err;
    };
  };
} ddog_ArrayQueue_UsizeResult;

typedef enum ddog_Option_U32_Tag {
  DDOG_OPTION_U32_SOME_U32,
  DDOG_OPTION_U32_NONE_U32,
} ddog_Option_U32_Tag;

typedef struct ddog_Option_U32 {
  ddog_Option_U32_Tag tag;
  union {
    struct {
      uint32_t some;
    };
  };
} ddog_Option_U32;

/**
 * A wrapper for returning owned strings from FFI
 */
typedef struct ddog_StringWrapper {
  /**
   * This is a String stuffed into the vec.
   */
  struct ddog_Vec_U8 message;
} ddog_StringWrapper;

/**
 * Holds the raw parts of a Rust Vec; it should only be created from Rust,
 * never from C.
 */
typedef struct ddog_Vec_Tag {
  const struct ddog_Tag *ptr;
  uintptr_t len;
  uintptr_t capacity;
} ddog_Vec_Tag;

typedef enum ddog_Vec_Tag_PushResult_Tag {
  DDOG_VEC_TAG_PUSH_RESULT_OK,
  DDOG_VEC_TAG_PUSH_RESULT_ERR,
} ddog_Vec_Tag_PushResult_Tag;

typedef struct ddog_Vec_Tag_PushResult {
  ddog_Vec_Tag_PushResult_Tag tag;
  union {
    struct {
      struct ddog_Error err;
    };
  };
} ddog_Vec_Tag_PushResult;

typedef struct ddog_Vec_Tag_ParseResult {
  struct ddog_Vec_Tag tags;
  struct ddog_Error *error_message;
} ddog_Vec_Tag_ParseResult;

typedef struct ddog_CancellationToken ddog_CancellationToken;

typedef struct ddog_prof_Exporter ddog_prof_Exporter;

typedef struct ddog_prof_ProfiledEndpointsStats ddog_prof_ProfiledEndpointsStats;

typedef struct ddog_prof_Exporter_Request ddog_prof_Exporter_Request;

typedef struct ddog_Slice_U8 {
  /**
   * Should be non-null and suitably aligned for the underlying type. It is
   * allowed but not recommended for the pointer to be null when the len is
   * zero.
   */
  const uint8_t *ptr;
  /**
   * The number of elements (not bytes) that `.ptr` points to. Must be less
   * than or equal to [isize::MAX].
   */
  uintptr_t len;
} ddog_Slice_U8;

/**
 * Use to represent bytes -- does not need to be valid UTF-8.
 */
typedef struct ddog_Slice_U8 ddog_ByteSlice;

typedef struct ddog_prof_Exporter_File {
  ddog_CharSlice name;
  ddog_ByteSlice file;
} ddog_prof_Exporter_File;

typedef struct ddog_prof_Exporter_Slice_File {
  /**
   * Should be non-null and suitably aligned for the underlying type. It is
   * allowed but not recommended for the pointer to be null when the len is
   * zero.
   */
  const struct ddog_prof_Exporter_File *ptr;
  /**
   * The number of elements (not bytes) that `.ptr` points to. Must be less
   * than or equal to [isize::MAX].
   */
  uintptr_t len;
} ddog_prof_Exporter_Slice_File;

typedef enum ddog_prof_Endpoint_Tag {
  DDOG_PROF_ENDPOINT_AGENT,
  DDOG_PROF_ENDPOINT_AGENTLESS,
  DDOG_PROF_ENDPOINT_FILE,
} ddog_prof_Endpoint_Tag;

typedef struct ddog_prof_Endpoint_ddog_prof_Agentless_Body {
  ddog_CharSlice _0;
  ddog_CharSlice _1;
} ddog_prof_Endpoint_ddog_prof_Agentless_Body;

typedef struct ddog_prof_Endpoint {
  ddog_prof_Endpoint_Tag tag;
  union {
    struct {
      ddog_CharSlice agent;
    };
    ddog_prof_Endpoint_ddog_prof_Agentless_Body AGENTLESS;
    struct {
      ddog_CharSlice file;
    };
  };
} ddog_prof_Endpoint;

typedef enum ddog_prof_Exporter_NewResult_Tag {
  DDOG_PROF_EXPORTER_NEW_RESULT_OK,
  DDOG_PROF_EXPORTER_NEW_RESULT_ERR,
} ddog_prof_Exporter_NewResult_Tag;

typedef struct ddog_prof_Exporter_NewResult {
  ddog_prof_Exporter_NewResult_Tag tag;
  union {
    struct {
      struct ddog_prof_Exporter *ok;
    };
    struct {
      struct ddog_Error err;
    };
  };
} ddog_prof_Exporter_NewResult;

typedef enum ddog_prof_Option_Error_Tag {
  DDOG_PROF_OPTION_ERROR_SOME_ERROR,
  DDOG_PROF_OPTION_ERROR_NONE_ERROR,
} ddog_prof_Option_Error_Tag;

typedef struct ddog_prof_Option_Error {
  ddog_prof_Option_Error_Tag tag;
  union {
    struct {
      struct ddog_Error some;
    };
  };
} ddog_prof_Option_Error;

typedef struct ddog_prof_Option_Error ddog_prof_MaybeError;

typedef enum ddog_prof_Exporter_Request_BuildResult_Tag {
  DDOG_PROF_EXPORTER_REQUEST_BUILD_RESULT_OK,
  DDOG_PROF_EXPORTER_REQUEST_BUILD_RESULT_ERR,
} ddog_prof_Exporter_Request_BuildResult_Tag;

typedef struct ddog_prof_Exporter_Request_BuildResult {
  ddog_prof_Exporter_Request_BuildResult_Tag tag;
  union {
    struct {
      struct ddog_prof_Exporter_Request *ok;
    };
    struct {
      struct ddog_Error err;
    };
  };
} ddog_prof_Exporter_Request_BuildResult;

/**
 * Represents time since the Unix Epoch in seconds plus nanoseconds.
 */
typedef struct ddog_Timespec {
  int64_t seconds;
  uint32_t nanoseconds;
} ddog_Timespec;

typedef struct ddog_HttpStatus {
  uint16_t code;
} ddog_HttpStatus;

typedef enum ddog_prof_Exporter_SendResult_Tag {
  DDOG_PROF_EXPORTER_SEND_RESULT_HTTP_RESPONSE,
  DDOG_PROF_EXPORTER_SEND_RESULT_ERR,
} ddog_prof_Exporter_SendResult_Tag;

typedef struct ddog_prof_Exporter_SendResult {
  ddog_prof_Exporter_SendResult_Tag tag;
  union {
    struct {
      struct ddog_HttpStatus http_response;
    };
    struct {
      struct ddog_Error err;
    };
  };
} ddog_prof_Exporter_SendResult;

/**
 * Represents a profile. Do not access its member for any reason, only use
 * the C API functions on this struct.
 */
typedef struct ddog_prof_Profile {
  struct ddog_prof_Profile *inner;
} ddog_prof_Profile;

/**
 * Returned by [ddog_prof_Profile_new].
 */
typedef enum ddog_prof_Profile_NewResult_Tag {
  DDOG_PROF_PROFILE_NEW_RESULT_OK,
  DDOG_PROF_PROFILE_NEW_RESULT_ERR,
} ddog_prof_Profile_NewResult_Tag;

typedef struct ddog_prof_Profile_NewResult {
  ddog_prof_Profile_NewResult_Tag tag;
  union {
    struct {
      struct ddog_prof_Profile ok;
    };
    struct {
      struct ddog_Error err;
    };
  };
} ddog_prof_Profile_NewResult;

typedef struct ddog_prof_ValueType {
  ddog_CharSlice type_;
  ddog_CharSlice unit;
} ddog_prof_ValueType;

typedef struct ddog_prof_Slice_ValueType {
  /**
   * Should be non-null and suitably aligned for the underlying type. It is
   * allowed but not recommended for the pointer to be null when the len is
   * zero.
   */
  const struct ddog_prof_ValueType *ptr;
  /**
   * The number of elements (not bytes) that `.ptr` points to. Must be less
   * than or equal to [isize::MAX].
   */
  uintptr_t len;
} ddog_prof_Slice_ValueType;

typedef struct ddog_prof_Period {
  struct ddog_prof_ValueType type_;
  int64_t value;
} ddog_prof_Period;

typedef struct ddog_prof_ManagedStringStorage {
  const void *inner;
} ddog_prof_ManagedStringStorage;

/**
 * A generic result type for when a profiling operation may fail, but there's
 * nothing to return in the case of success.
 */
typedef enum ddog_prof_Profile_Result_Tag {
  DDOG_PROF_PROFILE_RESULT_OK,
  DDOG_PROF_PROFILE_RESULT_ERR,
} ddog_prof_Profile_Result_Tag;

typedef struct ddog_prof_Profile_Result {
  ddog_prof_Profile_Result_Tag tag;
  union {
    struct {
      /**
       * Do not use the value of Ok. This value only exists to overcome
       * Rust -> C code generation.
       */
      bool ok;
    };
    struct {
      struct ddog_Error err;
    };
  };
} ddog_prof_Profile_Result;

typedef struct ddog_prof_ManagedStringId {
  uint32_t value;
} ddog_prof_ManagedStringId;

typedef struct ddog_prof_Mapping {
  /**
   * Address at which the binary (or DLL) is loaded into memory.
   */
  uint64_t memory_start;
  /**
   * The limit of the address range occupied by this mapping.
   */
  uint64_t memory_limit;
  /**
   * Offset in the binary that corresponds to the first mapped address.
   */
  uint64_t file_offset;
  /**
   * The object this entry is loaded from.  This can be a filename on
   * disk for the main binary and shared libraries, or virtual
   * abstractions like "[vdso]".
   */
  ddog_CharSlice filename;
  struct ddog_prof_ManagedStringId filename_id;
  /**
   * A string that uniquely identifies a particular program version
   * with high probability. E.g., for binaries generated by GNU tools,
   * it could be the contents of the .note.gnu.build-id field.
   */
  ddog_CharSlice build_id;
  struct ddog_prof_ManagedStringId build_id_id;
} ddog_prof_Mapping;

typedef struct ddog_prof_Function {
  /**
   * Name of the function, in human-readable form if available.
   */
  ddog_CharSlice name;
  struct ddog_prof_ManagedStringId name_id;
  /**
   * Name of the function, as identified by the system.
   * For instance, it can be a C++ mangled name.
   */
  ddog_CharSlice system_name;
  struct ddog_prof_ManagedStringId system_name_id;
  /**
   * Source file containing the function.
   */
  ddog_CharSlice filename;
  struct ddog_prof_ManagedStringId filename_id;
  /**
   * Line number in source file.
   */
  int64_t start_line;
} ddog_prof_Function;

typedef struct ddog_prof_Location {
  /**
   * todo: how to handle unknown mapping?
   */
  struct ddog_prof_Mapping mapping;
  struct ddog_prof_Function function;
  /**
   * The instruction address for this location, if available.  It
   * should be within [Mapping.memory_start...Mapping.memory_limit]
   * for the corresponding mapping. A non-leaf address may be in the
   * middle of a call instruction. It is up to display tools to find
   * the beginning of the instruction if necessary.
   */
  uint64_t address;
  int64_t line;
} ddog_prof_Location;

typedef struct ddog_prof_Slice_Location {
  /**
   * Should be non-null and suitably aligned for the underlying type. It is
   * allowed but not recommended for the pointer to be null when the len is
   * zero.
   */
  const struct ddog_prof_Location *ptr;
  /**
   * The number of elements (not bytes) that `.ptr` points to. Must be less
   * than or equal to [isize::MAX].
   */
  uintptr_t len;
} ddog_prof_Slice_Location;

typedef struct ddog_Slice_I64 {
  /**
   * Should be non-null and suitably aligned for the underlying type. It is
   * allowed but not recommended for the pointer to be null when the len is
   * zero.
   */
  const int64_t *ptr;
  /**
   * The number of elements (not bytes) that `.ptr` points to. Must be less
   * than or equal to [isize::MAX].
   */
  uintptr_t len;
} ddog_Slice_I64;

typedef struct ddog_prof_Label {
  ddog_CharSlice key;
  struct ddog_prof_ManagedStringId key_id;
  /**
   * At most one of the following must be present
   */
  ddog_CharSlice str;
  struct ddog_prof_ManagedStringId str_id;
  int64_t num;
  /**
   * Should only be present when num is present.
   * Specifies the units of num.
   * Use arbitrary string (for example, "requests") as a custom count unit.
   * If no unit is specified, consumer may apply heuristic to deduce the unit.
   * Consumers may also  interpret units like "bytes" and "kilobytes" as memory
   * units and units like "seconds" and "nanoseconds" as time units,
   * and apply appropriate unit conversions to these.
   */
  ddog_CharSlice num_unit;
  struct ddog_prof_ManagedStringId num_unit_id;
} ddog_prof_Label;

typedef struct ddog_prof_Slice_Label {
  /**
   * Should be non-null and suitably aligned for the underlying type. It is
   * allowed but not recommended for the pointer to be null when the len is
   * zero.
   */
  const struct ddog_prof_Label *ptr;
  /**
   * The number of elements (not bytes) that `.ptr` points to. Must be less
   * than or equal to [isize::MAX].
   */
  uintptr_t len;
} ddog_prof_Slice_Label;

typedef struct ddog_prof_Sample {
  /**
   * The leaf is at locations[0].
   */
  struct ddog_prof_Slice_Location locations;
  /**
   * The type and unit of each value is defined by the corresponding
   * entry in Profile.sample_type. All samples must have the same
   * number of values, the same as the length of Profile.sample_type.
   * When aggregating multiple samples into a single sample, the
   * result has a list of values that is the element-wise sum of the
   * lists of the originals.
   */
  struct ddog_Slice_I64 values;
  /**
   * label includes additional context for this sample. It can include
   * things like a thread id, allocation size, etc
   */
  struct ddog_prof_Slice_Label labels;
} ddog_prof_Sample;

typedef struct ddog_prof_Slice_Usize {
  /**
   * Should be non-null and suitably aligned for the underlying type. It is
   * allowed but not recommended for the pointer to be null when the len is
   * zero.
   */
  const uintptr_t *ptr;
  /**
   * The number of elements (not bytes) that `.ptr` points to. Must be less
   * than or equal to [isize::MAX].
   */
  uintptr_t len;
} ddog_prof_Slice_Usize;

typedef struct ddog_prof_EncodedProfile {
  struct ddog_Timespec start;
  struct ddog_Timespec end;
  struct ddog_Vec_U8 buffer;
  struct ddog_prof_ProfiledEndpointsStats *endpoints_stats;
} ddog_prof_EncodedProfile;

typedef enum ddog_prof_Profile_SerializeResult_Tag {
  DDOG_PROF_PROFILE_SERIALIZE_RESULT_OK,
  DDOG_PROF_PROFILE_SERIALIZE_RESULT_ERR,
} ddog_prof_Profile_SerializeResult_Tag;

typedef struct ddog_prof_Profile_SerializeResult {
  ddog_prof_Profile_SerializeResult_Tag tag;
  union {
    struct {
      struct ddog_prof_EncodedProfile ok;
    };
    struct {
      struct ddog_Error err;
    };
  };
} ddog_prof_Profile_SerializeResult;

typedef enum ddog_prof_ManagedStringStorageNewResult_Tag {
  DDOG_PROF_MANAGED_STRING_STORAGE_NEW_RESULT_OK,
  DDOG_PROF_MANAGED_STRING_STORAGE_NEW_RESULT_ERR,
} ddog_prof_ManagedStringStorageNewResult_Tag;

typedef struct ddog_prof_ManagedStringStorageNewResult {
  ddog_prof_ManagedStringStorageNewResult_Tag tag;
  union {
    struct {
      struct ddog_prof_ManagedStringStorage ok;
    };
    struct {
      struct ddog_Error err;
    };
  };
} ddog_prof_ManagedStringStorageNewResult;

typedef enum ddog_prof_ManagedStringStorageInternResult_Tag {
  DDOG_PROF_MANAGED_STRING_STORAGE_INTERN_RESULT_OK,
  DDOG_PROF_MANAGED_STRING_STORAGE_INTERN_RESULT_ERR,
} ddog_prof_ManagedStringStorageInternResult_Tag;

typedef struct ddog_prof_ManagedStringStorageInternResult {
  ddog_prof_ManagedStringStorageInternResult_Tag tag;
  union {
    struct {
      struct ddog_prof_ManagedStringId ok;
    };
    struct {
      struct ddog_Error err;
    };
  };
} ddog_prof_ManagedStringStorageInternResult;

typedef struct ddog_prof_Slice_CharSlice {
  /**
   * Should be non-null and suitably aligned for the underlying type. It is
   * allowed but not recommended for the pointer to be null when the len is
   * zero.
   */
  const ddog_CharSlice *ptr;
  /**
   * The number of elements (not bytes) that `.ptr` points to. Must be less
   * than or equal to [isize::MAX].
   */
  uintptr_t len;
} ddog_prof_Slice_CharSlice;

typedef struct ddog_prof_Slice_ManagedStringId {
  /**
   * Should be non-null and suitably aligned for the underlying type. It is
   * allowed but not recommended for the pointer to be null when the len is
   * zero.
   */
  const struct ddog_prof_ManagedStringId *ptr;
  /**
   * The number of elements (not bytes) that `.ptr` points to. Must be less
   * than or equal to [isize::MAX].
   */
  uintptr_t len;
} ddog_prof_Slice_ManagedStringId;

typedef enum ddog_StringWrapperResult_Tag {
  DDOG_STRING_WRAPPER_RESULT_OK,
  DDOG_STRING_WRAPPER_RESULT_ERR,
} ddog_StringWrapperResult_Tag;

typedef struct ddog_StringWrapperResult {
  ddog_StringWrapperResult_Tag tag;
  union {
    struct {
      struct ddog_StringWrapper ok;
    };
    struct {
      struct ddog_Error err;
    };
  };
} ddog_StringWrapperResult;

typedef enum ddog_ConfigurationOrigin {
  DDOG_CONFIGURATION_ORIGIN_ENV_VAR,
  DDOG_CONFIGURATION_ORIGIN_CODE,
  DDOG_CONFIGURATION_ORIGIN_DD_CONFIG,
  DDOG_CONFIGURATION_ORIGIN_REMOTE_CONFIG,
  DDOG_CONFIGURATION_ORIGIN_DEFAULT,
} ddog_ConfigurationOrigin;

typedef enum ddog_LogLevel {
  DDOG_LOG_LEVEL_ERROR,
  DDOG_LOG_LEVEL_WARN,
  DDOG_LOG_LEVEL_DEBUG,
} ddog_LogLevel;

typedef enum ddog_MetricNamespace {
  DDOG_METRIC_NAMESPACE_TRACERS,
  DDOG_METRIC_NAMESPACE_PROFILERS,
  DDOG_METRIC_NAMESPACE_RUM,
  DDOG_METRIC_NAMESPACE_APPSEC,
  DDOG_METRIC_NAMESPACE_IDE_PLUGINS,
  DDOG_METRIC_NAMESPACE_LIVE_DEBUGGER,
  DDOG_METRIC_NAMESPACE_IAST,
  DDOG_METRIC_NAMESPACE_GENERAL,
  DDOG_METRIC_NAMESPACE_TELEMETRY,
  DDOG_METRIC_NAMESPACE_APM,
  DDOG_METRIC_NAMESPACE_SIDECAR,
} ddog_MetricNamespace;

typedef enum ddog_MetricType {
  DDOG_METRIC_TYPE_GAUGE,
  DDOG_METRIC_TYPE_COUNT,
  DDOG_METRIC_TYPE_DISTRIBUTION,
} ddog_MetricType;

typedef enum ddog_TelemetryWorkerBuilderBoolProperty {
  DDOG_TELEMETRY_WORKER_BUILDER_BOOL_PROPERTY_CONFIG_TELEMETRY_DEBUG_LOGGING_ENABLED,
} ddog_TelemetryWorkerBuilderBoolProperty;

typedef enum ddog_TelemetryWorkerBuilderEndpointProperty {
  DDOG_TELEMETRY_WORKER_BUILDER_ENDPOINT_PROPERTY_CONFIG_ENDPOINT,
} ddog_TelemetryWorkerBuilderEndpointProperty;

typedef enum ddog_TelemetryWorkerBuilderStrProperty {
  DDOG_TELEMETRY_WORKER_BUILDER_STR_PROPERTY_APPLICATION_SERVICE_VERSION,
  DDOG_TELEMETRY_WORKER_BUILDER_STR_PROPERTY_APPLICATION_ENV,
  DDOG_TELEMETRY_WORKER_BUILDER_STR_PROPERTY_APPLICATION_RUNTIME_NAME,
  DDOG_TELEMETRY_WORKER_BUILDER_STR_PROPERTY_APPLICATION_RUNTIME_VERSION,
  DDOG_TELEMETRY_WORKER_BUILDER_STR_PROPERTY_APPLICATION_RUNTIME_PATCHES,
  DDOG_TELEMETRY_WORKER_BUILDER_STR_PROPERTY_HOST_CONTAINER_ID,
  DDOG_TELEMETRY_WORKER_BUILDER_STR_PROPERTY_HOST_OS,
  DDOG_TELEMETRY_WORKER_BUILDER_STR_PROPERTY_HOST_KERNEL_NAME,
  DDOG_TELEMETRY_WORKER_BUILDER_STR_PROPERTY_HOST_KERNEL_RELEASE,
  DDOG_TELEMETRY_WORKER_BUILDER_STR_PROPERTY_HOST_KERNEL_VERSION,
  DDOG_TELEMETRY_WORKER_BUILDER_STR_PROPERTY_RUNTIME_ID,
} ddog_TelemetryWorkerBuilderStrProperty;

typedef struct ddog_TelemetryWorkerBuilder ddog_TelemetryWorkerBuilder;

/**
 * TelemetryWorkerHandle is a handle which allows interactions with the telemetry worker.
 * The handle is safe to use across threads.
 *
 * The worker won't send data to the agent until you call `TelemetryWorkerHandle::send_start`
 *
 * To stop the worker, call `TelemetryWorkerHandle::send_stop` which trigger flush asynchronously
 * then `TelemetryWorkerHandle::wait_for_shutdown`
 */
typedef struct ddog_TelemetryWorkerHandle ddog_TelemetryWorkerHandle;

typedef enum ddog_Option_Bool_Tag {
  DDOG_OPTION_BOOL_SOME_BOOL,
  DDOG_OPTION_BOOL_NONE_BOOL,
} ddog_Option_Bool_Tag;

typedef struct ddog_Option_Bool {
  ddog_Option_Bool_Tag tag;
  union {
    struct {
      bool some;
    };
  };
} ddog_Option_Bool;

typedef struct ddog_ContextKey {
  uint32_t _0;
  enum ddog_MetricType _1;
} ddog_ContextKey;

typedef enum ddog_crasht_BuildIdType {
  DDOG_CRASHT_BUILD_ID_TYPE_GNU,
  DDOG_CRASHT_BUILD_ID_TYPE_GO,
  DDOG_CRASHT_BUILD_ID_TYPE_PDB,
  DDOG_CRASHT_BUILD_ID_TYPE_SHA1,
} ddog_crasht_BuildIdType;

typedef enum ddog_crasht_DemangleOptions {
  DDOG_CRASHT_DEMANGLE_OPTIONS_COMPLETE,
  DDOG_CRASHT_DEMANGLE_OPTIONS_NAME_ONLY,
} ddog_crasht_DemangleOptions;

typedef enum ddog_crasht_ErrorKind {
  DDOG_CRASHT_ERROR_KIND_PANIC,
  DDOG_CRASHT_ERROR_KIND_UNHANDLED_EXCEPTION,
  DDOG_CRASHT_ERROR_KIND_UNIX_SIGNAL,
} ddog_crasht_ErrorKind;

typedef enum ddog_crasht_FileType {
  DDOG_CRASHT_FILE_TYPE_APK,
  DDOG_CRASHT_FILE_TYPE_ELF,
  DDOG_CRASHT_FILE_TYPE_PE,
} ddog_crasht_FileType;

/**
 * This enum represents operations a the tracked library might be engaged in.
 * Currently only implemented for profiling.
 * The idea is that if a crash consistently occurs while a particular operation
 * is ongoing, its likely related.
 *
 * In the future, we might also track wall-clock time of operations
 * (or some statistical sampling thereof) using the same enum.
 *
 * NOTE: This enum is known to be non-exhaustive.  Feel free to add new types
 *       as needed.
 */
typedef enum ddog_crasht_OpTypes {
  DDOG_CRASHT_OP_TYPES_PROFILER_INACTIVE = 0,
  DDOG_CRASHT_OP_TYPES_PROFILER_COLLECTING_SAMPLE,
  DDOG_CRASHT_OP_TYPES_PROFILER_UNWINDING,
  DDOG_CRASHT_OP_TYPES_PROFILER_SERIALIZING,
  /**
   * Dummy value to allow easier iteration
   */
  DDOG_CRASHT_OP_TYPES_SIZE,
} ddog_crasht_OpTypes;

/**
 * See https://man7.org/linux/man-pages/man2/sigaction.2.html
 */
typedef enum ddog_crasht_SiCodes {
  DDOG_CRASHT_SI_CODES_BUS_ADRALN,
  DDOG_CRASHT_SI_CODES_BUS_ADRERR,
  DDOG_CRASHT_SI_CODES_BUS_MCEERR_AO,
  DDOG_CRASHT_SI_CODES_BUS_MCEERR_AR,
  DDOG_CRASHT_SI_CODES_BUS_OBJERR,
  DDOG_CRASHT_SI_CODES_SEGV_ACCERR,
  DDOG_CRASHT_SI_CODES_SEGV_BNDERR,
  DDOG_CRASHT_SI_CODES_SEGV_MAPERR,
  DDOG_CRASHT_SI_CODES_SEGV_PKUERR,
  DDOG_CRASHT_SI_CODES_SI_ASYNCIO,
  DDOG_CRASHT_SI_CODES_SI_KERNEL,
  DDOG_CRASHT_SI_CODES_SI_MESGQ,
  DDOG_CRASHT_SI_CODES_SI_QUEUE,
  DDOG_CRASHT_SI_CODES_SI_SIGIO,
  DDOG_CRASHT_SI_CODES_SI_TIMER,
  DDOG_CRASHT_SI_CODES_SI_TKILL,
  DDOG_CRASHT_SI_CODES_SI_USER,
  DDOG_CRASHT_SI_CODES_SYS_SECCOMP,
  DDOG_CRASHT_SI_CODES_UNKNOWN,
} ddog_crasht_SiCodes;

/**
 * See https://man7.org/linux/man-pages/man7/signal.7.html
 */
typedef enum ddog_crasht_SignalNames {
  DDOG_CRASHT_SIGNAL_NAMES_SIGABRT,
  DDOG_CRASHT_SIGNAL_NAMES_SIGBUS,
  DDOG_CRASHT_SIGNAL_NAMES_SIGSEGV,
  DDOG_CRASHT_SIGNAL_NAMES_SIGSYS,
  DDOG_CRASHT_SIGNAL_NAMES_UNKNOWN,
} ddog_crasht_SignalNames;

/**
 * Stacktrace collection occurs in the context of a crashing process.
 * If the stack is sufficiently corruputed, it is possible (but unlikely),
 * for stack trace collection itself to crash.
 * We recommend fully enabling stacktrace collection, but having an environment
 * variable to allow downgrading the collector.
 */
typedef enum ddog_crasht_StacktraceCollection {
  /**
   * Stacktrace collection occurs in the
   */
  DDOG_CRASHT_STACKTRACE_COLLECTION_DISABLED,
  DDOG_CRASHT_STACKTRACE_COLLECTION_WITHOUT_SYMBOLS,
  DDOG_CRASHT_STACKTRACE_COLLECTION_ENABLED_WITH_INPROCESS_SYMBOLS,
  DDOG_CRASHT_STACKTRACE_COLLECTION_ENABLED_WITH_SYMBOLS_IN_RECEIVER,
} ddog_crasht_StacktraceCollection;

typedef struct ddog_crasht_CrashInfo ddog_crasht_CrashInfo;

typedef struct ddog_crasht_CrashInfoBuilder ddog_crasht_CrashInfoBuilder;

typedef struct ddog_crasht_StackFrame ddog_crasht_StackFrame;

typedef struct ddog_crasht_StackTrace ddog_crasht_StackTrace;

/**
 * A generic result type for when an operation may fail,
 * but there's nothing to return in the case of success.
 */
typedef enum ddog_VoidResult_Tag {
  DDOG_VOID_RESULT_OK,
  DDOG_VOID_RESULT_ERR,
} ddog_VoidResult_Tag;

typedef struct ddog_VoidResult {
  ddog_VoidResult_Tag tag;
  union {
    struct {
      /**
       * Do not use the value of Ok. This value only exists to overcome
       * Rust -> C code generation.
       */
      bool ok;
    };
    struct {
      struct ddog_Error err;
    };
  };
} ddog_VoidResult;

typedef struct ddog_crasht_Slice_CharSlice {
  /**
   * Should be non-null and suitably aligned for the underlying type. It is
   * allowed but not recommended for the pointer to be null when the len is
   * zero.
   */
  const ddog_CharSlice *ptr;
  /**
   * The number of elements (not bytes) that `.ptr` points to. Must be less
   * than or equal to [isize::MAX].
   */
  uintptr_t len;
} ddog_crasht_Slice_CharSlice;

typedef struct ddog_crasht_Config {
  struct ddog_crasht_Slice_CharSlice additional_files;
  bool create_alt_stack;
  bool use_alt_stack;
  /**
   * The endpoint to send the crash report to (can be a file://).
   * If None, the crashtracker will infer the agent host from env variables.
   */
  const struct ddog_Endpoint *endpoint;
  enum ddog_crasht_StacktraceCollection resolve_frames;
  /**
   * Timeout in milliseconds before the signal handler starts tearing things down to return.
   * This is given as a uint32_t, but the actual timeout needs to fit inside of an i32 (max
   * 2^31-1). This is a limitation of the various interfaces used to guarantee the timeout.
   */
  uint32_t timeout_ms;
  /**
   * Optional filename for a unix domain socket if the receiver is used asynchonously
   */
  ddog_CharSlice optional_unix_socket_filename;
} ddog_crasht_Config;

typedef struct ddog_crasht_EnvVar {
  ddog_CharSlice key;
  ddog_CharSlice val;
} ddog_crasht_EnvVar;

typedef struct ddog_crasht_Slice_EnvVar {
  /**
   * Should be non-null and suitably aligned for the underlying type. It is
   * allowed but not recommended for the pointer to be null when the len is
   * zero.
   */
  const struct ddog_crasht_EnvVar *ptr;
  /**
   * The number of elements (not bytes) that `.ptr` points to. Must be less
   * than or equal to [isize::MAX].
   */
  uintptr_t len;
} ddog_crasht_Slice_EnvVar;

typedef struct ddog_crasht_ReceiverConfig {
  struct ddog_crasht_Slice_CharSlice args;
  struct ddog_crasht_Slice_EnvVar env;
  ddog_CharSlice path_to_receiver_binary;
  /**
   * Optional filename to forward stderr to (useful for logging/debugging)
   */
  ddog_CharSlice optional_stderr_filename;
  /**
   * Optional filename to forward stdout to (useful for logging/debugging)
   */
  ddog_CharSlice optional_stdout_filename;
} ddog_crasht_ReceiverConfig;

typedef struct ddog_crasht_Metadata {
  ddog_CharSlice library_name;
  ddog_CharSlice library_version;
  ddog_CharSlice family;
  /**
   * Should include "service", "environment", etc
   */
  const struct ddog_Vec_Tag *tags;
} ddog_crasht_Metadata;

/**
 * A generic result type for when an operation may fail,
 * or may return <T> in case of success.
 */
typedef enum ddog_crasht_Result_Usize_Tag {
  DDOG_CRASHT_RESULT_USIZE_OK_USIZE,
  DDOG_CRASHT_RESULT_USIZE_ERR_USIZE,
} ddog_crasht_Result_Usize_Tag;

typedef struct ddog_crasht_Result_Usize {
  ddog_crasht_Result_Usize_Tag tag;
  union {
    struct {
      uintptr_t ok;
    };
    struct {
      struct ddog_Error err;
    };
  };
} ddog_crasht_Result_Usize;

/**
 * Represents an object that should only be referred to by its handle.
 * Do not access its member for any reason, only use the C API functions on this struct.
 */
typedef struct ddog_crasht_Handle_CrashInfo {
  struct ddog_crasht_CrashInfo *inner;
} ddog_crasht_Handle_CrashInfo;

/**
 * Represents an object that should only be referred to by its handle.
 * Do not access its member for any reason, only use the C API functions on this struct.
 */
typedef struct ddog_crasht_Handle_CrashInfoBuilder {
  struct ddog_crasht_CrashInfoBuilder *inner;
} ddog_crasht_Handle_CrashInfoBuilder;

typedef enum ddog_crasht_CrashInfo_NewResult_Tag {
  DDOG_CRASHT_CRASH_INFO_NEW_RESULT_OK,
  DDOG_CRASHT_CRASH_INFO_NEW_RESULT_ERR,
} ddog_crasht_CrashInfo_NewResult_Tag;

typedef struct ddog_crasht_CrashInfo_NewResult {
  ddog_crasht_CrashInfo_NewResult_Tag tag;
  union {
    struct {
      struct ddog_crasht_Handle_CrashInfo ok;
    };
    struct {
      struct ddog_Error err;
    };
  };
} ddog_crasht_CrashInfo_NewResult;

typedef struct ddog_crasht_OsInfo {
  ddog_CharSlice architecture;
  ddog_CharSlice bitness;
  ddog_CharSlice os_type;
  ddog_CharSlice version;
} ddog_crasht_OsInfo;

typedef struct ddog_crasht_ProcInfo {
  uint32_t pid;
} ddog_crasht_ProcInfo;

typedef struct ddog_crasht_SigInfo {
  ddog_CharSlice addr;
  int code;
  enum ddog_crasht_SiCodes code_human_readable;
  int signo;
  enum ddog_crasht_SignalNames signo_human_readable;
} ddog_crasht_SigInfo;

typedef struct ddog_crasht_Span {
  ddog_CharSlice id;
  ddog_CharSlice thread_name;
} ddog_crasht_Span;

/**
 * Represents an object that should only be referred to by its handle.
 * Do not access its member for any reason, only use the C API functions on this struct.
 */
typedef struct ddog_crasht_Handle_StackTrace {
  struct ddog_crasht_StackTrace *inner;
} ddog_crasht_Handle_StackTrace;

typedef struct ddog_crasht_ThreadData {
  bool crashed;
  ddog_CharSlice name;
  struct ddog_crasht_Handle_StackTrace stack;
  ddog_CharSlice state;
} ddog_crasht_ThreadData;

/**
 * Represents an object that should only be referred to by its handle.
 * Do not access its member for any reason, only use the C API functions on this struct.
 */
typedef struct ddog_crasht_Handle_StackFrame {
  struct ddog_crasht_StackFrame *inner;
} ddog_crasht_Handle_StackFrame;

typedef enum ddog_crasht_StackFrame_NewResult_Tag {
  DDOG_CRASHT_STACK_FRAME_NEW_RESULT_OK,
  DDOG_CRASHT_STACK_FRAME_NEW_RESULT_ERR,
} ddog_crasht_StackFrame_NewResult_Tag;

typedef struct ddog_crasht_StackFrame_NewResult {
  ddog_crasht_StackFrame_NewResult_Tag tag;
  union {
    struct {
      struct ddog_crasht_Handle_StackFrame ok;
    };
    struct {
      struct ddog_Error err;
    };
  };
} ddog_crasht_StackFrame_NewResult;

/**
 * Represent error codes that `Error` struct can hold
 */
typedef enum ddog_TraceExporterErrorCode {
  DDOG_TRACE_EXPORTER_ERROR_CODE_ADDRESS_IN_USE,
  DDOG_TRACE_EXPORTER_ERROR_CODE_CONNECTION_ABORTED,
  DDOG_TRACE_EXPORTER_ERROR_CODE_CONNECTION_REFUSED,
  DDOG_TRACE_EXPORTER_ERROR_CODE_CONNECTION_RESET,
  DDOG_TRACE_EXPORTER_ERROR_CODE_HTTP_BODY_FORMAT,
  DDOG_TRACE_EXPORTER_ERROR_CODE_HTTP_BODY_TOO_LONG,
  DDOG_TRACE_EXPORTER_ERROR_CODE_HTTP_CLIENT,
  DDOG_TRACE_EXPORTER_ERROR_CODE_HTTP_EMPTY_BODY,
  DDOG_TRACE_EXPORTER_ERROR_CODE_HTTP_PARSE,
  DDOG_TRACE_EXPORTER_ERROR_CODE_HTTP_SERVER,
  DDOG_TRACE_EXPORTER_ERROR_CODE_HTTP_UNKNOWN,
  DDOG_TRACE_EXPORTER_ERROR_CODE_HTTP_WRONG_STATUS,
  DDOG_TRACE_EXPORTER_ERROR_CODE_INVALID_ARGUMENT,
  DDOG_TRACE_EXPORTER_ERROR_CODE_INVALID_DATA,
  DDOG_TRACE_EXPORTER_ERROR_CODE_INVALID_INPUT,
  DDOG_TRACE_EXPORTER_ERROR_CODE_INVALID_URL,
  DDOG_TRACE_EXPORTER_ERROR_CODE_IO_ERROR,
  DDOG_TRACE_EXPORTER_ERROR_CODE_NETWORK_UNKNOWN,
  DDOG_TRACE_EXPORTER_ERROR_CODE_SERDE,
  DDOG_TRACE_EXPORTER_ERROR_CODE_TIMED_OUT,
} ddog_TraceExporterErrorCode;

/**
 * The TraceExporter ingest traces from the tracers serialized as messagepack and forward them to
 * the agent while applying some transformation.
 *
 * # Proxy
 * If the input format is set as `Proxy`, the exporter will forward traces to the agent without
 * deserializing them.
 *
 * # Features
 * When the input format is set to `V04` the TraceExporter will deserialize the traces and perform
 * some operation before sending them to the agent. The available operations are described below.
 *
 * ## V07 Serialization
 * The Trace exporter can serialize the traces to V07 before sending them to the agent.
 *
 * ## Stats computation
 * The Trace Exporter can compute stats on traces. In this case the trace exporter will start
 * another task to send stats when a time bucket expire. When this feature is enabled the
 * TraceExporter drops all spans that may not be sampled by the agent.
 */
typedef struct ddog_TraceExporter ddog_TraceExporter;

/**
 * The TraceExporterConfig object will hold the configuration properties for the TraceExporter.
 * Once the configuration is passed to the TraceExporter constructor the config is no longer
 * needed by the handle and it can be freed.
 */
typedef struct ddog_TraceExporterConfig ddog_TraceExporterConfig;

/**
 * Stucture that contains error information that `TraceExporter` API can return.
 */
typedef struct ddog_TraceExporterError {
  enum ddog_TraceExporterErrorCode code;
  char *msg;
} ddog_TraceExporterError;

/**
 * `AgentResponse` structure holds agent response information upon successful request.
 */
typedef struct ddog_AgentResponse {
  /**
   * Sampling rate for the current service.
   */
  double rate;
} ddog_AgentResponse;

typedef enum ddog_LibraryConfigName {
  DDOG_LIBRARY_CONFIG_NAME_DD_APM_TRACING_ENABLED,
  DDOG_LIBRARY_CONFIG_NAME_DD_RUNTIME_METRICS_ENABLED,
  DDOG_LIBRARY_CONFIG_NAME_DD_LOGS_INJECTION,
  DDOG_LIBRARY_CONFIG_NAME_DD_PROFILING_ENABLED,
  DDOG_LIBRARY_CONFIG_NAME_DD_DATA_STREAMS_ENABLED,
  DDOG_LIBRARY_CONFIG_NAME_DD_APPSEC_ENABLED,
  DDOG_LIBRARY_CONFIG_NAME_DD_IAST_ENABLED,
  DDOG_LIBRARY_CONFIG_NAME_DD_DYNAMIC_INSTRUMENTATION_ENABLED,
  DDOG_LIBRARY_CONFIG_NAME_DD_DATA_JOBS_ENABLED,
  DDOG_LIBRARY_CONFIG_NAME_DD_APPSEC_SCA_ENABLED,
  DDOG_LIBRARY_CONFIG_NAME_DD_TRACE_DEBUG,
  DDOG_LIBRARY_CONFIG_NAME_DD_SERVICE,
  DDOG_LIBRARY_CONFIG_NAME_DD_ENV,
  DDOG_LIBRARY_CONFIG_NAME_DD_VERSION,
} ddog_LibraryConfigName;

typedef enum ddog_LibraryConfigSource {
  DDOG_LIBRARY_CONFIG_SOURCE_LOCAL_STABLE_CONFIG = 0,
  DDOG_LIBRARY_CONFIG_SOURCE_FLEET_STABLE_CONFIG = 1,
} ddog_LibraryConfigSource;

typedef struct ddog_Configurator ddog_Configurator;

/**
 * Ffi safe type representing a borrowed null-terminated C array
 * Equivalent to a std::ffi::CStr
 */
typedef struct ddog_CStr {
  /**
   * Null terminated char array
   */
  char *ptr;
  /**
   * Length of the array, not counting the null-terminator
   */
  uintptr_t length;
} ddog_CStr;

typedef struct ddog_Slice_CharSlice {
  /**
   * Should be non-null and suitably aligned for the underlying type. It is
   * allowed but not recommended for the pointer to be null when the len is
   * zero.
   */
  const ddog_CharSlice *ptr;
  /**
   * The number of elements (not bytes) that `.ptr` points to. Must be less
   * than or equal to [isize::MAX].
   */
  uintptr_t len;
} ddog_Slice_CharSlice;

typedef struct ddog_ProcessInfo {
  struct ddog_Slice_CharSlice args;
  struct ddog_Slice_CharSlice envp;
  ddog_CharSlice language;
} ddog_ProcessInfo;

/**
 * Ffi safe type representing an owned null-terminated C array
 * Equivalent to a std::ffi::CString
 */
typedef struct ddog_CString {
  /**
   * Null terminated char array
   */
  char *ptr;
  /**
   * Length of the array, not counting the null-terminator
   */
  uintptr_t length;
} ddog_CString;

typedef struct ddog_LibraryConfig {
  enum ddog_LibraryConfigName name;
  struct ddog_CString value;
} ddog_LibraryConfig;

/**
 * Holds the raw parts of a Rust Vec; it should only be created from Rust,
 * never from C.
 */
typedef struct ddog_Vec_LibraryConfig {
  const struct ddog_LibraryConfig *ptr;
  uintptr_t len;
  uintptr_t capacity;
} ddog_Vec_LibraryConfig;

/**
 * A generic result type for when an operation may fail,
 * or may return <T> in case of success.
 */
typedef enum ddog_Result_VecLibraryConfig_Tag {
  DDOG_RESULT_VEC_LIBRARY_CONFIG_OK_VEC_LIBRARY_CONFIG,
  DDOG_RESULT_VEC_LIBRARY_CONFIG_ERR_VEC_LIBRARY_CONFIG,
} ddog_Result_VecLibraryConfig_Tag;

typedef struct ddog_Result_VecLibraryConfig {
  ddog_Result_VecLibraryConfig_Tag tag;
  union {
    struct {
      struct ddog_Vec_LibraryConfig ok;
    };
    struct {
      struct ddog_Error err;
    };
  };
} ddog_Result_VecLibraryConfig;

#ifdef __cplusplus
extern "C" {
#endif // __cplusplus

/**
 * # Safety
 * Only pass null or a valid reference to a `ddog_Error`.
 */
void ddog_Error_drop(struct ddog_Error *error);

/**
 * Returns a CharSlice of the error's message that is valid until the error
 * is dropped.
 * # Safety
 * Only pass null or a valid reference to a `ddog_Error`.
 */
ddog_CharSlice ddog_Error_message(const struct ddog_Error *error);

void ddog_MaybeError_drop(ddog_MaybeError);

/**
 * Creates a new ArrayQueue with the given capacity and item_delete_fn.
 * The item_delete_fn is called when an item is dropped from the queue.
 */
DDOG_CHECK_RETURN
struct ddog_ArrayQueue_NewResult ddog_ArrayQueue_new(uintptr_t capacity,
                                                     void (*item_delete_fn)(void*));

/**
 * Drops the ArrayQueue.
 * # Safety
 * The pointer is null or points to a valid memory location allocated by ArrayQueue_new.
 */
void ddog_ArrayQueue_drop(struct ddog_ArrayQueue *queue);

/**
 * Pushes an item into the ArrayQueue. It returns the given value if the queue is full.
 * # Safety
 * The pointer is null or points to a valid memory location allocated by ArrayQueue_new. The value
 * is null or points to a valid memory location that can be deallocated by the item_delete_fn.
 */
struct ddog_ArrayQueue_PushResult ddog_ArrayQueue_push(const struct ddog_ArrayQueue *queue_ptr,
                                                       void *value);

/**
 * Pushes an element into the queue, replacing the oldest element if necessary.
 * # Safety
 * The pointer is null or points to a valid memory location allocated by ArrayQueue_new. The value
 * is null or points to a valid memory location that can be deallocated by the item_delete_fn.
 */
DDOG_CHECK_RETURN
struct ddog_ArrayQueue_PushResult ddog_ArrayQueue_force_push(const struct ddog_ArrayQueue *queue_ptr,
                                                             void *value);

/**
 * Pops an item from the ArrayQueue.
 * # Safety
 * The pointer is null or points to a valid memory location allocated by ArrayQueue_new.
 */
DDOG_CHECK_RETURN
struct ddog_ArrayQueue_PopResult ddog_ArrayQueue_pop(const struct ddog_ArrayQueue *queue_ptr);

/**
 * Checks if the ArrayQueue is empty.
 * # Safety
 * The pointer is null or points to a valid memory location allocated by ArrayQueue_new.
 */
struct ddog_ArrayQueue_BoolResult ddog_ArrayQueue_is_empty(const struct ddog_ArrayQueue *queue_ptr);

/**
 * Returns the length of the ArrayQueue.
 * # Safety
 * The pointer is null or points to a valid memory location allocated by ArrayQueue_new.
 */
struct ddog_ArrayQueue_UsizeResult ddog_ArrayQueue_len(const struct ddog_ArrayQueue *queue_ptr);

/**
 * Returns true if the underlying queue is full.
 * # Safety
 * The pointer is null or points to a valid memory location allocated by ArrayQueue_new.
 */
struct ddog_ArrayQueue_BoolResult ddog_ArrayQueue_is_full(const struct ddog_ArrayQueue *queue_ptr);

/**
 * Returns the capacity of the ArrayQueue.
 * # Safety
 * The pointer is null or points to a valid memory location allocated by ArrayQueue_new.
 */
struct ddog_ArrayQueue_UsizeResult ddog_ArrayQueue_capacity(const struct ddog_ArrayQueue *queue_ptr);

DDOG_CHECK_RETURN struct ddog_Endpoint *ddog_endpoint_from_url(ddog_CharSlice url);

DDOG_CHECK_RETURN struct ddog_Endpoint *ddog_endpoint_from_filename(ddog_CharSlice filename);

DDOG_CHECK_RETURN struct ddog_Endpoint *ddog_endpoint_from_api_key(ddog_CharSlice api_key);

DDOG_CHECK_RETURN
struct ddog_Error *ddog_endpoint_from_api_key_and_site(ddog_CharSlice api_key,
                                                       ddog_CharSlice site,
                                                       struct ddog_Endpoint **endpoint);

void ddog_endpoint_set_timeout(struct ddog_Endpoint *endpoint, uint64_t millis);

void ddog_endpoint_set_test_token(struct ddog_Endpoint *endpoint, ddog_CharSlice token);

void ddog_endpoint_drop(struct ddog_Endpoint*);

struct ddog_Option_U32 ddog_Option_U32_some(uint32_t v);

struct ddog_Option_U32 ddog_Option_U32_none(void);

/**
 * # Safety
 * Only pass null or a valid reference to a `ddog_StringWrapper`.
 */
void ddog_StringWrapper_drop(struct ddog_StringWrapper *s);

/**
 * Returns a CharSlice of the message that is valid until the StringWrapper
 * is dropped.
 * # Safety
 * Only pass null or a valid reference to a `ddog_StringWrapper`.
 */
ddog_CharSlice ddog_StringWrapper_message(const struct ddog_StringWrapper *s);

DDOG_CHECK_RETURN struct ddog_Vec_Tag ddog_Vec_Tag_new(void);

void ddog_Vec_Tag_drop(struct ddog_Vec_Tag);

/**
 * Creates a new Tag from the provided `key` and `value` by doing a utf8
 * lossy conversion, and pushes into the `vec`. The strings `key` and `value`
 * are cloned to avoid FFI lifetime issues.
 *
 * # Safety
 * The `vec` must be a valid reference.
 * The CharSlices `key` and `value` must point to at least many bytes as their
 * `.len` properties claim.
 */
DDOG_CHECK_RETURN
struct ddog_Vec_Tag_PushResult ddog_Vec_Tag_push(struct ddog_Vec_Tag *vec,
                                                 ddog_CharSlice key,
                                                 ddog_CharSlice value);

/**
 * # Safety
 * The `string`'s .ptr must point to a valid object at least as large as its
 * .len property.
 */
DDOG_CHECK_RETURN struct ddog_Vec_Tag_ParseResult ddog_Vec_Tag_parse(ddog_CharSlice string);

#ifdef __cplusplus
}  // extern "C"
#endif  // __cplusplus

#endif  /* DDOG_COMMON_H */
