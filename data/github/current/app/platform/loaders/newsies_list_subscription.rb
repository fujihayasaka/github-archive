# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class NewsiesListSubscription < Platform::Loader
      def self.load(user_id, list)
        self.for(user_id).load(list)
      end

      def initialize(user_id)
        @user_id = user_id
      end

      def fetch(lists)
        response = GitHub.newsies.user_list_subscriptions(@user_id, lists)
        return {} unless response.success?

        subscriptions = response.value.index_by do |subscription|
          ::Newsies::List.new(subscription.list_type, subscription.list_id).key
        end

        lists.each_with_object({}) do |list, results|
          results[list] = subscriptions[list.key]
        end
      end
    end
  end
end
