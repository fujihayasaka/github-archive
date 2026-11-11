# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class ContributorOpenPullRequestCount < Platform::Loader
      def self.load(repository, user_id)
        self.for(repository).load(user_id)
      end

      def initialize(repository)
        @repository = repository
      end

      def fetch(user_ids)
        result = @repository.pull_requests.
          includes(:issue).
          joins("INNER JOIN `issues` ON `issues`.`pull_request_id` = `pull_requests`.`id` AND `issues`.`repository_id` = `pull_requests`.`repository_id`").
          where(user_id: user_ids, issues: { state: "open" }).
          group("`pull_requests`.`user_id`").count

        user_ids.each_with_object(result) do |user_id, result|
          result[user_id] ||= 0
        end
      end
    end
  end
end
