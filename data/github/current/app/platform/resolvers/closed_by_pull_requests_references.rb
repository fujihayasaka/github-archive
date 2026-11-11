# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class ClosedByPullRequestsReferences < Resolvers::Base
      type Connections.define(Objects::PullRequest), null: true

      argument :include_closed_prs, Boolean, "Include closed PRs in results", required: false, default_value: false
      argument :order_by_state, Boolean, "Return results ordered by state", required: false, default_value: false
      argument :user_linked_only, Boolean, "Return only manually linked PRs", required: false, default_value: false

      def resolve(include_closed_prs: false, order_by_state: false, user_linked_only: false, **arguments)
        @object.async_cap_filtered_closed_by_pull_requests_references_for(
          viewer: @context[:viewer],
          user_linked_only: user_linked_only,
          include_closed_prs: include_closed_prs,
          order_by_state: order_by_state,
          cap_filter: @context[:cap_filter]
        ).then do |accessible_pulls|
          ArrayWrapper.new(accessible_pulls.compact)
        end
      end
    end
  end
end
