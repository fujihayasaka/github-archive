# typed: true
# frozen_string_literal: true

class Api::Internal::Codespaces::Webhook < Api::Internal::Codespaces::Hmac
  class MissingCodespaceError < ::Codespaces::Error
  end

  post "/internal/vscs/environment_heartbeat", operation_id: :internal do
    @route_owner = "@github/codespaces"
    update_codespace_from_webhook("codespaces-environment-heartbeat")
  end

  post "/internal/vscs/environment_webhook", operation_id: :internal do
    @route_owner = "@github/codespaces"
    update_codespace_from_webhook("codespaces-environment-webhook")
  end

  private

  def update_codespace_from_webhook(schema)
    deliver_empty(status: 200) if GitHub.flipper[:disable_codespaces_environment_webhooks].enabled?

    data = receive_with_schema("codespace", schema, expected_type: Hash)
    codespace = Codespace.include_deleted.find_by(name: data["friendlyName"])
    if codespace
      authorize_vscs_target!(codespace.vscs_target&.to_sym)
      ::Codespaces::WebhookJob.perform_later(data)
    end
    deliver_empty(status: 200)
  end
end
