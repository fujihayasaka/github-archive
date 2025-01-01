# typed: true
# frozen_string_literal: true

require "test_helper"

class ApiLimitersAuthenticationFingerprintByPathTest < GitHub::TestCase

  setup do
    enable_cache_storage
    max = 5
    @max_rate_limit_endpoint = max * Api::Limiters::AuthenticationFingerprintByPath::RATE_LIMIT_ENDPOINT_MULTIPLIER
    @limiter = Api::Limiters::AuthenticationFingerprintByPath.new(max: max)
    @fingerprint = Api::RequestAuthenticationFingerprint.from({ "REMOTE_ADDR" => "127.0.0.1" })
  end

  teardown do
    reset_cache
  end

  def request(path_info = "/rate_limit")
    Rack::Request.new({
      Api::Middleware::RequestAuthenticationFingerprint::AUTHENTICATION_FINGERPRINT => @fingerprint,
      "PATH_INFO" => path_info,
      "REQUEST_METHOD" => "GET",
      Rack::RequestLogger::APPLICATION_LOG_DATA => {},
    })
  end
end
