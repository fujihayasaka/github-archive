# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class PullRequestContributionsByRepository < Platform::Objects::Base
      description "This aggregates pull requests opened by a user within one repository."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, obj)
        permission.typed_can_access?("Repository", obj.repository)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.typed_can_see?("Repository", object.repository)
      end


      scopeless_tokens_as_minimum

      field :repository, Repository,
        description: "The repository in which the pull requests were opened.", null: false

      field :contributions, Connections.define(Objects::CreatedPullRequestContribution),
        description: "The pull request contributions.", null: false do
        argument :order_by, Inputs::ContributionOrder,
          "Ordering options for contributions returned from the connection.",
          required: false, default_value: { direction: "DESC" }
      end

      def contributions(order_by: nil)
        result = @object.contributions(order_by: order_by)
        ArrayWrapper.new(result)
      end

      field :contributions_by_state, [PullRequestContributionsByState], null: false,
        description: <<~DESCRIPTION
          A list of data about pull request contributions based on the pull request's state.
        DESCRIPTION

      def contributions_by_state
        issue_promises = @object.contributions.map(&:async_issue)
        Promise.all(issue_promises).then { @object.contributions_by_state }
      end
    end
  end
end
