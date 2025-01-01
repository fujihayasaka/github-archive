# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class RepositoryStafftoolsInfo < Platform::Objects::Base
      description "Repository information only visible to site admins"

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, _object)
        # TODO write proper permissions before making this object public
        permission.hidden_from_public?(self)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        Platform::Objects::Base::SiteAdminCheck.viewer_is_site_admin?(permission.viewer, self.class.name)
      end

      visibility :internal

      minimum_accepted_scopes ["site_admin"]

      field :network_lfs_disk_usage, Integer, description: "The amount in bytes of LFS storage used by this repository's network.", null: false

      def network_lfs_disk_usage
        Loaders::NetworkLfsDiskUsage.load(@object.repo.network_id)
      end

      field :interaction_ability, Objects::RepositoryInteractionAbility, "The interaction ability settings for this repository.", null: false

      def interaction_ability
        Platform::Models::RepositoryInteractionAbility.new(@object.repo)
      end

      field :has_workflows, Boolean, description: "Does this repo have any workflows.", null: false, visibility: :internal

      def has_workflows
        @object.repo.workflows.any?
      end

      field :tree_list, [String], description: "Result of repo tree search", null: false, visibility: :internal do
        argument :tree_oid, String, description: "OID of tree to search", required: true
      end

      def tree_list(tree_oid:)
        Platform::Loaders::GitTreeFileList.load(@object.repo, tree_oid)
      end

      field :access_disabled, Boolean, description: "Access to this repository has been disabled. ex. tos violation", null: false, visibility: :internal

      def access_disabled
        @object.repo.access.disabled?
      end

      field :pages_branch_tree_oid, Scalars::GitObjectID, description: "The git tree object ID corresponding to the currently deployed pages branch.", null: true

      def pages_branch_tree_oid
        repo = @object.repo
        Platform::Loaders::ActiveRecord.load(::Page, repo.id, column: :repository_id).then do |page|
          begin
            page ? repo.tree_entry(repo.ref_to_sha(page.source_branch), "").oid : nil
          rescue GitRPC::InvalidFullOid # Page isn't set up yet
            nil
          end
        end
      end

      field :content_warning,
        Objects::ContentWarning,
        description: "Content warning displayed when repository is viewed.",
        null: true

      def content_warning
        @object.repo.content_warning
      end

      field :high_profile, Objects::HighProfile, description: "If a repository meets Trust & Safety high profile criteria", null: true
      def high_profile
        is_high_profile, high_profile_reason = HighProfileSignals.high_profile_repo?(@object.repo)
        return nil unless is_high_profile

        {
          is_high_profile: is_high_profile,
          reason: high_profile_reason
        }
      end
    end
  end
end
