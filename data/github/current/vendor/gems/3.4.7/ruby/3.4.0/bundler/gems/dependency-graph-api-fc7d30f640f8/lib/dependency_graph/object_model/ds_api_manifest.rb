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

      # Input: Array of DS-API manifests, each with a "name" and "snapshot_id" field.
      # Output: DS-API manifests "collapsed" (manifests are an array, dependencies are dictionaries keyed by purl).
      def self.collapse_ds_api_manifests(manifests, snapshots = {})
        # ds-api returns manifests "uniquely" by name, which means that you can have multiple manifest entries for the
        # same logical file. This isn't really what the rest of gh/gh expects today (they expect one entry per file) and
        # arguably all callers that just care about the "dependencies" level of concern also do not care.
        # So, we collapse all dependency information into manifests grouped by file name where possible.
        if !manifests.present? || manifests.length == 0
          return manifests
        end

        collapsed_manifests = {}
        manifests.each do |manifest|
          # we would prefer to use the file_path for all of these cases, but not every manifest has one
          merge_key = manifest.file_path.empty? ? manifest.name : manifest.file_path
          if collapsed_manifests.key?(merge_key)
            collapsed_manifests[merge_key].collapse_other_ds_api_manifest_into(manifest)
          else
            # We still need the interestingly structured (by purl) dependencies as our baseline
            collapsed_manifests[merge_key] = DependencyGraph::ObjectModel::DSAPIManifest.new(manifest, snapshots[manifest.snapshot_id])
          end
        end
        collapsed_manifests.values
      end

      # NOTE: This would be private, but class methods aren't allowed to use private instance methods.
      def collapse_other_ds_api_manifest_into(manifest_from)
        manifest_from.dependencies.each do |dependency_name, dependency|
          package_url = dependency.package_url
          if @dependencies[package_url]
            # this dependency already exists in the manifest we're collapsing into. Largely a no-op, except we should make
            # sure that business logic like "scope" behaves as expected.
            # todo SCOPE and RELATIONSHIP?
          else
            @dependencies[package_url] = DSAPIDependency.new(dependency_name, dependency)
          end
        end
      end
    end
  end
end
