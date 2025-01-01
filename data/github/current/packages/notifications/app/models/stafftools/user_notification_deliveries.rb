# typed: true
# frozen_string_literal: true

module Stafftools
  class UserNotificationDeliveries
    include NewsiesReasons

    attr_reader :user
    attr_reader :first_delivery
    attr_reader :handlers

    delegate :reason, to: :first_delivery

    def self.for_thread(thread_or_comment)
      thread = thread_or_comment.notifications_thread
      list = thread.notifications_list
      comment = thread_or_comment

      newsies_list = ::Newsies::List.to_object(list)
      newsies_thread = ::Newsies::Thread.to_object(thread, list: newsies_list)
      newsies_comment = ::Newsies::Comment.to_object(comment)

      email_and_web_deliveries = ::Newsies::NotificationDelivery.with_utc do
        ::Newsies::NotificationDelivery.where(
          list_id: newsies_list.id,
          thread_key: newsies_thread.key,
          comment_key: newsies_comment.key,
        ).all
      end

      all_deliveries = email_and_web_deliveries

      ::User
        .where(id: all_deliveries.map(&:user_id).uniq)
        .order(login: :asc)
        .map { |user| new(user, all_deliveries.select { |n| n.user_id == user.id }) }
    end

    def initialize(user, deliveries)
      @user = user
      @first_delivery = deliveries.sort_by(&:delivered_at).first
      @handlers = deliveries.map(&:handler).uniq.sort.join(", ")
    end

    def first_delivered_at
      @first_delivery.delivered_at
    end
  end
end
