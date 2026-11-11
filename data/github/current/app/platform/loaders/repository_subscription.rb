# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class RepositorySubscription < Platform::Loader
      def self.load(user_id, repository_id)
        self.for(user_id).load(repository_id)
      end

      def initialize(user_id)
        @user_id = user_id
      end

      def fetch(repository_ids)
        result = Notifications::Subscriptions.user_repository_subscriptions(@user_id, repository_ids)
        return {} if result.nil?

        subscriptions = result.index_by(&:list_id)
        repository_ids.each_with_object({}) do |repository_id, results|
          results[repository_id] = subscriptions[repository_id]
        end
      end
    end
  end
end
