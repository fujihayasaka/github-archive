# typed: true
# frozen_string_literal: true

require "test_helper"

class ApiLimitersElapsedTimeByAuthenticationFingerprintTest < GitHub::TestCase

  setup do
    enable_cache_storage
    @limiter = Api::Limiters::ElapsedTimeByAuthenticationFingerprint.new(max: 2)
    fingerprint = Api::RequestAuthenticationFingerprint.from({ "REMOTE_ADDR" => "127.0.0.1" })
    @request = Rack::Request.new(Api::Middleware::RequestAuthenticationFingerprint::AUTHENTICATION_FINGERPRINT => fingerprint)
  end

  teardown do
    reset_cache
  end

  test "has the expected name" do
    assert_equal "time-based", @limiter.name
  end

  test "increments the cache with the expected number of miliseconds" do
    @limiter.start(@request)
    sleep 0.002
    assert_operator @limiter.finish(@request), :>=, 2
  end

  test "returns a limited state after reaching the maximum milliseconds" do
    @limiter.start(@request)
    sleep 0.003
    assert_operator @limiter.finish(@request), :>=, 3

    state = @limiter.start(@request)
    assert state.limited?
  end

  test "requests to /rate_limit are ignored by limiter" do
    @request.path_info = "/rate_limit"

    assert @limiter.ignored?(@request)
  end
end
