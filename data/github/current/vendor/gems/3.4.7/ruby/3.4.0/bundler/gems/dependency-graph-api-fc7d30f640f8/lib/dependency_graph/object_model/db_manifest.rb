module DependencyGraph
  module ObjectModel
    # This manifest corresponds to Dependency Graph API's ActiveRecord "Manifest" model, used as the target model for storage of ParsedManifests
    class DBManifest < AbstractManifest
      def initialize(manifest)
        @manifest = manifest
        if DependencyGraph.use_normalized_tables?
          @dependencies = manifest.entries.map { |d| DBDependency.new(d) }
        else
          @dependencies = manifest.dependencies.map { |d| DBDependency.new(d) }
        end
      end

      def file_path
        @manifest.path.present? ? File.join(@manifest.path, @manifest.filename) : @manifest.filename
      end

      def package_manager
        @manifest.package_manager
      end

      def dependencies
        @dependencies
      end

      def manifest_type
        @manifest.manifest_type.to_s
      end
    end
  end
end
