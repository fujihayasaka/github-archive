# typed: strict
# frozen_string_literal: true

module PullRequests
  module Stacks
    class UpdateAllBranchesJob < ApplicationJob
      queue_as :pull_requests_stacks_update_all_branches

      use_primaries ApplicationRecord::IssuesPullRequests

      retry_on_dirty_exit

      sig do
        params(
          start_pull_request: ::PullRequest,
          actor: ::User,
          expected_head_oid_by_pr_number: T::Hash[String, String],
        ).void
      end
      def perform(start_pull_request:, actor:, expected_head_oid_by_pr_number:)
        stack = start_pull_request.stack
        return if stack.nil?

        PullRequests::Observability::Git.tag(repository: start_pull_request.repository, feature: :update_all_branches_stack) do
          Stacks.lock!(stack, ttl: 2.minutes) do
            Stacks.update_all_branches_now(
              start_pull_request:,
              actor:,
              expected_head_oid_by_pr_number:,
            )
          end
        end
      end
    end
  end
end
