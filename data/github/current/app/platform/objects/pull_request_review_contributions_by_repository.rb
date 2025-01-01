# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class PullRequestReviewContributionsByRepository < Platform::Objects::Base
      description "This aggregates pull request reviews made by a user within one repository."

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
        description: "The repository in which the pull request reviews were made.", null: false

      field :contributions, Connections.define(Objects::CreatedPullRequestReviewContribution),
        description: "The pull request review contributions.", null: false do
        argument :order_by, Inputs::ContributionOrder,
          "Ordering options for contributions returned from the connection.",
          required: false, default_value: { direction: "DESC" }
      end

      def contributions(order_by: nil)
        result = @object.contributions(order_by: order_by)
        ArrayWrapper.new(result)
      end
    end
  end
end
