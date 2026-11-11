# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class NewsiesThreadSubscription < Platform::Loader
      def self.load(user_id, thread)
        self.for(user_id).load(thread)
      end

      def initialize(user_id)
        @user_id = user_id
      end

      def fetch(threads)
        response = GitHub.newsies.user_thread_subscriptions(@user_id, threads)
        return {} unless response.success?

        subscriptions = response.index_by do |subscription|
          [
            ::Newsies::List.new(subscription.list_type, subscription.list_id).key,
            subscription.thread_key,
          ]
        end

        threads.each_with_object({}) do |thread, results|
          results[thread] = subscriptions[[thread.list.key, thread.key]]
        end
      end
    end
  end
end
