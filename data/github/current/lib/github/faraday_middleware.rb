# typed: true
# frozen_string_literal: true

module GitHub
  module FaradayMiddleware
    autoload :Datadog,            "github/faraday_middleware/datadog"
    autoload :DatadogAsync,       "github/faraday_middleware/datadog_async"
    autoload :AsyncDuration,      "github/faraday_middleware/async_duration"
    autoload :CountryCode,        "github/faraday_middleware/country_code"
    autoload :HMACAuth,           "github/faraday_middleware/hmac_auth"
    autoload :IncreasingTimeout,  "github/faraday_middleware/increasing_timeout"
    autoload :RaiseError,         "github/faraday_middleware/raise_error"
    autoload :RequestID,          "github/faraday_middleware/request_id"
    autoload :Staffbar,           "github/faraday_middleware/staffbar"
    autoload :TenantContext,      "github/faraday_middleware/tenant_context"
    autoload :Resilient,          "github/faraday_middleware/resilient"
    autoload :Retries,            "github/faraday_middleware/retries"
    autoload :RequestAnalytics,   "github/faraday_middleware/request_analytics"
    autoload :RequestTimeoutHeader,     "github/faraday_middleware/request_timeout_header"
  end
end
