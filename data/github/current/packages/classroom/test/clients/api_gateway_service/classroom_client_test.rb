# typed: true
# frozen_string_literal: true

require "test_helper"

class ApiGatewayService::ClassroomClientTest < GitHub::TestCase
  context "GET /api/classrooms" do
    test "forwards params and headers with request for classrooms" do
      stub_request(
        :get,
        "#{GitHub.classroom_api_service_url}/api/classrooms?per_page=100"
      ).with(headers: { "X-Header" => "value" }).to_return(status: 200)

      client = ApiGatewayService::ClassroomClient.new
      response =
        client.classrooms(
          headers: {
            "X-Header" => "value"
          },
          params: {
            per_page: 100
          }
        )

      assert_equal response.status, 200
    end

    test "raises a connection exception if connection is refused" do
      stub_request(
        :get,
        "#{GitHub.classroom_api_service_url}/api/classrooms"
      ).to_raise(Faraday::ConnectionFailed)

      client = ApiGatewayService::ClassroomClient.new
      assert_raises(ApiGatewayService::ClassroomClient::ConnectionFailed) do
        client.classrooms
      end
    end

    test "raised a timeout exception if connection times out" do
      stub_request(
        :get,
        "#{GitHub.classroom_api_service_url}/api/classrooms"
      ).to_raise(Faraday::TimeoutError)

      client = ApiGatewayService::ClassroomClient.new
      assert_raises(ApiGatewayService::ClassroomClient::RequestTimedout) do
        client.classrooms
      end
    end

    test "raises generic error for other exceptions" do
      stub_request(
        :get,
        "#{GitHub.classroom_api_service_url}/api/classrooms"
      ).to_raise(Faraday::Error)

      client = ApiGatewayService::ClassroomClient.new
      assert_raises(ApiGatewayService::ClassroomClient::ClassroomApiError) do
        client.classrooms
      end
    end
  end

  context "GET /api/classrooms/:id" do
    test "forwards params and headers with request for a classroom" do
      stub_request(
        :get,
        "#{GitHub.classroom_api_service_url}/api/classrooms/1?per_page=100"
      ).with(headers: { "X-Header" => "value" }).to_return(status: 200)

      client = ApiGatewayService::ClassroomClient.new
      response =
        client.classroom(
          1,
          headers: {
            "X-Header" => "value"
          },
          params: {
            per_page: 100
          }
        )

      assert_equal response.status, 200
    end
  end

  context "GET /api/classrooms/:id/assignments" do
    test "forwards params and headers with request for assignments" do
      stub_request(
        :get,
        "#{GitHub.classroom_api_service_url}/api/classrooms/1/assignments?per_page=100"
      ).with(headers: { "X-Header" => "value" }).to_return(status: 200)

      client = ApiGatewayService::ClassroomClient.new
      response =
        client.assignments(
          1,
          headers: {
            "X-Header" => "value"
          },
          params: {
            per_page: 100
          }
        )

      assert_equal response.status, 200
    end
  end

  context "GET /api/assignments/:id" do
    test "forwards params and headers with request for an assignment" do
      stub_request(
        :get,
        "#{GitHub.classroom_api_service_url}/api/assignments/1?per_page=100"
      ).with(headers: { "X-Header" => "value" }).to_return(status: 200)

      client = ApiGatewayService::ClassroomClient.new
      response =
        client.assignment(
          1,
          headers: {
            "X-Header" => "value"
          },
          params: {
            per_page: 100
          }
        )

      assert_equal response.status, 200
    end
  end

  context "GET /api/assignments/:id/accepted_assignments" do
    test "forwards params and headers with request for accepted_assignments" do
      stub_request(
        :get,
        "#{GitHub.classroom_api_service_url}/api/assignments/1/accepted_assignments?per_page=100"
      ).with(headers: { "X-Header" => "value" }).to_return(status: 200)

      client = ApiGatewayService::ClassroomClient.new
      response =
        client.accepted_assignments(
          1,
          headers: {
            "X-Header" => "value"
          },
          params: {
            per_page: 100
          }
        )

      assert_equal response.status, 200
    end
  end

  context "GET /api/assignments/:id/grades" do
    test "forwards params and headers with request for grades" do
      stub_request(
        :get,
        "#{GitHub.classroom_api_service_url}/api/assignments/1/grades?per_page=100"
      ).with(headers: { "X-Header" => "value" }).to_return(status: 200)

      client = ApiGatewayService::ClassroomClient.new
      response =
        client.assignment_grades(
          1,
          headers: {
            "X-Header" => "value"
          },
          params: {
            per_page: 100
          }
        )

      assert_equal response.status, 200
    end
  end
end
