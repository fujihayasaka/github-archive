# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class NotifySubscriptionStatusChangeJob < ApplicationJob
  include ActiveJob::InitiallyEnqueuedAt

  set_max_redelivery_attempts 0
  queue_as  :notify_subscription_status_change
  retry_on_dirty_exit

  resolve_tenant_context do |_, list_id, _, _, list_type|
    Notifications::TenantContext.resolve_tenant_for_list(list_type: list_type || "Repository", list_id: list_id)
  end

  def perform(user_id, list_id, thread_id, data = {}, list_type = "Repository")
    data = { timestamp: initially_enqueued_at.to_i }.merge(data)

    return unless user = User.find_by(id: user_id)
    return unless list = list_type.constantize.find_by_id(list_id)

    channel = GitHub.tracer.in_span("fetch_channels_thread_subscription", kind: :internal) do
      GitHub::WebSocket::Channels.thread_subscription(user, list, thread_id)
    end

    GitHub.tracer.in_span("notify_user_channel_via_web_socket", kind: :internal) do
      GitHub::WebSocket.notify_user_channel(user, channel, data)
    end
  end
end
