
# typed: strict
# frozen_string_literal: true

module Platform
  module Objects
    class IssueCreationPermissions < Platform::Objects::Base
      visibility :internal

      description "Permissions the viewer has when creating a new issue in a repository."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      sig { params(permission: T.untyped, object: T.untyped).returns(T::Boolean) }
      def self.async_api_can_access?(permission, object)
        # This is only called internally as a field in the Repository object
        # and visibility is pre-checked on the Repository object itself.
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      sig { params(permission: T.untyped, object: T.untyped).returns(T::Boolean) }
      def self.async_viewer_can_see?(permission, object)
        # This is only called internally as a field in the Repository object
        # and visibility is pre-checked on the Repository object itself.
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      field :labelable,
        Boolean,
        description: "Whether the viewer can add labels to new issues",
        null: false

      field :assignable,
        Boolean,
        description: "Whether the viewer can assign new issues",
        null: false

      field :milestoneable,
        Boolean,
        description: "Whether the viewer can add milestones to new issues",
        null: false

      field :triageable,
        Boolean,
        description: "Whether the viewer can triage new issues",
        null: false

      field :typeable,
        Boolean,
        description: "Whether the viewer can set the type of a new issue",
        null: false,
        feature_flag: :issue_types
    end
  end
end
