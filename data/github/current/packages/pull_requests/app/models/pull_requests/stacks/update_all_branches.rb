# typed: strict
# frozen_string_literal: true

module PullRequests
  module Stacks
    module UpdateAllBranches
      sig do
        params(
          stack: PullRequests::Stack,
          actor: User,
          expected_head_oid_by_pr_number: T::Hash[Integer, String],
          start_pull_request: T.nilable(PullRequest),
        ).returns(Service::Result)
      end
      def self.execute(stack:, actor:, expected_head_oid_by_pr_number:, start_pull_request: nil)
        Service.new(stack:, actor:, expected_head_oid_by_pr_number:, start_pull_request:).call
      end
    end
  end
end
