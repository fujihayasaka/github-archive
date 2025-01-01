# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class AllowablePullRequestMergeMethod < Platform::Objects::Base
      visibility :internal
      model_name "PullRequest::AllowableMergeMethod"

      description "Describes a method the user could pick to merge the Pull Request based
      on the Repository's configuration and the user's permissions"

      field :name, Enums::PullRequestMergeMethod, null: false, description: "The name of the merge method. Only squash, rebase, and merge apply."
      field :is_allowable, Boolean, null: false, description: "Whether the viewer is allowed to use this method to merge the pull request"
      field :is_allowable_with_bypass, Boolean, null: false, description: "Whether the viewer is allowed to use this method to merge the pull request by bypassing the required checks"
      field :is_default, Boolean, null: false, description: "Whether this is the default merge method for the repository"

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      sig { params(permission: Platform::Authorization::Permission, _object: ::PullRequest::AllowableMergeMethod).returns(T::Boolean) }
      def self.async_api_can_access?(permission, _object)
        # This field is currently internal, but eventually we'll
        # check if the user can view the PR.
        permission.hidden_from_public?(self)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        # This object is currently internal, but eventually we'll
        # check if the user can view the PR.
        permission.hidden_from_public?(self)
      end
    end
  end
end
