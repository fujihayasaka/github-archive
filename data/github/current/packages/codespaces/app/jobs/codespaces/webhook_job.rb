# typed: true
# frozen_string_literal: true

class Codespaces::WebhookJob < CodespacesJob
  retry_on GitRPC::Error
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  def perform(data)
    with_write do
      Codespaces::ProcessWebhook.call(data)
    end
  end
end
