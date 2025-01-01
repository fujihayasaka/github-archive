# typed: true
# frozen_string_literal: true

class Api::Runtime::Telemetry < Api::Runtime::SdkBase
  post "/runtime/:app/loaded", operation_id: :internal, read_from_replicas: true do
    @route_owner = "@github/copilot-workbench"

    runtime_app = find_runtime_app!

    control_access :runtime_write_loaded,
      resource: current_user,
      app: runtime_app,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    workbench = Spark::Workbench.find_by(runtime_app: runtime_app)

    telemetry_params = receive(Hash, required: true)

    payload = Workbench::TelemetryInstrumenter::Payload.from_api(
      restricted: false,
      current_user: current_user,
      event_type: "spark.spark_load",
      request_id:,
      session_id: GitHub.context[:actor_session].to_s,
      spark_id: workbench&.uuid_string || "",
      context: {
        environment: environment_from_url(telemetry_params["url"]),
        owner_id: runtime_app.runtime_app_owner.owner_id,
        runtime_permanent_name: runtime_app.permanent_name,
        url: telemetry_params["url"],
      },
      timestamp: Time.now,
    )

    GlobalInstrumenter.instrument(Workbench::Events::GENERIC, payload)

    deliver_empty
  end

  def environment_from_url(url)
    begin
      uri = URI.parse(url)
      return "production" if uri.host&.ends_with?("github.app")
      return "development" if uri.host&.ends_with?("github.dev")
    rescue URI::InvalidURIError
      # whatever bro
    end

    "unknown"
  end
end
