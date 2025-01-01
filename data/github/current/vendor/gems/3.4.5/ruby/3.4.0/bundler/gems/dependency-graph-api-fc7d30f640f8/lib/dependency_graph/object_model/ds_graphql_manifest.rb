require "zlib"
require "dependency_graph/object_model/base_graphql_manifest"
require "dependency_graph/object_model/ds_graphql_dependency"

module DependencyGraph::ObjectModel
  class DSGraphqlManifest < BaseGraphqlManifest

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

    def snapshot_detector_name
      @snapshot.detector.name
    end

    def snapshot_scanned
      @snapshot.scanned.to_time.iso8601
    end

    def source
      "snapshots"
    end

    # This method takes the dependencies from the wrapped `@manifest`
    def fetch_dependencies
      @manifest.dependencies.map do |dep|
        DependencyGraph::ObjectModel::DSGraphqlDependency.new(dep, include_transitive_labels: ds_transitive_labels_enabled?(@repository_id))
      end
    end

    private

    def ds_transitive_labels_enabled?(repository_id)
      @ds_transitive_labels_enabled ||= DependencyGraph.flipper[:dependency_graph_snapshot_transitive_labels].enabled?(FeatureFlags::Actor::Repository.new(repository_id))
    end
  end
end
