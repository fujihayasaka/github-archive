# typed: strict
# frozen_string_literal: true

# These are GlobalInstrumenter subscriptions that emit Hydro events related to GitHub Copilot Chat Attachments.
Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("copilot.chat_attachment.scan_requested") do |payload|
    attachment = payload[:attachment]

    message = {
      request_context: serializer.request_context(GitHub.context.to_hash),
      actor: serializer.user(attachment.uploader),
      upload_ip: serializer.ip_address(payload[:upload_ip]),
      image_model: serializer.image_attachment(attachment),
    }

    publish(message, schema: "github.trust_safety.v0.ImageScan")
  end
end
