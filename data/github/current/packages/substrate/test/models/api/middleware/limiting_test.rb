# typed: false
# frozen_string_literal: true

require "test_helper"
require "json"

class ApiMiddlewareLimitingTest < GitHub::TestCase
  nope = GitHub::Limiters::Simple.new("nope") { GitHub::Limiter::LIMITED }

  setup do
    GitHub.stubs(:request_limiting_enabled?).returns(true)
  end

  test "whitelists requests to /status" do
    path = "/status"
    status, _, _ = middleware(nope).call(env.merge("PATH_INFO" => path))
    assert_equal 200, status
  end

  test "whitelists browser reporting paths" do
    path = "/_private/browser/stats"
    status, _, _ = middleware(nope).call(env.merge("PATH_INFO" => path))
    assert_equal 200, status

    path = "/_private/browser/errors"
    status, _, _ = middleware(nope).call(env.merge("PATH_INFO" => path))
    assert_equal 200, status
  end

  test "whitelists LFS paths" do
    path = "/lfs/pengwynn/flint/objects"
    status, _, _ = middleware(nope).call(env.merge("PATH_INFO" => path))
    assert_equal 200, status

    path = "/lfs/pengwynn/flint/objects/6886dcdc7b37edf9e5a5c18db19ca70d33027423"
    status, _, _ = middleware(nope).call(env.merge("PATH_INFO" => path))
    assert_equal 200, status
  end

  test "whitelists ignored versions" do
    path = "/"
    status, _, _ = middleware(nope).call(env.merge("PATH_INFO" => path, "HTTP_ACCEPT" => "application/vnd.github.smasher"))
    assert_equal 200, status
  end

  test "doesn't whitelist everything" do
    status, _, _ = middleware(nope).call(env)
    assert_equal 429, status
  end

  test "bypasses when going through varnish" do
    GitHub.stubs(:varnish_enabled?).returns(true)
    status, _, _ = middleware(nope).call(env.merge("HTTP_X_GITHUB_DYNAMIC_CACHE" => "api"))
    assert_equal 200, status
  end

  protected

  def app
    lambda { |_env| [200, { "Content-Type" => "application/json" }, ["{}"]] }
  end

  def env
    { "PATH_INFO" => "/", "REQUEST_METHOD" => "GET" }
  end

  def middleware(*limiters)
    Api::Middleware::Limiting.new(app, *limiters)
  end
end
