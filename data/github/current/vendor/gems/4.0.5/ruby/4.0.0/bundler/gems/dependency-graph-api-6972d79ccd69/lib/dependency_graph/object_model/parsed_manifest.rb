module DependencyGraph::ObjectModel
  # This manifest corresponds to Dependency Graph API's ParsedManifest model, used as a non-stored result of a file parse
  class ParsedManifest < AbstractManifest
    def initialize(manifest)
      @manifest = manifest
      @dependencies = manifest.dependencies.map { |d| ParsedManifestDependency.new(d) }
    end

    def file_path
      @manifest.file_path
    end

    def package_manager
      @manifest.package_manager
    end

    def dependencies
      @dependencies
    end

    def is_vendored
      @manifest.vendored?
    end

    def manifest_type
      @manifest.manifest_type.to_s
    end
  end
end
