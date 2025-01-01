# typed: true
# frozen_string_literal: true

# from https://github.com/github/pull-requests/discussions/8474?sort=new#discussioncomment-6815511

module Platform
  module Objects
    class AllowablePullRequestMergeAction < Platform::Objects::Base
      extend T::Sig
      visibility :internal
      model_name "PullRequest::AllowableMergeAction"

      description <<~DESC
        Describes a mechanism the user could pick to merge the Pull Request based
        on the Repository's configuration and the user's permissions.

        It does not take mergeability into account.
      DESC

      field :name, Enums::PullRequestMergeAction, null: false, description: <<~DESC
        The name of the merge action. Only direct merge and merge queue apply.
      DESC

      field :merge_methods, [Platform::Objects::AllowablePullRequestMergeMethod], null: false, description: <<~DESC
        The merge method that will be used if the user picks this action.
      DESC

      field :is_allowable, Boolean, null: false, description: <<~DESC
        Whether the viewer is allowed to use this action to merge the pull request
      DESC

      field :is_allowable_with_bypass, Boolean, null: false, description: <<~DESC
        Whether the viewer is allowed to use this action to merge the pull request by bypassing the required checks
      DESC

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      sig { params(permission: Platform::Authorization::Permission, _object: ::PullRequest::AllowableMergeAction).returns(T::Boolean) }
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
