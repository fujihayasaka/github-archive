# frozen_string_literal: true

module DependencyGraph
  class ManifestDependencyReplicator
    include DependencyGraph::Tracing

    trace_method :to_manifest_entries
    def to_manifest_entries(manifest_dependencies)
      return if manifest_dependencies.empty?

      # First pass over the batch: upsert all the ManifestPackages
      packages = import_packages(manifest_dependencies)

      # Second pass over the batch: upsert all the ManifestPackageVersions
      package_versions = import_package_versions(manifest_dependencies, packages:)

      # Third pass over the batch: upsert all the ManifestEntries
      entries = manifest_dependencies.map do |dep|
        pkg_id = packages[[dep.package_manager.to_i, dep.package_name&.downcase]]
        pkg_ver_id = package_versions[[pkg_id, dep.requirements&.downcase]]

        [
          dep.manifest_id,
          pkg_ver_id,
          dep.scope,
          dep.last_seen_at_revision,
        ]
      end

      create_result = ManifestEntry.import(
        [:manifest_id, :manifest_package_version_id, :scope, :last_seen_at_revision],
        entries,
        on_duplicate_key_update: "last_seen_at_revision = VALUES(last_seen_at_revision), scope = LEAST(scope, VALUES(scope)), updated_at = VALUES(updated_at)"
      )

      if create_result.failed_instances.any?
        create_result.failed_instances.each do |failed|
          DependencyGraph.logger.error "Failed to import ManifestEntry (#{failed})"
        end
      end

      Instrument.count("manifest_dependency_replicator.entries_created", create_result.num_inserts)
      Instrument.count("manifest_dependency_replicator.entries_failed_creates", create_result.failed_instances.size)
    end

    # Given a list of ManifestDependencies, import all the ManifestPackages,
    # and return a hash of the form { [package_manager, package_name] => id }
    trace_method :import_packages
    def import_packages(manifest_dependencies)
      return {} if manifest_dependencies.empty?

      # Using a set lets us deduplicate packages within the batch
      packages = Set.new

      manifest_dependencies.each do |dep|
        if dep.package_manager.nil? || dep.package_name.nil?
          DependencyGraph.logger.warn "Skipping ManifestPackage import for (#{dep.package_manager}, #{dep.package_name}) (ManifestDependency ID: #{dep.id})"
          next
        end

        packages << [dep.package_manager.to_i, dep.package_name]
      end

      # If packages is empty, we didn't find any packages that we could import
      return {} if packages.empty?

      # The rest of the calls require an array
      packages = packages.to_a

      result = ManifestPackage.import(
        [:package_manager, :package_name],
        packages,
        on_duplicate_key_ignore: true
      )
      # If there is a duplicate, and insertion is ignored, "num_inserts" will _still be incremented_
      Instrument.count("manifest_dependency_replicator.packages_imported", result.num_inserts)
      Instrument.count("manifest_dependency_replicator.packages_failed_imports", result.failed_instances.size)
      if result.failed_instances.any?
        result.failed_instances.each do |failed|
          DependencyGraph.logger.error "Failed to import ManifestPackage (#{failed})"
        end
      end

      ## Rails 7.1+ hash condition querying:
      ## https://guides.rubyonrails.org/v7.1/active_record_querying.html#hash-conditions
      ids_by_manager_and_name = ManifestPackage
        .where([:package_manager, :package_name] => packages)
        .pluck(:id, :package_manager, :package_name)
        .map { |id, manager, name| [[manager, name.downcase], id] }
        .to_h

      return ids_by_manager_and_name
    end

    # Given a list of ManifestDependencies and a hash of ManifestPackages, import all the ManifestPackageVersions,
    # and return a hash of the form { [package_id, requirements] => id }
    trace_method :import_package_versions
    def import_package_versions(manifest_dependencies, packages:)
      return {} if manifest_dependencies.empty?

      package_versions = []
      pv_tuples = Set.new

      manifest_dependencies.each do |dep|
        pkg_id = packages[[dep.package_manager.to_i, dep.package_name&.downcase]]

        if pkg_id.nil? || dep.requirements.nil?
          DependencyGraph.logger.warn "Skipping ManifestPackageVersion import for (#{dep.package_manager}, #{dep.package_name}, #{dep.requirements}) (ManifestDependency ID: #{dep.id})"
          next
        end

        # Deduplicate package versions within the batch (manifest dependencies that map to the same package and requirements)
        if pv_tuples.add?([pkg_id, dep.requirements])
          package_versions << [
            dep.requirements,
            dep.encoded_lower_bound,
            dep.encoded_upper_bound,
            pkg_id
          ]
        end
      end

      # If package_versions is empty, we didn't find any package_versions that we could import
      return {} if package_versions.empty?

      result = ManifestPackageVersion.import(
        [:requirements, :encoded_lower_bound, :encoded_upper_bound, :manifest_package_id],
        package_versions,
        on_duplicate_key_ignore: true
      )
      # If there is a duplicate, and insertion is ignored, "num_inserts" will _still be incremented_
      Instrument.count("manifest_dependency_replicator.package_versions_imported", result.num_inserts)
      Instrument.count("manifest_dependency_replicator.package_versions_failed_imports", result.failed_instances.size)
      if result.failed_instances.any?
        result.failed_instances.each do |failed|
          DependencyGraph.logger.error "Failed to import ManifestPackageVersion (#{failed})"
        end
      end

      ids_by_pkg_id_and_requirements = ManifestPackageVersion
        .where([:manifest_package_id, :requirements] => pv_tuples.to_a)
        .pluck(:id, :manifest_package_id, :requirements)
        .map { |id, pkg_id, requirements| [[pkg_id, requirements.downcase], id] }
        .to_h

      return ids_by_pkg_id_and_requirements
    end
  end
end
