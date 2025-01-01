# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class IssueContributionsByState < Platform::Objects::Base
      description "This aggregates issue contributions by state."

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

      visibility :under_development

      scopeless_tokens_as_minimum

      field :total_contributions, Integer,
        description: "A count of how many contributions are in this state.", null: false

      field :state, Enums::IssueState, description: "The state the issues are in.", null: false
    end
  end
end
