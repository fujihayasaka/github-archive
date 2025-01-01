# typed: true
# frozen_string_literal: true

require "test_helper"

class ApiLimitersElapsedAuthenticatedTimeByPathTest < GitHub::TestCase
  setup do
    enable_cache_storage
    @limiter = Api::Limiters::ElapsedAuthenticatedTimeByPath.new("time-based-limittown", max: 2, path: "/limittown")
    fingerprint = Api::RequestAuthenticationFingerprint.from({ "REMOTE_ADDR" => "127.0.0.1" })
    @request = Rack::Request.new({
      Api::Middleware::RequestAuthenticationFingerprint::AUTHENTICATION_FINGERPRINT => fingerprint,
      "PATH_INFO" => "/limittown",
    })
  end

  teardown do
    reset_cache
  end

  test "has the expected name" do
    assert_equal "time-based-limittown", @limiter.name
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

  test "does not return a limited state if the request is for a different path" do
    fingerprint = Api::RequestAuthenticationFingerprint.from({ "REMOTE_ADDR" => "127.0.0.1" })
    request = Rack::Request.new({
      Api::Middleware::RequestAuthenticationFingerprint::AUTHENTICATION_FINGERPRINT => fingerprint,
      "PATH_INFO" => "/wrong",
    })

    @limiter.start(request)
    sleep 0.003
    assert_nil @limiter.finish(request)

    state = @limiter.start(request)
    refute state.limited?
  end

  test "requests to /rate_limit are ignored by limiter" do
    @request.path_info = "/rate_limit"

    assert @limiter.ignored?(@request)
  end
end
