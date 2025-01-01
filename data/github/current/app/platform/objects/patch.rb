# typed: false
# frozen_string_literal: true

module Platform
  module Objects
    class Patch < Platform::Objects::Base
      description "Represents the changes to an individual file in a diff."

      implements_node templates: [[:rpch, :patch_id]], as: "PCH", ready_date: "1970-01-01", uses_database_id: false do |patch|
        {
          prefix: :rpch,
          patch_id: patch.id
        }
      end

      def initialize(*)
        super
        @context.scoped_merge!(root_commit_arguments: { oid: @object.diff.diff&.sha2 })
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        repo = object.diff.repo

        permission.async_owner_if_org(repo).then do |org|
          permission.access_allowed?(
            :get_diff,
            resource: repo,
            current_org: org,
            current_repo: repo,
            allow_integrations: true,
            allow_user_via_granular_actor: true,
          )
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.typed_can_see?("Diff", object.diff)
      end

      def self.load_from_next_global_id(parsed_id)
        load_from_global_id(parsed_id.parts[:patch_id])
      end

      def self.load_from_global_id(id)
        Platform::Models::Patch.load_from_global_id(id)
      end

      mobile_only true

      minimum_accepted_scopes ["repo"]

      field :path, String, "The path of this changed file", null: false, visibility: :internal

      field :path_ownership, Objects::PathOwnership, null: false, description: "The owners for the patch's file path.", visibility: :internal

      field :oid, String, "The blob oid of the new file (or the old one if this is a deletion)", null: false, visibility: :internal

      field :path_digest, String, "The hashed path of the changed file", null: false, visibility: :internal

      field :lines_added, Integer, "The number of lines added in this patch.", method: :additions, null: false

      field :lines_deleted, Integer, "The number of lines removed in this patch.", method: :deletions, null: false

      field :lines_changed, Integer, "The total lines added or removed in this patch.", method: :changes, null: false

      field :viewer_viewed_state, Enums::FileViewedState, description: "Whether the authenticated viewer has viewed this file in the given Pull Request", null: true, visibility: :internal do
        argument :pull_request_id, ID, description: "the ID of the PullRequest", required: true
      end

      def viewer_viewed_state(pull_request_id:)
        Helpers::NodeIdentification.async_typed_object_from_id([::Platform::Objects::PullRequest], pull_request_id, context).then do |pull_request|
          if pull_request
            user_reviewed_files = pull_request.user_reviewed_files_for(@context[:viewer])
            if user_reviewed_files.reviewed?(object.path)
              :viewed
            elsif user_reviewed_files.dismissed?(object.path)
              :dismissed
            else
              :unviewed
            end
          end
        end
      end

      field :new_tree_entry, Objects::TreeEntry, "The tree entry after the change.", null: true

      field :old_tree_entry, Objects::TreeEntry, "The tree entry before the change.", null: true

      field :similarity, Integer, "The percent similarity in the case of a rename.", visibility: :internal, null: true

      field :status, Enums::PatchStatus, "Identifies the status of the patch.", null: false

      field :text, String, "The textual diff of this patch.", null: true

      field :unicode_text, String, "The textual diff of this patch in Unicode.", visibility: :internal, null: true

      field :diff_lines, [Objects::DiffLine, null: true], description: "The diff lines for this patch.", null: true do
        argument :syntax_highlighting_enabled, Boolean, default_value: true, description: "Indicates whether diff lines should be syntax highlighted.", required: false
        argument :injected_context_lines, [Inputs::DiffLineRange], description: "The list of line ranges for injected contexts added to the diff lines. The ranges can overlap and are not required to be sorted.", required: false
      end

      def diff_lines(**arguments)
        @object.async_diff_lines \
          syntax_highlighted_diffs_enabled: arguments[:syntax_highlighting_enabled],
          injected_context_lines: arguments[:injected_context_lines]
      end

      field :is_submodule, Boolean, null: false, method: :submodule?, description: "Whether or not the patch is in a submodule"
      field :is_binary, Boolean, null: false, method: :binary?, description: "Whether or not the patch is binary"
      field :is_large_diff, Boolean, null: false, method: :is_large_diff?, description: "Whether or not the patch is a large diff"
      field :is_too_big, Boolean, null: false, method: :too_big?, description: "Whether or not the patch's diff contents were skipped due to size", visibility: :internal
      field :is_lfs_pointer, Boolean, null: false, method: :lfs_pointer?, description: "Whether or not the patch contains LFS pointers", visibility: :internal

      field :blob_url, Scalars::URI, null: false, visibility: :internal, description: "The HTML blob patch URL."
      field :raw_url, Scalars::URI, null: false, visibility: :internal, description: "The HTML raw patch URL."
      field :contents_url, Scalars::URI, null: false, visibility: :internal, description: "The contents API URL."

      field :truncated_reason, String, null: true, visibility: :internal, description: "The reason why the patch was truncated.", method: :truncated_reason
    end
  end
end
