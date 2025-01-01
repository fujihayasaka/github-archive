# typed: true
# frozen_string_literal: true

# Module for methods used in both Code Scanning and Code Quality
module CodeAnalysisControllerMethods
  extend T::Helpers

  requires_ancestor { ApplicationController }

  sig { params(commit_oid: T.nilable(String), blob_paths: T::Array[String]).returns(T::Hash[String, TreeEntry]) }
  def blobs(commit_oid:, blob_paths:)
    blob_map = {}
    if commit_oid
      blob_paths_with_commit = blob_paths.map { |blob_path| [commit_oid, blob_path] }
      # Fetch blob_oids and match them to paths
      blob_oids = current_repository.rpc.read_blob_oids(blob_paths_with_commit, skip_bad: true)

      # Fetch blobs by blob_oid and match them to paths
      raw_blobs = current_repository.read_objects(blob_oids.select(&:present?), :blob)
      oids_by_blob_path = Hash[blob_paths.zip(blob_oids)]

      # Iterate over blob paths in case there are blobs with the same file contents but different paths
      blob_paths.each do |blob_path|
        blob_oid = oids_by_blob_path[blob_path]
        raw_blob = raw_blobs.find { |raw_blob| raw_blob["oid"] == blob_oid }
        next unless raw_blob

        # Create a TreeEntry for the blob and add it to the map
        blob_map[blob_path] = TreeEntry.new(current_repository, raw_blob.merge("path" => blob_path))
      end
    end
    blob_map
  end
end
