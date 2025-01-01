# typed: true
# frozen_string_literal: true

require "test_helper"

module Repositories
  class ExperimentResponseHydroPublisherTest < GitHub::TestCase
    include HydroTestHelpers

    class MockRequest
      attr_accessor :env, :request_method, :path, :query_string
    end

    class MockResponse
      attr_accessor :status, :headers, :body
    end

    setup do
      @route = "/test/route"

      @request = MockRequest.new
      @request.env = { "HTTP_X_GITHUB_REQUEST_ID" => "test-request-id", "HTTP_USER_AGENT" => "test-agent" }
      @request.request_method = "GET"
      @request.path = "/test/path"
      @request.query_string = "param=value"

      @response = MockResponse.new
      @response.status = 200
      @response.headers = { "Content-Type" => "application/json" }
      @response.body = ["{\"key\":\"value\"}"]
    end

    test ".publish" do
      GitHub.context.push(actor_ip: "1.1.1.1")

      expected_message = {
        request_id: "test-request-id",
        method: "GET",
        route: @route,
        path: "/test/path",
        query: "param=value",
        request_headers: { "HTTP_X_GITHUB_REQUEST_ID" => "test-request-id", "HTTP_USER_AGENT" => "test-agent" },
        response_code: 200,
        response_headers: { "Content-Type" => "application/json" },
        response_body_hash: Digest::SHA256.base64digest("{\"key\":\"value\"}"),
      }

      ExperimentResponseHydroPublisher.publish(route: @route, request: @request, response: @response)

      with_hydro_publisher(GitHub.hydro_request_analytics_publisher) do
        assert_hydro_published(expected_message, schema: "github.v1.ExperimentResponse", topic: "github.repos.contents.v1.ExperimentResponse")
      end
    end
  end
end
