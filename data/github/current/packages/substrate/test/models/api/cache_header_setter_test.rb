# typed: true
# frozen_string_literal: true

require "test_helper"

class CacheHeaderSetterTest < GitHub::TestCase
  class ExampleSinatraApp
    attr_accessor :headers, :env, :current_user
    def initialize(headers = {}, env = {})
      @headers, @env = headers, env
    end
  end

  def sinatra_app
    @sinatra_app ||= ExampleSinatraApp.new
  end

  def headers(options = {})
    Api::App::CachingHelpers::CacheHeaderSetter.new(
      sinatra_app, options
    )
  end

  test "it can also set the vary header for unauthenticated and authenticated requests" do
    sinatra_app.current_user = false
    headers.set_vary_header
    assert_equal "Accept", sinatra_app.headers["Vary"]

    sinatra_app.current_user = true
    headers.set_vary_header
    assert_equal "Accept, Authorization, Cookie, X-GitHub-OTP", sinatra_app.headers["Vary"]
  end

  test "should set cache control public on regular requests" do
    assert_equal "public", headers.cache_control_headers.first
  end

  test "should set cache control private on authenticated requests" do
    sinatra_app.current_user = true

    assert_equal "private", headers.cache_control_headers.first
  end

  test "should set the cache control max age to the default" do
    assert_equal "60", headers.cache_control_headers.last["max-age"].to_s
  end

  test "should set the cache control max age to the given value" do
    @headers = headers(max_age: 120)
    assert_equal "120", @headers.cache_control_headers.last["max-age"].to_s
  end

  test "should set the Vary header by default" do
    assert_equal ["Accept"], headers.vary_headers
  end

  test "should vary on authorization on authenticated requests" do
    sinatra_app.current_user = true

    assert headers.vary_headers.include?("Authorization")
    assert headers.vary_headers.include?("Cookie")
    assert headers.vary_headers.include?("X-GitHub-OTP")
  end

  test "can be manually disabled" do
    headers = headers(skip_caching_headers: true)
    assert headers.skip_caching?
  end

  test "should set last modified" do
    time = Time.parse("2012-06-04 00:00:00")
    @headers = headers(last_modified: time)
    assert_equal time, @headers.last_modified
  end

  test "should not set an etag if only last_modified is provided" do
    time = Time.parse("2012-06-04 00:00:00")
    @headers = headers(last_modified: time)

    assert_nil @headers.etag
  end

  test "should change the etag on a different value for a vary header" do
    body = "response_body"
    sinatra_app.current_user = true

    sinatra_app.env["HTTP_AUTHORIZATION"] = "basic 1"
    @headers = headers(body: body)
    original_etag = @headers.etag

    sinatra_app.env["HTTP_AUTHORIZATION"] = "basic 2"
    @headers = headers(body: body)
    refute_equal original_etag, @headers.etag
  end

  test "should take a custom etag option" do
    @headers = headers(etag: "abc")
    assert_equal "abc", @headers.etag
  end
end
