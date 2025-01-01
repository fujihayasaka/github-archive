# typed: true
# frozen_string_literal: true

require "test_helper"

class ApiLimitersConcurrentAuthenticationFingerprintTest < GitHub::TestCase

  setup do
    enable_cache_storage
    @limiter = Api::Limiters::ConcurrentAuthenticationFingerprint.new(ttl: 60, max: 2)
    fingerprint = Api::RequestAuthenticationFingerprint.from({ "REMOTE_ADDR" => "127.0.0.1" })
    @request = Rack::Request.new(Api::Middleware::RequestAuthenticationFingerprint::AUTHENTICATION_FINGERPRINT => fingerprint)
  end

  teardown do
    reset_cache
  end

  test "limits concurrent requests" do
    refute_predicate @limiter.start(@request), :limited?  # allow 1st request
    refute_predicate @limiter.start(@request), :limited?  # allow 2nd request
    assert_predicate @limiter.start(@request), :limited?  # block 3rd request

    @limiter.finish(@request)  # a request finished, only 1 still running
    refute_predicate @limiter.start(@request), :limited?  # allow 2nd request
    third = @limiter.start(@request) # block 3rd request
    assert_predicate third, :limited?
    assert_equal Api::Limiters::ConcurrentAuthenticationFingerprint::RESET_DURATION, third.duration
  end

  test "requests to /rate_limit are ignored by limiter" do
    @request.path_info = "/rate_limit"

    assert @limiter.ignored?(@request)
  end
end
