# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class OnBehalfOfReviewer < Platform::Objects::Base
      description "An object that describes reviewers a review was made on behalf of."
      visibility :internal

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, prr)
        permission.hidden_from_public?(self)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.hidden_from_public?(self)
      end

      field :as_codeowner, Boolean, description: "Whether this request was created for a code owner", null: false

      def as_codeowner
        @object[:as_codeowner]
      end

      field :reviewer, Unions::RequestedReviewer, description: "The reviewer that is requested.", null: true

      def reviewer
        @object[:reviewer]
      end
    end
  end
end
