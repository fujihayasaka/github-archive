# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class IssueContributionsByRepository < Platform::Objects::Base
      description "This aggregates issues opened by a user within one repository."

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

      field :repository, Repository, description: "The repository in which the issues were opened.",
        null: false

      field :contributions, Connections.define(Objects::CreatedIssueContribution),
        description: "The issue contributions.", null: false do
        argument :order_by, Inputs::ContributionOrder,
          "Ordering options for contributions returned from the connection.",
          required: false, default_value: { direction: "DESC" }
      end

      def contributions(order_by: nil)
        result = @object.contributions(order_by: order_by)
        ArrayWrapper.new(result)
      end

      field :contributions_by_state, [IssueContributionsByState],
        description: "A list of data about issue contributions based on the issue's state.",
        null: false
    end
  end
end
