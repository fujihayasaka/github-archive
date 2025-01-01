# typed: true
# frozen_string_literal: true

require "test_helper"

class ApiMiddlewareRouteFinderTest < GitHub::TestCase
  test "sets the github.api.route on the env" do
    app = Api::Licenses.new!
    app.stubs(:call)

    env = { "REQUEST_METHOD" => "GET", "PATH_INFO" => "/licenses/mit" }
    middleware = Api::Middleware::RouteFinder.new(app)
    middleware.call(env)
    assert_equal "GET /licenses/:key", env["github.api.route"]
  end

  context "doesn't error trying to find the route" do
    test "when the route doesn't exist on the controller" do
      app = Api::Licenses.new!
      expected_result = "test"
      app.stubs(call: expected_result)

      env = { "REQUEST_METHOD" => "GET", "PATH_INFO" => "/emojis" }
      middleware = Api::Middleware::RouteFinder.new(app)
      results = middleware.call(env)
      assert_equal expected_result, results
      refute env.has_key?("github.api.route")
    end

    test "when the request method doesn't exist on the controller" do
      app = Api::Licenses.new!
      expected_result = "test"
      app.stubs(call: expected_result)

      env = { "REQUEST_METHOD" => "POST", "PATH_INFO" => "/licenses/mit" }
      middleware = Api::Middleware::RouteFinder.new(app)
      results = middleware.call(env)
      assert_equal expected_result, results
      refute env.has_key?("github.api.route")
    end

    test "when the controller has no routes" do
      app = Api::App.new!
      expected_result = "test"
      app.stubs(call: expected_result)

      env = { "REQUEST_METHOD" => "GET", "PATH_INFO" => "/licenses/mit" }
      middleware = Api::Middleware::RouteFinder.new(app)
      results = middleware.call(env)
      assert_equal expected_result, results
      refute env.has_key?("github.api.route")
    end
  end
end
