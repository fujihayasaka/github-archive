# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class CreatedIssueContribution < Objects::Base

      scopeless_tokens_as_minimum

      implements Interfaces::Contribution

      description "Represents the contribution a user made on GitHub by opening an issue."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, contrib)
        permission.typed_can_access?("Issue", contrib.issue)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.typed_can_see?("Issue", object.issue)
      end

      field :issue, Issue, null: false, description: "The issue that was opened."
    end
  end
end
