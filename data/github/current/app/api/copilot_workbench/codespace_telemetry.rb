# typed: true
# frozen_string_literal: true

class Api::CopilotWorkbench::CodespaceTelemetry < Api::App
  include FeatureFlagHelper

  before do
    deliver_error!(404) unless current_user&.spark_enabled?
  end

  before do
    # This endpoint is only supported from Codespaces, not from deployed Sparks
    checker = Api::Runtime::IntegrationChecker.new(
      current_user,
      current_integration,
      [:codespaces_production])

    return if checker.allowed?

    # Anything else is invalid, so let's error out
    deliver_error! 401, message: "Integration auth is not supported for this endpoint"
  end

  post "/copilot_workbench/:copilot_workbench_id/telemetry", operation_id: :internal do
    @route_owner = "@github/copilot-workbench"

    control_access :copilot_workbench,
      resource: current_user,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    workbench = Spark::Workbench.for_uuid_string(current_user.id, params[:copilot_workbench_id])
    deliver_error!(404, message: "Workbench not found") unless workbench

    telemetry_params = receive(Hash, required: true)
    event = telemetry_params["event"]

    deliver_error!(422, message: "Missing event parameter") unless event
    event_type = event["event_type"]
    deliver_error!(422, message: "Missing event_type parameter") unless event_type
    deliver_error!(422, message: "Missing restricted parameter") unless event.has_key?("restricted")

    is_restricted = event["restricted"] == true
    if is_restricted
      copilot_user = Copilot::User.new(current_user)
      return deliver_raw("", status: :created) unless copilot_user.telemetry_enabled?
    end

    payload = Workbench::TelemetryInstrumenter::Payload.from_api(
      restricted: event["restricted"],
      current_user:,
      event_type:,
      request_id:,
      session_id: GitHub.context[:actor_session].to_s,
      spark_id: workbench.uuid_string,
      context: event["context"] || event["event_data"] || {}, # To avoid breaking clients, allow event_data or context
      timestamp: event["event_time"] ? Time.parse(event["event_time"]) : nil
    )

    Workbench::TelemetryInstrumenter.instrument(payload)

    # Log rate limit events to database when status 429 is detected
    log_rate_limit_event(payload)

    deliver_raw("", status: :created)
  end

  private

  def log_rate_limit_event(payload)
    return unless payload.event_type == "spark-agent.model.finished"
    error_info = payload.context["error"]
    return unless error_info && error_info["status"] == 429 && error_info["isUser"] != true

    model = payload.context["model"] || "unknown"

    Spark::ModelRateLimit.create!(
      user_id: current_user.id,
      model: model
    )
  rescue StandardError => e
    # Log the error but don't fail the main telemetry request
    GitHub.logger.error("Failed to log rate limit event from spark agent", e)
  end
end
