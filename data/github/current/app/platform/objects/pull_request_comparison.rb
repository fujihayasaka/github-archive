# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class PullRequestComparison < Platform::Objects::Base
      description "Represents a diff between two commits objects."

      def initialize(*)
        super
        @context.scoped_merge!(root_commit_arguments: { oid: @object.end_commit.oid })
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        Platform::Objects::PullRequest.async_api_can_access?(permission, object.pull)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.typed_can_see?("PullRequest", object.pull)
      end

      minimum_accepted_scopes ["repo"]

      field :annotations, Connections.define(Objects::CheckAnnotation), description: "The check annotations associated with changed and unchanged files at the comparison's end commit", null: true, visibility: :internal, connection: true, numeric_pagination_enabled: true

      def annotations(**arguments)
        @object.pull.async_compare_repository.then do |repository|
          repository.annotations_for(
            inline_only: true,
            limit: ::CheckAnnotation::MAX_READ_LIMIT,
            sha: @object.end_commit.oid,
          )
        end
      end

      field :files_changed, Integer, "The number of files changed in this diff.", method: :changed_files, null: false

      field :lines_added, Integer, "The number of lines added in this diff.", method: :additions, null: false

      field :lines_deleted, Integer, "The number of lines removed in this diff.", method: :deletions, null: false

      field :lines_changed, Integer, "The total lines added or removed in this diff.", method: :changes, null: false

      field :old_commit, Objects::Commit, "The commit before the changes were made.", method: :start_commit, null: false

      field :new_commit, Objects::Commit, "The commit after the changes were made.", method: :end_commit, null: false

      field :diff_entries, Connections.define(Objects::PullRequestDiffEntry), description: "The set of entries constituting this diff.", visibility: :internal, null: false, connection: true

      def diff_entries
        # Diff entries are sorted alphabetically by path, but we want to sort them
        # to match the behavior of the relay client, which uses String.prototype.localeCompare
        # and puts capitals after lowercase letters. This is notably different than the default
        # `<=>` operator behavior
        entries = object.entries.map do |diff_entry|
          Models::PullRequestDiffEntry.new(diff_entry: diff_entry, pull_request_comparison: @object, pull_request: @object.pull)
        end.sort { |a, b| Helpers::PathComparer.compare_paths(a.path, b.path) }

        ArrayWrapper.new(entries)
      end

      field :diff_entry, Objects::PullRequestDiffEntry, description: "Returns a PullRequestDiffEntry by the given path.", visibility: :internal, null: false do
        argument :path, String, required: true, description: "The path of the PullRequestDiffEntry to return."
      end

      def diff_entry(path:)
        diff_entry = object.entries.find { |subject| subject.path == path }

        if diff_entry.nil?
          raise Platform::Errors::NotFound.new("Could not find a PullRequestDiffEntry with the given path.")
        end

        Models::PullRequestDiffEntry.new(diff_entry: diff_entry, pull_request_comparison: @object, pull_request: @object.pull)
      end

      field :summary, [Objects::PullRequestSummaryDelta], description: "Lists the files changed within this pull request.", visibility: :internal, null: true

      def summary
        ArrayWrapper.new(@object.deltas.map { |delta| Models::PullRequestSummaryDelta.new(delta: delta, pull: @object.pull, comparison: @object, user: @context[:viewer]) })
      end
    end
  end
end
