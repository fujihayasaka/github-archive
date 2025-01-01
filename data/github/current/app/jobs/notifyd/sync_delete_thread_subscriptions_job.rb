# typed: true
# frozen_string_literal: true

module Notifyd
  class SyncDeleteThreadSubscriptionsJob < ApplicationJob
    queue_as :notifyd_maintenance

    class NotifydThreadSubscriptionDeleteError < StandardError; attr_accessor :msg; end

    DATABASE_UNAVAILABLE_EXCEPTIONS = [
      Freno::Throttler::Error,
      *Resiliency::Response::UnavailableExceptions,
    ].freeze

    NOTIFYD_CLEANUP_EXCEPTIONS = [
      NotifydThreadSubscriptionDeleteError,
    ].freeze

    retry_on(
      *DATABASE_UNAVAILABLE_EXCEPTIONS,
      *NOTIFYD_CLEANUP_EXCEPTIONS,
      wait: :polynomially_longer,
      attempts: 20,
    )

    retry_on_dirty_exit

    def perform(user_id:, subscriptions_to_delete: [])
      return if GitHub.enterprise?

      user = User.find(user_id)
      return if user.nil?

      subscriptions_to_delete.each do |s|
        list_id = s[:list_id]
        list_type = s[:list_type]

        thread_key = s[:thread_key]
        newsies_thread = Newsies::Thread.from_key(thread_key)

        thread_type = newsies_thread.type
        thread_id = newsies_thread.id

        newsies_thread = Newsies::Thread.from_key(thread_key)
        if thread_type == "Grit::Commit"
          list = list_type.constantize.find_by_id(list_id)
          thread = list.commits.find(thread_id) if list
        else
          thread = thread_type.constantize.find_by_id(thread_id)
        end
        next if thread.nil?

        tags = ["thread_type:#{thread_type}", "list_type:#{list_type}"]

        begin
          # Unsubscription will be controlled by unsubscribe_in_notifyd? method
          response = ::Notifications::Subscriptions.notifyd_delete_thread_subscription(user, thread)
          tags = tags << "success: #{response&.value}"

          if !response&.value
            raise NotifydThreadSubscriptionDeleteError.new("Failed to delete thread subscription for user: #{user.id}, thread: #{thread_key}")
          end

          GitHub::Logger.log(
            msg: "Deleted notifyd thread subscription for user: #{user.id}, thread: #{thread_key}, list_id : #{list_id}, list_type: #{list_type}",
            tags: tags,
          )
        rescue => e # rubocop:todo Lint/GenericRescue
          tags = tags << "success: false"
          NotificationsFailbot.report(e, system: "notifyd", catalog_service: "github/notifications")
          GitHub::Logger.log(
            exception: "error: #{e.message}",
            msg: "Failed to delete notifyd thread subscriptions for user: #{user.id}, thread: #{thread_key}, list_id : #{list_id}, list_type: #{list_type}",
            tags: tags,
          )
          raise NotifydThreadSubscriptionDeleteError.new("Failed to delete thread subscription for user: #{user.id}, thread: #{thread_key}")
        ensure
          GitHub.dogstats.increment("notifyd.delete_thread_subscriptions.count", tags: tags)
        end
      end
    end
  end
end
