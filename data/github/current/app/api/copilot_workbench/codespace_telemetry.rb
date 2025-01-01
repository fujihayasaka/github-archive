# typed: true
# frozen_string_literal: true

class Api::CopilotWorkbench::CodespaceTelemetry < Api::App
  include FeatureFlagHelper

  before do
    deliver_error!(404) unless current_user&.feature_enabled?(:copilot_workbench)
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

    payload = Workbench::TelemetryInstrumenter::Payload.from_api(
      restricted: event["restricted"],
      current_user:,
      event_type:,
      request_id:,
      session_id: GitHub.context[:actor_session].to_s,
      spark_id: workbench.uuid_string,
      event_data: event["event_data"] || {},
      timestamp: event["event_time"] ? Time.parse(event["event_time"]) : nil
    )


    Workbench::TelemetryInstrumenter.instrument(payload)

    deliver_raw("", status: :created)
  end
end
