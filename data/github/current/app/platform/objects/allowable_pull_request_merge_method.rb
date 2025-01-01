# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class AllowablePullRequestMergeMethod < Platform::Objects::Base
      required_capabilities [:mobile_only_schema_mask]
      model_name "PullRequest::AllowableMergeMethod"

      description "Describes a method the user could pick to merge the Pull Request based
      on the Repository's configuration and the user's permissions"

      field :name, Enums::PullRequestMergeMethod, null: false, description: "The name of the merge method. Only squash, rebase, and merge apply."
      field :allowable_status, Enums::PullRequestMergeMethodStatus, null: false, description: <<~DESC
        The viewer's ability to use this method to merge the pull request
      DESC
      field :is_default, Boolean, null: false, description: "Whether this is the default merge method for the repository"

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      sig { params(permission: Platform::Authorization::Permission, allowable_merge_method: ::PullRequest::AllowableMergeMethod).returns(T::Boolean) }
      def self.async_api_can_access?(permission, allowable_merge_method)
        # Resource access is controlled by the pull request
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        # Resource access is controlled by the pull request
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end
    end
  end
end
