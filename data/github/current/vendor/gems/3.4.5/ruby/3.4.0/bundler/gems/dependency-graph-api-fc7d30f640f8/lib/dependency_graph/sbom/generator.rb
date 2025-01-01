# frozen_string_literal: true

require "dependency_graph/tracing"

module DependencyGraph
  module SBOM
    # SBOM::Generator is a superclass for generating SBOM documents from the dependency graph and associated snapshots.
    class Generator
      include DependencyGraph::Tracing
      trace_method :get_manifests_from_database, span_attribute_extractor: -> (_instance, *_args, **kwargs) do
        {
          GitHub::SemConv::Trace::GH::REPO_ID => kwargs[:repository_id],
        }
      end
      trace_method :get_manifests_from_snapshots, span_attribute_extractor: -> (_instance, *_args, **kwargs) do
        {
          GitHub::SemConv::Trace::GH::REPO_ID => kwargs[:repository_id],
        }
      end
      trace_method :batch_query_licenses_for_dependencies

      class SBOMGenerationError < StandardError; end

      def initialize(snapshot_dependencies_client: default_snapshot_dependencies_client, features_client: default_features_client)
        @snapshot_dependencies_client = snapshot_dependencies_client
        @features_client = features_client
      end

      # generate an SPDX document for the given repository ID.
      def generate(repository_id:)
        raise NotImplementedError
      end

      protected

      def default_snapshot_dependencies_client
        DependencyGraphAPI::DependencySnapshotsAPI::DependenciesClient.new
      end

      attr_reader :features_client
      def default_features_client
        Monolith::Features.new
      end

      # Returns a unique-ish array of dependencies (unique by manifest type) in the given repository. Duplicates will be
      # removed later in the SBOM generation process.
      def get_dependencies_from_database(repository_id:, preview_enabled: false, exclude_superseded_manifests: false)
        repository = Repository.find_by(github_repository_id: repository_id)

        # The repository might not be available in our database, but it might still be valid,
        # and it might still have snapshots.
        return [] unless repository

        manifests_scope = Manifest.where(repository_id: repository.id)

        if (!preview_enabled)
          preview_package_managers = DependencyGraph::PACKAGE_MANAGER_PREVIEW.map(&:to_i)
          manifests_scope = manifests_scope.where.not(package_manager: preview_package_managers) if preview_package_managers.any?

          preview_manifest_types = DependencyGraph::MANIFEST_TYPE_PREVIEW.map(&:to_i)
          manifests_scope = manifests_scope.where.not(manifest_type: preview_manifest_types) if preview_manifest_types.any?
        end

        superseding_cases =
          Types::Manifest.filter_map do |manifest_type|
            superseded_by = Types::Manifest.filter { |m| m.supersedes == manifest_type }

            unless superseded_by.empty?
              superseded_by_ids_list = superseded_by.map(&:id).join(", ")
              "(dg_manifests.manifest_type = #{manifest_type.id}
                and superseding_manifest.manifest_type in (#{superseded_by_ids_list}))"
            end
          end
          .join(" or ")

        dependency_table = DependencyGraph.use_normalized_tables? ? ManifestEntry : ManifestDependency
        dependency_pkg_table = DependencyGraph.use_normalized_tables? ? ManifestPackage : ManifestDependency
        dependency_req_table = DependencyGraph.use_normalized_tables? ? ManifestPackageVersion : ManifestDependency

        rel = dependency_table
          .joins(:manifest).merge(manifests_scope)

        if exclude_superseded_manifests
          rel = rel
          # Exclude superseded manifests, c.f. https://github.com/github/dependency-graph/issues/1889
          .joins("left join dg_manifests superseding_manifest
            on superseding_manifest.repository_id = dg_manifests.repository_id
            and superseding_manifest.path = dg_manifests.path
            and (#{superseding_cases})
          ")
          .where("superseding_manifest.id is null")
        end

        if DependencyGraph.use_normalized_tables?
          rel = rel
            .joins(manifest_package_version: :manifest_package)
        end

        rel = rel
          .where("#{Manifest.table_name}.revision = #{dependency_table.table_name}.last_seen_at_revision")
          .joins("LEFT JOIN #{PackageRelease.table_name}
            ON #{PackageRelease.table_name}.package_manager = #{Manifest.table_name}.package_manager
            AND #{PackageRelease.table_name}.package_name = #{dependency_pkg_table.table_name}.package_name
            AND #{PackageRelease.table_name}.name = TRIM(Leading '= ' FROM #{dependency_req_table.table_name}.requirements)")
          .distinct
          .pluck("#{Manifest.table_name}.manifest_type", "#{dependency_pkg_table.table_name}.package_name", :requirements, "#{PackageRelease.table_name}.license")
          .map do |manifest_type, package_name, requirements, license|
            manifest_type = Types::Manifest.by(:id, manifest_type)
            Dependency.new(
              package_manager: manifest_type.package_manager,
              package_name: package_name,
              requirements: requirements,
              license: license,
              known_pinned: manifest_type.only_contains_pinned_deps
            )
          end

        batch_query_attributions_for_dependencies(rel)

        rel
      end

      def get_dependencies_and_detectors_from_snapshots(repository_id:)
        response = @snapshot_dependencies_client.get_dependencies_for_repository(
          repository_id,
          # Internal snapshots are not launched externally, so we don't need to include them here yet
          include_internal_snapshots: false,
        )
        if response.error.present?
          raise SBOMGenerationError.new("An unexpected error occurred during snapshot retrieval: " + response.error.message)
        end

        manifests = DependencyGraph::ObjectModel::DSAPIManifest
          .collapse_ds_api_manifests(response.data.all_manifests, response.data.snapshots)

        dependencies = manifests
          .flat_map(&:dependencies)
          .map do |dep|
            Dependency.new(
              package_manager: dep.package_manager,
              package_name: dep.full_package_name,
              requirements: dep.requirement_set.serialize,
              known_pinned: true
            )
          end

        detectors = manifests.map(&:detector_name).sort.uniq

        batch_query_licenses_for_dependencies(dependencies)
        batch_query_attributions_for_dependencies(dependencies)

        return [dependencies, detectors]
      end

      # returns a composite key based on the dependency metadata
      def dependency_key(ecosystem, name, version)
        "#{ecosystem}-#{name}-#{version}"
      end

      def batch_query_licenses_for_dependencies(dependencies)
        # generate (package_manager, package_name, version) tuples for all the
        # dependencies so we can query PackageReleases for licenses
        release_refs = dependencies
          # make sure to only query for dependencies that have specified an exact version
          .filter_map do |dep|
            if dep.exact_version.present?
              [dep.package_manager.to_i, dep.package_name, dep.exact_version]
            end
          end
          .uniq

        # create a table of `key => license` rows. `key` is a unique
        # release identifier.
        licenses = {}

        release_refs.each_slice(500) do |batch|
          PackageRelease
            .where_in(["package_manager", "package_name", "name"], batch)
            .pluck(:package_manager, :package_name, :name, :license)
            .each do |package_manager, package_name, name, license|
              package_manager = Types::PackageManager.by(:id, package_manager)
              key = dependency_key(package_manager, package_name, name)
              licenses[key] = license
            end
        end

        dependencies.each do |dep|
          key = dependency_key(dep.package_manager, dep.package_name, dep.exact_version)
          dep.license = licenses[key]
        end
      end

      def batch_query_attributions_for_dependencies(dependencies)
        # generate (package_manager, package_name, version) tuples for all the
        # dependencies so we can query PackageReleases for licenses
        release_refs = dependencies
          # make sure to only query for dependencies that have specified an exact version
          .filter_map do |dep|
            if dep.exact_version.present?
              [dep.package_manager.to_i, dep.package_name, dep.exact_version]
            end
          end
          .uniq

        # create a table of `key => license` rows. `key` is a unique
        # release identifier.
        attributions = {}

        release_refs.each_slice(500) do |batch|
          releases = PackageRelease
            .where_in(["package_manager", "package_name", "name"], batch)
            .pluck(:id, :package_manager, :package_name, :name)

          ids = releases.map { |r| r[0] }
          keys = releases.map { |r| [r[0], dependency_key(Types::PackageManager.coerce(r[1]), r[2], r[3])] }.to_h

          Attribution
            .where(dg_package_versions_id: ids)
            .pluck(:dg_package_versions_id, :attribution)
            .each do |package_release_id, attribution|
              attributions[keys[package_release_id]] = [] unless attributions[keys[package_release_id]]
              attributions[keys[package_release_id]] << attribution
            end
        end

        dependencies.each do |dep|
          key = dependency_key(dep.package_manager, dep.package_name, dep.exact_version)
          dep.attributions = attributions[key]
        end
      end
    end
  end
end
