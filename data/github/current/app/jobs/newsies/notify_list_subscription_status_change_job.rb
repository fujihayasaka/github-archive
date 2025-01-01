# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

module Newsies
  class NotifyListSubscriptionStatusChangeJob < ApplicationJob
    queue_as :notify_subscription_status_change
    retry_on_dirty_exit

    def perform(user_id, list_type, list_id)
      return unless user = User.find_by(id: user_id)
      return unless list = list_type.constantize.find_by(id: list_id)

      channel = GitHub.tracer.in_span("fetch_web_socket_list_subscription_channel", kind: :internal, attributes: { "gh.user.id" => user.id }) do
        GitHub::WebSocket::Channels.list_subscription(user, list)
      end

      GitHub.tracer.in_span("notify_user_channel", kind: :internal, attributes: { "gh.user.id" => user.id }) do
        data = { timestamp: Time.now.to_i }
        GitHub::WebSocket.notify_user_channel(user, channel, data)
      end
    end
  end
end
