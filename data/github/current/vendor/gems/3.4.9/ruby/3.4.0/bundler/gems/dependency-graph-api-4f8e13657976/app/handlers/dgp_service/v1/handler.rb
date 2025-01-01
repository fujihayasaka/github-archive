module DgpService
  module V1
    class Handler < TracedHandler
      include DependencyGraph::Tracing

      PARTITION_SIZE = 500

      trace_method :get_licenses_for_packages
      def get_licenses_for_packages(req, env)
        if req.packages.blank?
          raise "Request must contain packages"
        end

        with_versions, without_versions = req.packages.uniq.partition { |package| package.package_versions.present? }

        package_releases = get_all_package_releases(without_versions)

        package_releases += get_versioned_package_releases(with_versions)

        attributions = {}
        if req.include_copyright_attributions
          release_ids = package_releases.map { |release| release[:id] }
          attributions = get_attributions(release_ids)
        end

        grouped_releases = package_releases.group_by { |release| [release[:package_name], release[:package_manager]] }

        licenses_for_packages = grouped_releases.map do |(package_name, package_manager), releases|
          package_licenses = releases.map do |release|
            DependencyGraphAPI::V1::GetLicensesForPackagesResponse::PackageLicenseInfo.new(
              package_version: release[:name],
              package_license: release[:license],
              attributions: attributions[release[:id]] || []
            )
          end

          DependencyGraphAPI::V1::GetLicensesForPackagesResponse::PackageLicenses.new(
            package_manager: package_manager,
            package_name: package_name,
            package_licenses: package_licenses
          )
        end

        DependencyGraphAPI::V1::GetLicensesForPackagesResponse.new(
          licenses: licenses_for_packages
        )
      end

      trace_method :get_dependencies_for_s_b_o_m
      def get_dependencies_for_s_b_o_m(req, env)
        repository_id = req.repository_id
        excluding_package_managers = req.excluding_package_managers
                                       .map { |e| Types::PackageManager.from_proto(e) { Types::PackageManager[:unknown] } }

        repository = Repository.find_by(github_repository_id: repository_id)

        return DependencyGraphAPI::V1::GetDependenciesForSBOMResponse.new unless repository

        manifests_scope = Manifest.where(repository_id: repository.id)

        manifests_scope = manifests_scope.where.not(package_manager: excluding_package_managers) if excluding_package_managers.any?

        dependency_table = DependencyGraph.use_normalized_tables? ? ManifestEntry : ManifestDependency
        dependency_pkg_table = DependencyGraph.use_normalized_tables? ? ManifestPackage : ManifestDependency
        dependency_req_table = DependencyGraph.use_normalized_tables? ? ManifestPackageVersion : ManifestDependency

        rel = dependency_table.joins(:manifest).merge(manifests_scope)

        # Excluding superseded manifests, c.f. https://github.com/github/dependency-graph/issues/1889
        rel = rel
        .joins("left join dg_manifests superseding_manifest
            on superseding_manifest.repository_id = dg_manifests.repository_id
            and superseding_manifest.path = dg_manifests.path
            and (#{superseding_cases})
          ")
        .where("superseding_manifest.id is null")

        if DependencyGraph.use_normalized_tables?
          rel = rel.joins(manifest_package_version: :manifest_package)
        end

        dependencies = rel
          .where("#{Manifest.table_name}.revision = #{dependency_table.table_name}.last_seen_at_revision")
          .distinct
          .pluck("#{Manifest.table_name}.manifest_type", "#{dependency_pkg_table.table_name}.package_name", "#{dependency_req_table.table_name}.requirements",
            "#{Manifest.table_name}.path", "#{Manifest.table_name}.filename",
          ).map do |manifest_type, package_name, requirements, path, filename|
            manifest_type = Types::Manifest.by(:id, manifest_type)
            dep = DependencyGraph::SBOM::Dependency.new(
              package_manager: manifest_type.package_manager,
              package_name: package_name,
              requirements: requirements,
              known_pinned: manifest_type.only_contains_pinned_deps
            )
            manifest_path = path.present? ? "#{path}/#{filename}" : filename
            dep.manifest_path = manifest_path
            dep
          end

        dependencies = deduplicate_dependencies(dependencies)

        Instrument.count("sbom.dependencies.count", dependencies.count, dependency_source: :database, repository_id: repository_id, rpc_service: "DgpAPI", rpc_method: "GetDependenciesForSBOM")

        dependencies_to_proto(dependencies)
      end

      private

      def get_versioned_package_releases(packages)
        fields = [:id, :name, :package_name, :package_manager, :license]
        package_versions = packages.flat_map do |package|
          package.package_versions.uniq.map do |package_version|
            package_manager_type = Types::PackageManager.from_proto(package.package_manager)

            [
              package_manager_type.to_i,
              package.package_name,
              # HOTFIX: See PackageReleaseSearchAdapter for context
              PackageReleaseSearchAdapter.adapted_dependency_version(package_manager_type, package_version)
            ]
          end
        end

        results = package_versions.each_slice(PARTITION_SIZE).flat_map do |slice|
          PackageRelease
            .where([:package_manager, :package_name, :name] => slice)
            .pluck(*fields)
            .map { |release| fields.zip(release).to_h }
        end

        map_releases_to_packages(packages, results)
      end

      def get_all_package_releases(packages)
        fields = [:id, :name, :package_name, :package_manager, :license]
        results = packages.each_slice(PARTITION_SIZE).flat_map do |slice|
          PackageRelease
            .where([:package_manager, :package_name] => slice.map { |package|
              [
                Types::PackageManager.from_proto(package.package_manager).to_i,
                package.package_name
              ]
            })
            .pluck(*fields)
            .map { |release| fields.zip(release).to_h }
        end

        map_releases_to_packages(packages, results)
      end

      trace_method :get_attributions
      def get_attributions(package_release_ids)
        # create a table of `key => [attributions]`. `key` is a unique release identifier.
        attributions = {}

        Attribution
          .where(dg_package_versions_id: package_release_ids)
          .pluck(:dg_package_versions_id, :attribution)
          .each do |package_release_id, attribution|
          attributions[package_release_id] ||= []
          attributions[package_release_id] << attribution
        end

        attributions
      end

      def superseding_cases
        Types::Manifest.filter_map do |manifest_type|
          superseded_by = Types::Manifest.filter { |m| m.supersedes == manifest_type }

          unless superseded_by.empty?
            superseded_by_ids_list = superseded_by.map(&:id).join(", ")
            "(dg_manifests.manifest_type = #{manifest_type.id}
              and superseding_manifest.manifest_type in (#{superseded_by_ids_list}))"
          end
        end.join(" or ")
      end

      trace_method :deduplicate_dependencies
      def deduplicate_dependencies(dependencies)
        dependencies.group_by { |dep| [dep.package_name, dep.requirements, dep.package_manager] }
                    .map { |_, group| group.find { |dep| dep.known_pinned } || group.first }
      end

      # The package releases we find in the database may have a mix of cases for
      # a single package name. This method compensates for that by ensuring:
      # - All package releases mapped to packages without case sensitivity
      # - The hash returned by the method uses the package name case from the
      #   request so the returned data matches the caller's expected case
      trace_method :map_releases_to_packages
      def map_releases_to_packages(packages, package_releases)
        packages.each_with_object([]) do |package, package_list|
          matches = package_releases.find_all do |release|
            release[:package_name].downcase == package.package_name.downcase
          end

          # Ensure we use the package's case in the data we return for serialisation
          matches = matches.map do |m|
            m.merge({ package_name: package.package_name })
          end

          package_list.concat(matches) if matches.any?
        end
      end

      trace_method :dependencies_to_proto
      def dependencies_to_proto(dependencies)
        DependencyGraphAPI::V1::GetDependenciesForSBOMResponse.new(
          dependencies: dependencies.map do |dependency|
            exact_version = dependency.exact_version
            DependencyGraphAPI::V1::GetDependenciesForSBOMResponse::Dependency.new(
              package_manager: dependency.package_manager.to_proto,
              package_name: dependency.package_name,
              version: exact_version.present? ? PackageReleaseSearchAdapter.adapted_dependency_version(dependency.package_manager, exact_version) : nil,
              version_range: exact_version.present? ? nil : dependency.requirement_set.serialize,
              manifest_path: dependency.manifest_path,
            )
          end
        )
      end
    end
  end
end
