# typed: true
# frozen_string_literal: true

class Api::Classroom < Api::App
  include ReceiveSchemaWithOpenApi

  before do
    deliver_error! 404 unless GitHub.flipper[:classroom_api_forwarding].enabled?(current_user)
  end

  get "/classrooms", operation_id: "classroom/list-classrooms" do
    control_access :authenticated_user,
      resource: current_user,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    client = ApiGatewayService::ClassroomClient.new

    response = client.classrooms(headers: http_headers, params: params)

    GitHub.logger.info(
      "code.namespace": "Api::Classroom",
      "code.function": "list-classrooms",
      "gh.user.id": current_user.id,
    )

    deliver_raw(response.body, status: response.status)
    rescue ApiGatewayService::ClassroomClient::ClassroomApiError => e
      GitHub.logger.error(
        "exception.message": e.message,
        "code.namespace": "Api::Classroom",
        "code.function": "list-classrooms",
        "gh.user.id": current_user.id,
      )
      deliver_error! 500
  end

  get "/classrooms/:classroom_id", operation_id: "classroom/get-a-classroom" do
    control_access :authenticated_user,
      resource: current_user,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    classroom_id = params.delete(:classroom_id)

    client = ApiGatewayService::ClassroomClient.new
    response =
      client.classroom(
        classroom_id,
        headers: http_headers,
        params: params
      )

    GitHub.logger.info(
      "code.namespace": "Api::Classroom",
      "code.function": "get-a-classroom",
      "gh.user.id": current_user.id,
      "gh.classroom.id": classroom_id,
    )

    deliver_raw(response.body, status: response.status)
    rescue ApiGatewayService::ClassroomClient::ClassroomApiError => e
      GitHub.logger.error(
        "exception.message": e.message,
        "code.namespace": "Api::Classroom",
        "code.function": "get-a-classroom",
        "gh.user.id": current_user.id
      )
      deliver_error! 500
  end

  get "/classrooms/:classroom_id/assignments",
    operation_id: "classroom/list-assignments-for-a-classroom" do
      control_access :authenticated_user,
        resource: current_user,
        challenge: true,
        allow_integrations: false,
        allow_user_via_granular_actor: true

      classroom_id = params.delete("classroom_id")

      client = ApiGatewayService::ClassroomClient.new
      response =
        client.assignments(
          classroom_id,
          headers: http_headers,
          params: params
        )

      GitHub.logger.info(
        "code.namespace": "Api::Classroom",
        "code.function": "list-assignments-for-a-classroom",
        "gh.user.id": current_user.id,
        "gh.classroom.id": classroom_id,
      )

      deliver_raw(response.body, status: response.status)
    rescue ApiGatewayService::ClassroomClient::ClassroomApiError => e
      GitHub.logger.error(
        "exception.message": e.message,
        "code.namespace": "Api::Classroom",
        "code.function": "list-assignments-for-a-classroom",
        "gh.user.id": current_user.id
      )
      deliver_error! 500
    end

  get "/assignments/:assignment_id",
    operation_id: "classroom/get-an-assignment" do
      control_access :authenticated_user,
        resource: current_user,
        challenge: true,
        allow_integrations: false,
        allow_user_via_granular_actor: true

      assignment_id = params.delete("assignment_id")

      client = ApiGatewayService::ClassroomClient.new
      response =
        client.assignment(
          assignment_id,
          headers: http_headers,
          params: params
        )

      GitHub.logger.info(
        "code.namespace": "Api::Classroom",
        "code.function": "get-an-assignment",
        "gh.user.id": current_user.id,
        "gh.classroom.assignment_id": assignment_id,
      )

      deliver_raw(response.body, status: response.status)
    rescue ApiGatewayService::ClassroomClient::ClassroomApiError => e
      GitHub.logger.error(
        "exception.message": e.message,
        "code.namespace": "Api::Classroom",
        "code.function": "get-an-assignment",
        "gh.user.id": current_user.id
      )
      deliver_error! 500
    end

  get "/assignments/:assignment_id/accepted_assignments",
    operation_id: "classroom/list-accepted-assigments-for-an-assignment" do
      control_access :authenticated_user,
        resource: current_user,
        challenge: true,
        allow_integrations: false,
        allow_user_via_granular_actor: true

      assignment_id = params.delete("assignment_id")

      client = ApiGatewayService::ClassroomClient.new

      response =
        client.accepted_assignments(
          assignment_id,
          headers: http_headers,
          params: params
        )

      GitHub.logger.info(
        "code.namespace": "Api::Classroom",
        "code.function": "list-accepted-assigments-for-an-assignment",
        "gh.user.id": current_user.id,
        "gh.classroom.assignment_id": assignment_id,
      )

      deliver_raw(response.body, status: response.status)
    rescue ApiGatewayService::ClassroomClient::ClassroomApiError => e
      GitHub.logger.error(
        "exception.message": e.message,
        "code.namespace": "Api::Classroom",
        "code.function": "list-accepted-assigments-for-an-assignment",
        "gh.user.id": current_user.id
      )
      deliver_error! 500
    end

  get "/assignments/:assignment_id/grades",
    operation_id: "classroom/get-assignment-grades" do
      control_access :authenticated_user,
        resource: current_user,
        challenge: true,
        allow_integrations: false,
        allow_user_via_granular_actor: true

      assignment_id = params.delete("assignment_id")

      client = ApiGatewayService::ClassroomClient.new

      response =
        client.assignment_grades(
          assignment_id,
          headers: http_headers,
          params: params
        )

      GitHub.logger.info(
        "code.namespace": "Api::Classroom",
        "code.function": "get-assignment-grades",
        "gh.user.id": current_user.id,
        "gh.classroom.assignment_id": assignment_id,
      )

      deliver_raw(response.body, status: response.status)
    rescue ApiGatewayService::ClassroomClient::ClassroomApiError => e
      GitHub.logger.error(
        "exception.message": e.message,
        "code.namespace": "Api::Classroom",
        "code.function": "get-assignment-grades",
        "gh.user.id": current_user.id,
        "gh.classroom.assignment_id": assignment_id,
      )
      deliver_error! 500
    end

  private

  def http_headers
    env
      .filter { |k, v| (k.start_with?("HTTP_") && k != "HTTP_HOST" && !v.empty?) }
      .map { |k, v| [k.sub(/\AHTTP_/, ""), v] }
      .map { |k, v| [k.split("_").map(&:capitalize).join("-"), v] }
      .to_h
  end
end
