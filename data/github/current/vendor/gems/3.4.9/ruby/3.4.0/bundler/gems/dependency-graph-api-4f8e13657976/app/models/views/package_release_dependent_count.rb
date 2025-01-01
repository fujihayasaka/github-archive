module Views
  class PackageReleaseDependentCount < ApplicationRecord
    self.table_name = "dg_package_release_dependent_counts"

    def self.rebuild_for(*owner_ids)
      owner_ids.each do |owner_id|
        Instrument.time_dist("views.owner_package_release_count.dist", owner_id: owner_id) do
          cumulative_counts = {}

          ActiveRecord::Base.connected_to(role: :reading) do
            Manifest.not_superseded.joins(:repository).merge(Repository.where(github_owner_id: owner_id)).in_batches(of: 500) do |batch|
              results = counts_for_manifests(batch.pluck(:id))
              results.each do |result|
                cumulative_counts[result.id] ||= 0
                cumulative_counts[result.id] += result.count
              end
            end
          end

          ActiveRecord::Base.connected_to(role: :writing) do
            cumulative_counts
              .map do |id, count|
                new(github_owner_id: owner_id, package_release_id: id, count: count)
              end
              .each_slice(100) do |slice|
                DependencyGraph.throttler.throttle(:"dependency-graph") do
                  import(slice, on_duplicate_key_update: [:updated_at, :count])
                end
              end
          end

          clear_orphan_counts(owner_id, cumulative_counts.keys)
        end
      end
    end

    def self.counts_for_manifests(manifest_ids)
      if DependencyGraph.use_normalized_tables?
        return normalized_counts_for_manifests(manifest_ids)
      end

      Manifest
        .where(id: manifest_ids)
        .select("dg_package_versions.id, COUNT(DISTINCT dg_manifest_dependencies.manifest_id) as count")
        .joins("INNER JOIN dg_manifest_dependencies USE INDEX (manifest_dep_spec_package_name_reqs)
          ON dg_manifest_dependencies.manifest_id = dg_manifests.id
          AND dg_manifest_dependencies.last_seen_at_revision = dg_manifests.revision
          AND dg_manifest_dependencies.requirements LIKE '= %'
        ")
        .joins("INNER JOIN dg_package_versions
          ON dg_package_versions.package_manager = dg_manifest_dependencies.package_manager
          AND dg_package_versions.package_name = dg_manifest_dependencies.package_name
          AND dg_package_versions.name =
            IF(dg_manifest_dependencies.package_manager = 7,
              CONCAT('v', TRIM(Leading '= ' FROM dg_manifest_dependencies.requirements)),
              TRIM(Leading '= ' FROM dg_manifest_dependencies.requirements)
            )
          ")
        .group("dg_package_versions.id")
    end

    def self.normalized_counts_for_manifests(manifest_ids)
      Manifest
        .where(id: manifest_ids)
        .select("dg_package_versions.id, COUNT(DISTINCT dg_manifest_entries.manifest_id) as count")
        .joins("INNER JOIN dg_manifest_entries
          ON dg_manifest_entries.manifest_id = dg_manifests.id
          AND dg_manifest_entries.last_seen_at_revision = dg_manifests.revision")
        .joins("INNER JOIN dg_manifest_package_versions
          ON dg_manifest_package_versions.id = dg_manifest_entries.manifest_package_version_id
          AND dg_manifest_package_versions.requirements LIKE '= %'")
        .joins("INNER JOIN dg_manifest_packages
          ON dg_manifest_packages.id = dg_manifest_package_versions.manifest_package_id")
        .joins("INNER JOIN dg_package_versions
          ON dg_package_versions.package_manager = dg_manifest_packages.package_manager
          AND dg_package_versions.package_name = dg_manifest_packages.package_name
          AND dg_package_versions.name =
            IF(dg_manifest_packages.package_manager = 7,
              CONCAT('v', TRIM(Leading '= ' FROM dg_manifest_package_versions.requirements)),
              TRIM(Leading '= ' FROM dg_manifest_package_versions.requirements)
            )
          ")
        .group("dg_package_versions.id")
    end

    def self.clear_orphan_counts(owner_id, present_releases_ids)
      ActiveRecord::Base.connected_to(role: :reading) do
        dependent_counts_release_ids = self.where(github_owner_id: owner_id).pluck(:package_release_id)

        # Remove the "active" package release counts from the group, remaining counts are orphans
        older_revisions_package_releases = (dependent_counts_release_ids - present_releases_ids)

        older_revisions_package_releases.in_groups_of(100, false) do |group_release_ids|
          orphan_counts_ids = self.where(github_owner_id: owner_id, package_release_id: group_release_ids).pluck(:id)

          ActiveRecord::Base.connected_to(role: :writing) do
            self.delete(orphan_counts_ids)
          end
        end
      end
    end
  end
end
