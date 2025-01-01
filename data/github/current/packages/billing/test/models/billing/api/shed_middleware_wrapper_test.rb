# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Api::ShedMiddlewareWrapperTest < GitHub::TestCase
  setup do
    @conn = Faraday.new(url: "http://example.invalid") do |c|
      c.options.timeout = 15
      c.use Billing::Api::ShedMiddlewareWrapper

      c.adapter :test do |stub|
        stub.get("/") do |env|
          [200, env.request_headers, ""]
        end
      end
    end
  end

  teardown do
    Shed.clear_timeout
  end

  context "when the feature flag is enabled" do
    test "propagates default timeout via request headers" do
      GitHub.flipper[:billing_api_shed_middleware].enable

      response = @conn.get

      assert_equal 200, response.status
      assert_equal 15, response.env.request.timeout
      assert_equal "15000", response.headers["X-Client-Timeout-Ms"]
    end

    test "propagates contextual timeout via request headers" do
      GitHub.flipper[:billing_api_shed_middleware].enable
      Process.stubs(:clock_gettime).returns(1_000.0)
      Shed.with_timeout(5_000)

      response = @conn.get

      assert_equal 200, response.status
      assert_equal 5, response.env.request.timeout
      assert_equal "5000", response.headers["X-Client-Timeout-Ms"]
    end

    test "raises when contextual deadline is exceeded" do
      GitHub.flipper[:billing_api_shed_middleware].enable
      Process.stubs(:clock_gettime).returns(1_000.0, 1_005.1)
      Shed.with_timeout(5_000)

      assert_raises Shed::Timeout do
        @conn.get
      end
    end
  end

  context "when the feature flag is disabled" do
    test "does not propagate default timeout via request headers" do
      GitHub.flipper[:billing_api_shed_middleware].disable

      response = @conn.get

      assert_equal 200, response.status
      assert_equal 15, response.env.request.timeout
      assert_nil response.headers["X-Client-Timeout-Ms"]
    end

    test "does not propagate contextual timeout via request headers" do
      GitHub.flipper[:billing_api_shed_middleware].disable
      Process.stubs(:clock_gettime).returns(1_000.0)
      Shed.with_timeout(5_000)

      response = @conn.get

      assert_equal 200, response.status
      assert_equal 15, response.env.request.timeout
      assert_nil response.headers["X-Client-Timeout-Ms"]
    end

    test "does not raise when contextual deadline is exceeded" do
      GitHub.flipper[:billing_api_shed_middleware].disable
      Process.stubs(:clock_gettime).returns(1_000.0, 1_005.1)
      Shed.with_timeout(5_000)

      response = @conn.get

      assert_equal 200, response.status
      assert_equal 15, response.env.request.timeout
      assert_nil response.headers["X-Client-Timeout-Ms"]
    end
  end
end
