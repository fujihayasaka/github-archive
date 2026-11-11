# typed: true
# frozen_string_literal: true

module Platform
  module Connections
    class PullRequestCommit < Connections::Base
      total_count_field

      def total_count
        pull_request = @object.parent
        pull_request.async_total_commits
      end

      field :has_limit_exceeded, Boolean, visibility: :internal, description: "Identifies whether the number of commits exceeds the limit.", null: false

      def has_limit_exceeded
        pull_request = @object.parent
        pull_request.async_changed_commits.then do
          pull_request.commit_limit_exceeded?
        end
      end
    end
  end
end
