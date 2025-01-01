# typed: true
# frozen_string_literal: true

# Class that encapsulates the logic of detecting manifests in a repository.
class ManifestEnumerator
  include GitHub::Tracing

  # Simple object to hold a manifest path and blob OID.
  # Intended to be used by jobs that send Hydro events that need this data.
  class Manifest
    attr_reader :full_path, :blob_oid

    def initialize(full_path, blob_oid = GitHub::NULL_OID)
      @full_path, @blob_oid = full_path, blob_oid
    end

    def filename
      File.basename(full_path)
    end

    def path
      # Remove '.' at the beginning of the path
      File.dirname(full_path).sub(/\A\.\z/, "")
    end
  end

  # Given a repository and a commit, return a list of the manifests inside it (incl. filename, path and blob OIDs)
  # @repository the repository to search
  # @commit_id the point in time (i.e. commit OID) we're interested in evaluating
  def scan_repository(repository, commit_oid)
    paths = repo_file_tree(repository, commit_oid)
    # make sure that the list of paths is sorted by their depth
    paths = paths.sort_by { |path| [path.count("/"), path] }
    manifest_paths = paths.select { |path| DependencyManifestFile.recognized_path?(path: path) }

    if manifest_paths.count > repository.max_manifest_files
      GitHub.logger.info("Manifest paths count is over max manifest files", {
        "gh.repo.id" => repository.id,
        "gh.dependency_graph.manifest_paths_count" => manifest_paths.count,
        "gh.dependency_graph.max_manifest_files" => repository.max_manifest_files,
      })
      GitHub.instrument "repo.max_manifests_hit_on_detect", amount: manifest_paths.count

      manifest_paths = manifest_paths.first(repository.max_manifest_files)
    end

    blob_oids_for_manifest_paths = repository.rpc.read_blob_oids(manifest_paths.map { |path| [commit_oid, path] })

    manifest_paths.each_with_index.map do |path, index|
      Manifest.new(path, blob_oids_for_manifest_paths[index])
    end
  end

  # Given a Push, return lists of manifests that were changed or removed.
  # Returns a two-element array:
  # [
  #   <array of Manifest objects that were changed>,
  #   <array of Manifest objects that were removed>
  # ]
  #
  # Use: changed, removed = enumerator.scan_push(push)
  def scan_push(push)
    changed_files = push.changed_files(decompose_renames: true)

    return [] if changed_files.nil?

    changed_manifests = []
    removed_manifests = []

    changed_files.each do |file|
      next unless DependencyManifestFile.recognized_path?(path: file.path)

      if file.deletion?
        removed_manifests << Manifest.new(file.path)
      else
        changed_manifests << Manifest.new(file.path, file.oid)
      end
    end

    if changed_manifests.count > push.repository.max_manifest_files
      GitHub.logger.info("Changed manifest count is over max manifest files", {
        "gh.repo.id" => push.repository.id,
        "gh.repo.push.id" => push.id,
        "gh.dependency_graph.changed_manifest_count" => changed_manifests.count,
        "gh.dependency_graph.max_manifest_files" => push.repository.max_manifest_files,
      })

      changed_manifests = changed_manifests.first(push.repository.max_manifest_files)
    end

    [changed_manifests, removed_manifests]
  end

  private

  trace_method :repo_file_tree
  def repo_file_tree(repository, commit_oid)
    repository.rpc.tree_file_list(commit_oid).select(&:valid_encoding?)
  end
end
