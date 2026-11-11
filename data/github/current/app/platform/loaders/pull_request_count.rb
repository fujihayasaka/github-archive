# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class PullRequestCount < Platform::Loader
      def self.load(user)
        self.for.load(user.id)
      end

      def fetch(user_ids)
        result = ::PullRequest.for_user(user_ids)
                            .group("`pull_requests`.`user_id`").count

        user_ids.each_with_object(result) do |user_id, result|
          result[user_id] ||= 0
        end
      end
    end
  end
end
