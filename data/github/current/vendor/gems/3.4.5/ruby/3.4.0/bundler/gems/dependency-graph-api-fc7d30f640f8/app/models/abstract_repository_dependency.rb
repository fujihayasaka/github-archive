class AbstractRepositoryDependency < ApplicationRecord
  self.table_name = "dg_abstract_repository_dependencies"

  extend AbstractDependencyScoping
  extend IndexScoping

  belongs_to :repository

  scope :with_public_repo, -> { joins(:repository).merge(Repository.public_repos) }
  scope :for_github_repository, ->(github_repo_id) do
    joins(:repository).merge(Repository.with_github_repository_id(github_repo_id))
  end
  scope :repository_owned_by, -> (owner) { joins(:repository).merge(Repository.owned_by(owner)) }
  scope :join_packages, -> do
    pkg_arel = Package.arel_table
    join_conditions = pkg_arel[:package_manager].eq(arel_table[:package_manager])
      .and(pkg_arel[:name].eq(arel_table[:package_name]))
    joins(arel_table.join(pkg_arel).on(join_conditions).join_sources)
  end
  scope :direct_only, -> do
    pkg_arel = Package.arel_table
    abstract_deps_arel = AbstractPackageDependency.arel_table
    join_conditions = abstract_deps_arel[:dependent_id].eq(pkg_arel[:id])
    join_packages.joins(arel_table.join(abstract_deps_arel).on(join_conditions).join_sources)
  end
  scope :with_package_manager, -> (pkg_manager) { where(package_manager: pkg_manager) }
  scope :sort_by_package_manager, -> do
    when_clauses = Types::PackageManager.map do |package_manager|
      condition = arel_table[:package_manager].eq(package_manager.id).to_sql
      quoted_name = connection.quote(package_manager.name)
      "WHEN #{condition} THEN #{quoted_name}"
    end
    order(Arel.sql("CASE #{when_clauses.join(" ")} END"))
  end
  scope :sort_by_package_name, -> { join_packages.merge(Package.alphabetical) }
  scope :sort_by_recently_published, -> do
    join_packages.merge(Package.order(last_published_at: :desc))
  end
  scope :sort_by_least_recently_published, -> do
    join_packages.merge(Package.order(last_published_at: :asc))
  end

  restrict_type_of :package_manager, to: Types::PackageManager

  delegate :github_repository_id, :github_owner_id, to: :repository

  def self.recently_added_first
    order(id: :desc)
  end

  # Returns all of the packages mapped to a AbstractRepositoryDependency collection
  def self.packages
    Package.joins("INNER JOIN #{self.table_name} ON #{Package.table_name}.package_manager = #{self.table_name}.package_manager AND #{Package.table_name}.name = #{self.table_name}.package_name").merge(all)
  end

  def self.delete_orphans(package_name, package_manager)
    package_manager = Types::PackageManager.coerce(package_manager)

    to_delete = []
    ActiveRecord::Base.connected_to(role: :analytics) do
      repo_ids = self.where(package_manager: package_manager, package_name: package_name).pluck(:repository_id)
      repo_ids.each do |repo_id|
        should_delete = if DependencyGraph.use_normalized_tables?
                          any_orphaned_manifest_entries?(repo_id, package_manager, package_name)
                        else
                          any_orphaned_manifest_dependencies?(repo_id, package_manager, package_name)
                        end

        to_delete << repo_id if should_delete
      end
    end

    ActiveRecord::Base.connected_to(role: :writing) do
      self.where(repository_id: to_delete, package_manager: package_manager, package_name: package_name).in_batches.destroy_all
    end

    to_delete.count
  end

  def self.any_orphaned_manifest_dependencies?(repo_id, package_manager, package_name)
    deps = ManifestDependency
      .joins(:manifest)
      .where(dg_manifests: {
          repository_id: repo_id,
          package_manager: package_manager.to_i
        },
        dg_manifest_dependencies: { package_name: package_name }
      )

    return deps.empty? || !deps.any? { |dependency| dependency.last_seen_at_revision == dependency.manifest.revision  }
  end

  def self.any_orphaned_manifest_entries?(repo_id, package_manager, package_name)
    entries = ManifestEntry
      .joins(:manifest, manifest_package_version: :manifest_package)
      .where(dg_manifests: {
          repository_id: repo_id,
          package_manager: package_manager.to_i
        },
        dg_manifest_packages: { package_name: package_name }
      )

    return entries.empty? || !entries.any? { |dependency| dependency.last_seen_at_revision == dependency.manifest.revision  }
  end
end
