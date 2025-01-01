# typed: strict
# frozen_string_literal: true

# These are GlobalInstrumenter subscriptions that emit Hydro events related to GitHub Runtime deployments.
Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("runtime.deployment.scan_requested") do |payload|

    message = {
      request_context: serializer.request_context(GitHub.context.to_hash),
      actor: serializer.user(payload[:actor]),
      upload_ip: serializer.ip_address(payload[:upload_ip]),
      image_model: serializer.spark_deployment_payload(payload)
    }

    publish(message, schema: "github.trust_safety.v0.ImageScan")
  end
end
