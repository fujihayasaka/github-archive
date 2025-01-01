# typed: true
# frozen_string_literal: true

module ScanningControllerMethods
  extend T::Helpers
  include CommitHelper

  requires_ancestor { ApplicationController }

  # Load the commits for the given commit oids.
  #
  # Returns an array of raw Commit objects from `app/models/commit.rb`.
  sig { params(commit_oids: T::Array[String]).returns(T::Array[Commit]) }
  def load_commits(commit_oids)
    T.cast(
      Platform::Loaders::GitObject.load_all(current_repository, commit_oids.uniq, expected_type: "commit").sync.compact,
      T::Array[Commit])
  end

  sig { params(commit_oids: T::Array[String]).returns(T::Hash[String, Commit]) }
  def commits_by_oid(commit_oids)
    commits = load_commits(commit_oids)
    prefill_for_condensed_commit_view(commits, current_user)

    T.cast(commits.index_by(&:oid), T::Hash[String, Commit])
  end

  sig { params(commit_oid: T.nilable(String), blob_paths: T::Array[String]).returns(T::Hash[String, TreeEntry]) }
  def blobs(commit_oid:, blob_paths:)
    blob_map = {}
    if commit_oid
      blob_paths_with_commit = blob_paths.map { |blob_path| [commit_oid, blob_path] }
      # Fetch blob_oids and match them to paths
      blob_oids = current_repository.rpc.read_blob_oids(blob_paths_with_commit, skip_bad: true)

      # Fetch blobs by blob_oid and match them to paths
      raw_blobs = current_repository.read_objects(blob_oids.select(&:present?), :blob)

      if blobs_refactor_enabled?(current_repository)
        oids_by_blob_path = Hash[blob_paths.zip(blob_oids)]

        # Iterate over blob paths in case there are blobs with the same file contents but different paths (e.g., due to renames).
        blob_paths.each do |blob_path|
          blob_oid = oids_by_blob_path[blob_path]
          raw_blob = raw_blobs.find { |raw_blob| raw_blob["oid"] == blob_oid }
          next unless raw_blob

          # Create a TreeEntry for the blob and add it to the map
          blob_map[blob_path] = TreeEntry.new(current_repository, raw_blob.merge("path" => blob_path))
        end
      else
        paths_by_oid = Hash[blob_oids.zip(blob_paths)]

        raw_blobs.map do |raw_blob|
          blob_path = paths_by_oid[raw_blob["oid"]]
          blob_map[blob_path] = TreeEntry.new(current_repository, raw_blob.merge("path" => blob_path))
        end
      end

    end
    blob_map
  end

  def check_code_scanning_read
    render_404 unless current_repository.code_scanning_readable_by?(current_user)
  end

  def check_code_scanning_write
    render_404 unless current_repository.code_scanning_writable_by?(current_user)
  end

  sig { params(repository: Repository).returns(T::Boolean) }
  def blobs_refactor_enabled?(repository)
    !!(repository.feature_enabled?(:blobs_refactor) ||
      repository.owner&.feature_enabled?(:blobs_refactor))
  end
end
