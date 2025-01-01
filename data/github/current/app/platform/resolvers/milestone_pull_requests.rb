# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class MilestonePullRequests < Resolvers::PullRequests
      def fetch_pull_requests(milestone, _, _)
        scope = ::PullRequest
                .select("pull_requests.*, issue_priorities.priority")
                .joins(:issue)
                .joins("LEFT JOIN `issue_priorities` ON `issue_priorities`.`issue_id` = `issues`.`id`")
                .where(issues: { id: milestone.pull_request_issue_ids }) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
                .order("issue_priorities.priority DESC, pull_requests.id ASC")
        repository = milestone.repository
        context[:permission].async_can_list_pull_requests?(repository).then do |can_list_pull_requests|
          filter_scope_by_visibility(scope, repository, can_list_pull_requests)
        end
      end

      def wrap_connection(relation, args)
        if args[:order_by]
          # The order-by using a join table was overridden.
          # The normal connection wrapper will work fine.
          relation
        else
          # Use this custom wrapper to accommodate the `issue_priorities`
          # join table.
          ConnectionWrappers::MilestoneMembersByPriority.new(relation)
        end
      end
    end
  end
end
