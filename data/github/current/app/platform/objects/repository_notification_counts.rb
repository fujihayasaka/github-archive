# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class RepositoryNotificationCounts < Platform::Objects::Base
      description "Returns the number of outstanding notifications per repository for this user."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, _object)
        permission.hidden_from_public?(self) # Update this authorization if we ever go public with this object
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(_permission, _object)
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      visibility :internal

      field :repository, Objects::Repository, "Reporitory object.", null: false
      field :total_count, Int, "The total number of notifications.", null: false
      field :unread_count, Int, "The total number of unread notifications.", null: false
    end
  end
end
