# typed: true
# frozen_string_literal: true

module GitHub
  module FaradayMiddleware
    autoload :CallerContext,      "github/faraday_middleware/caller_context"
    autoload :Datadog,            "github/faraday_middleware/datadog"
    autoload :DatadogAsync,       "github/faraday_middleware/datadog_async"
    autoload :AsyncDuration,      "github/faraday_middleware/async_duration"
    autoload :CountryCode,        "github/faraday_middleware/country_code"
    autoload :DriftwoodRequestID, "github/faraday_middleware/driftwood_request_id"
    autoload :RYOWsHeader,         "github/faraday_middleware/ryows_header"
    autoload :HMACAuth,           "github/faraday_middleware/hmac_auth"
    autoload :IncreasingTimeout,  "github/faraday_middleware/increasing_timeout"
    autoload :RaiseError,         "github/faraday_middleware/raise_error"
    autoload :RequestID,          "github/faraday_middleware/request_id"
    autoload :Staffbar,           "github/faraday_middleware/staffbar"
    autoload :TenantContext,      "github/faraday_middleware/tenant_context"
    autoload :Resilient,          "github/faraday_middleware/resilient"
    autoload :Retries,            "github/faraday_middleware/retries"
    autoload :RequestAnalytics,   "github/faraday_middleware/request_analytics"
    autoload :RequestFromHeader,  "github/faraday_middleware/request_from_header"
    autoload :RequestTimeoutHeader,     "github/faraday_middleware/request_timeout_header"
    autoload :StaffRequest,             "github/faraday_middleware/staff_request"
    autoload :TimeshiftedHeader,        "github/faraday_middleware/timeshifted_header"
    autoload :TracingAttributes,        "github/faraday_middleware/tracing_attributes"
  end
end
