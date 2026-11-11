require "zlib"
require "dependency_graph/object_model/base_graphql_manifest"
require "dependency_graph/object_model/ds_graphql_dependency"

module DependencyGraph::ObjectModel
  class DSGraphqlManifest < BaseGraphqlManifest
    def self.from_cache_payload(payload)
      raw_manifest = Github::DependencySnapshotsApi::Manifest.decode(payload.fetch(:manifest_proto))
      raw_snapshot = payload[:snapshot_proto] ?
        Github::DependencySnapshotsApi::GetDependenciesForRepositoryResponse::Snapshot.decode(payload[:snapshot_proto]) : nil
      ds_api_manifest = DSAPIManifest.new(raw_manifest)
      new(ds_api_manifest, raw_snapshot, payload.fetch(:repository_id))
    end

    def initialize(manifest, snapshot, repository_id)
      @snapshot = snapshot
      @repository_id = repository_id

      # Set id to a hash of the path or name represented as a negative number.
      # This is good enough for the UI to pick out a manifest when paging
      # dependencies.
      hashable_name = manifest.file_path.present? ? manifest.file_path : manifest.name
      generated_id = 0 - (Zlib.crc32(hashable_name) & (2**31 - 1))

      super(generated_id, repository_id, manifest)
    end

    # Give a filename if it exists, otherwise return the manifest name. This is
    # a hack to show something meaningful in a web ui that doesn't understand
    # anything but files.
    def filename
      return @filename if defined?(@filename)

      if !@manifest.file_path.present? || @manifest.file_path.empty?
        @filename = @manifest.name
      else
        @filename = File.basename(@manifest.file_path)
      end

      @filename
    end

    def path
      return @path if defined?(@path)

      if !@manifest.file_path.present? || @manifest.file_path.empty?
        @path = ""
      elsif @manifest.file_path == filename
        @path = ""
      else
        @path = File.dirname(@manifest.file_path)
      end

      @path
    end

    def name
      @manifest.name
    end

    def snapshot_id
      @manifest.snapshot_id
    end

    def is_dependabot?
      snapshot_detector_name&.downcase == "dependabot"
    end

    def is_empty?
      @manifest&.dependencies&.empty?
    end

    def snapshot_detector_name
      @snapshot&.detector&.name
    end

    def snapshot_scanned
      @snapshot&.scanned&.to_time&.iso8601
    end

    def source
      "snapshots"
    end

    def cache_payload
      {
        repository_id: github_repository_id,
        manifest_proto: Github::DependencySnapshotsApi::Manifest.encode(@manifest.proto_manifest),
        snapshot_proto: @snapshot ?
          Github::DependencySnapshotsApi::GetDependenciesForRepositoryResponse::Snapshot.encode(@snapshot) : nil,
      }
    end

    # This method takes the dependencies from the wrapped `@manifest`
    def fetch_dependencies
      return @fetched_dependencies if defined?(@fetched_dependencies)

      @fetched_dependencies = @manifest.dependencies.map do |dep|
        DependencyGraph::ObjectModel::DSGraphqlDependency.new(dep, include_transitive_labels: true)
      end
    end
  end
end
