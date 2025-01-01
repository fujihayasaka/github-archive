# typed: true
# frozen_string_literal: true

module Platform
  class Subscription
    class MissingData < RuntimeError; end
    DELIMITER = /:/

    def initialize(channel_name:, topic:, arguments:, persisted_query_id:, user_ids:, subscribed_users:)
      @channel_name = channel_name
      @topic = topic
      @arguments = arguments
      @persisted_query_id = persisted_query_id
      @user_ids = user_ids
      @subscribed_users = subscribed_users
    end

    attr_reader :channel_name, :topic, :arguments, :persisted_query_id, :user_ids, :subscribed_users

    def self.current_format
      Formats::V3
    end
  end
end
