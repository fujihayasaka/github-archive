require_relative "abstract_manifest"

module DependencyGraph
  module ObjectModel
    # This manifest corresponds to a Dependency Snapshots API manifest (Github::DependencySnapshotsApi::Manifest)
    class DSAPIManifest < AbstractManifest
      attr_reader :name, :file_path, :snapshot_id

      def initialize(manifest, snapshot = nil)
        @name = manifest.name
        @file_path = manifest.file_path
        @snapshot_id = manifest.snapshot_id
        @snapshot = snapshot

        @manifest = manifest
        # Because the dependencies and manifest data structures aren't keyed by what most of the rest of our system
        # considers unique info (manifest: file path, dependencies: purl), we create an interim hash on the unique info
        # to decide what to do.
        @dependencies = {}
        manifest.dependencies.each { |dependency_name, dependency|  @dependencies[dependency.package_url] = DSAPIDependency.new(dependency_name, dependency) }

        # This is no longer supported by ds-api schema?
        # file_path_to_use = attempt_to_make_file_path_relative(manifest.path, dependencies_response.snapshot.scan_directory)

        # package_manager as a file level concept is a little weird with snapshots -- We will currently do a
        # "best fit" based on our manifest file adapters, but I do wonder if we should be introspecting the dependencies
        # themselves (e.g. if all dependencies are "gradle", this is a "gradle" manifest).
        path = ManifestAdapters.normalize_path(path: @manifest.file_path)
        filename = File.basename(path)
        @manifest_package_manager = ManifestAdapters.recognized_path?(filename: filename, path: path)&.package_manager \
          || ManifestAdapters.snapshot_only_package_manager(filename) \
          || Types::PackageManager::UNKNOWN
      end

      def package_manager
        @manifest_package_manager
      end

      def dependencies
        @dependencies.values
      end

      def source
        "snapshots"
      end

      def detector_name
        @snapshot&.detector.name
      end

      def scanned
        @snapshot&.scanned.to_time
      end

      # Input: Array of Github::DependencySnapshotsApi::Manifest
      # Output: Array of DSAPIManifests
      def self.from_api_manifests(api_manifests, snapshots = {})
        api_manifests.map do |manifest|
          new(manifest, snapshots[manifest.snapshot_id])
        end
      end
    end
  end
end
