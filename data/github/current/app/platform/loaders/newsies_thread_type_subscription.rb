# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class NewsiesThreadTypeSubscription < Platform::Loader
      def self.load(user_id, thread)
        self.for(user_id).load(thread)
      end

      def initialize(user_id)
        @user_id = user_id
      end

      def fetch(threads)
        response = GitHub.newsies.user_thread_type_subscriptions(@user_id, threads)
        return {} unless response.success?

        subscriptions = response.value.index_by do |subscription|
          [
            ::Newsies::List.new(subscription.list_type, subscription.list_id).key,
            subscription.thread_type,
          ]
        end

        threads.each_with_object({}) do |thread, results|
          results[thread] = subscriptions[[thread.list.key, thread.subscription_type.to_s]]
        end
      end
    end
  end
end
