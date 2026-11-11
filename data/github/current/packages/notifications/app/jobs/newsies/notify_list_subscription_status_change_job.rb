# typed: true
# frozen_string_literal: true

module Newsies
  # Sends a real-time WebSocket push to a user when their subscription status changes on
  # a list (repository or team). Fetches the WebSocket channel for the user/list pair and
  # pushes a timestamped update.
  #
  # Enqueued by: Newsies::Service (lib/newsies/service.rb) when a user subscribes to or
  # unsubscribes from list-level notifications (e.g., watching/unwatching a repository).
  class NotifyListSubscriptionStatusChangeJob < ApplicationJob
    queue_as :notify_subscription_status_change
    retry_on_dirty_exit

    use_replicas ApplicationRecord::Mysql1,
      ApplicationRecord::Repositories

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
