# typed: true
# frozen_string_literal: true

class DeployKeyDeletedWebhookJob < ApplicationJob
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  queue_as :deploy_key_delete_webhook

  def perform(key_id:, repository_id:, actor_id:, async_event_context:)
    with_write do
      event = Hook::Event::DeployKeyEvent.new(
        action: :deleted,
        key_id: key_id,
        repository_id: repository_id,
        actor_id: actor_id,
        async_event_context: async_event_context,
        triggered_at: Time.now
      )

      delivery_system = Hook::DeliverySystem.new(event)
      delivery_system.generate_hookshot_payloads
      delivery_system.deliver_later
    end
  end
end
