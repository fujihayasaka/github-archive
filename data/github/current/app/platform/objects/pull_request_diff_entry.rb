# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class PullRequestDiffEntry < Platform::Objects::Base
      description "This is a diff entry object for a pull request comparison"

      implements_node(templates: [[:prde, :pull_request_diff_entry_id]], as: "PRDE", ready_date: "1970-01-01", uses_database_id: false) do |pull_request_diff_entry|
        {
          prefix: :prde,
          pull_request_diff_entry_id: pull_request_diff_entry.id
        }
      end

      def initialize(*)
        super
        @context.scoped_merge!(root_commit_arguments: { oid: object.pull_request_comparison.end_commit.oid })
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        Platform::Objects::PullRequest.async_api_can_access?(permission, object.pull_request)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.typed_can_see?("PullRequestComparison", object.pull_request_comparison)
      end

      def self.load_from_next_global_id(parsed_id)
        load_from_global_id(parsed_id.parts[:pull_request_diff_entry_id])
      end

      def self.load_from_global_id(id)
        Platform::Models::PullRequestDiffEntry.load_from_global_id(id)
      end

      visibility :internal

      minimum_accepted_scopes ["repo"]

      field :path, String, "The path of this changed file", null: false, visibility: :internal
      field :path_ownership, Objects::PathOwnership, null: false, description: "The owners for the patch's file path.", visibility: :internal
      field :oid, String, "The blob oid of the new file (or the old one if this is a deletion)", null: false, visibility: :internal
      field :path_digest, String, "The hashed path of the changed file", null: false, visibility: :internal
      field :lines_added, Integer, "The number of lines added in this patch.", method: :additions, null: false
      field :lines_deleted, Integer, "The number of lines removed in this patch.", method: :deletions, null: false
      field :lines_changed, Integer, "The total lines added or removed in this patch.", method: :changes, null: false
      field :new_tree_entry, Objects::TreeEntry, "The tree entry after the change.", null: true
      field :old_tree_entry, Objects::TreeEntry, "The tree entry before the change.", null: true
      field :similarity, Integer, "The percent similarity in the case of a rename.", visibility: :internal, null: true
      field :status, Enums::PatchStatus, "Identifies the status of the patch.", null: false
      field :text, String, "The textual diff of this patch.", null: true
      field :unicode_text, String, "The textual diff of this patch in Unicode.", visibility: :internal, null: true
      field :is_submodule, Boolean, null: false, method: :submodule?, description: "Whether or not the patch is in a submodule"
      field :is_binary, Boolean, null: false, method: :binary?, description: "Whether or not the patch is binary"
      field :is_large, Boolean, null: false, method: :is_large?, description: "Whether or not the patch is a large diff"
      field :is_too_big, Boolean, null: false, method: :too_big?, description: "Whether or not the patch's diff contents were skipped due to size", visibility: :internal
      field :is_lfs_pointer, Boolean, null: false, method: :lfs_pointer?, description: "Whether or not the patch contains LFS pointers", visibility: :internal
      field :blob_url, Scalars::URI, null: true, visibility: :internal, description: "The HTML blob patch URL."
      field :raw_url, Scalars::URI, null: true, visibility: :internal, description: "The HTML raw patch URL."
      field :contents_url, Scalars::URI, null: false, visibility: :internal, description: "The contents API URL."
      field :truncated_reason, String, null: true, visibility: :internal, description: "The reason why the patch was truncated.", method: :truncated_reason

      field :viewer_viewed_state, Enums::FileViewedState, description: "Whether the authenticated viewer has viewed this file in the given Pull Request", null: true, visibility: :internal

      def viewer_viewed_state
        user_reviewed_files = @object.pull_request.user_reviewed_files_for(@context[:viewer])
        if user_reviewed_files.reviewed?(@object.path)
          :viewed
        elsif user_reviewed_files.dismissed?(@object.path)
          :dismissed
        else
          :unviewed
        end
      end

      field :diff_lines, [Objects::DiffLine, null: true], scope: true, description: "The diff lines for this patch.", null: true do
        argument :injected_context_lines, [Inputs::DiffLineRange], description: "The list of line ranges for injected contexts added to the diff lines. The ranges can overlap and are not required to be sorted.", required: false
        argument :with_full_context, Boolean, description: "Whether or not to return the full context of the diff lines.", required: false, default_value: false
      end

      def diff_lines(**arguments)
        if arguments[:with_full_context] && arguments[:injected_context_lines].nil? && @object.can_expand_full_context_lines?
          context_lines = Struct.new(:start, :end).new(0, @object.new_tree_entry.line_count)
          return @object.async_diff_lines(injected_context_lines: [context_lines])
        end
        @object.async_diff_lines(injected_context_lines: arguments[:injected_context_lines])
      end

      field :threads, Connections.define(Objects::PullRequestThread), description: "The set of threads for this file.", visibility: :internal, null: false, connection: true do
        argument :subject_type, Enums::PullRequestReviewThreadSubjectType, description: "The subject type of the review thread", required: true, visibility: :internal
        argument :outdated_filter, Enums::PullRequestReviewThreadOutdatedFilterType, description: "Filters by whether the threads are outdated or not", required: false, default_value: "INCLUDE_OUTDATED", visibility: :internal
      end

      def threads(**arguments)
        outdated = case arguments[:outdated_filter]
        when "ONLY_OUTDATED"
          true
        when "EXCLUDE_OUTDATED"
          false
        else
          nil
        end

        Loaders::PullRequest::ReviewThreads.load(@object.pull_request.id, @context[:viewer], path: @object.path, subject_type: arguments[:subject_type], outdated: outdated).then do |threads|
          pr_threads = threads.map { |t| Platform::Models::PullRequestThread.new(t) }
          StableArrayWrapper.new(pr_threads)
        end
      end
    end
  end
end
