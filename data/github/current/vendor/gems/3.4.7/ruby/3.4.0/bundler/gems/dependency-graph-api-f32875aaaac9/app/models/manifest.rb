class Manifest < ApplicationRecord
  self.table_name = "dg_manifests"

  extend IndexScoping

  belongs_to :repository, optional: true # Make validation optional because, in ManifestLoader, we initialize objects and check their validity w/o having a repository_id

  before_destroy :decrement_package_release_dependent_counts

  has_many :dependencies,
    class_name: "ManifestDependency",
    dependent: :destroy

  has_many :entries,
    class_name: "ManifestEntry",
    dependent: :destroy

  scope :at_root, -> { where(path: nil).or(where(path: "")) }

  scope :not_superseded, -> { where.not(manifest_type: Types::Manifest.superseded) }

  # Scope Manifests to those who's paths are in subdirectories of one of the top-level directories provided.
  # E.g. `in_subdirectories(['src/', 'lib/'])` will match Manifests in `src/foo/bar` but not `foo/bar/lib`
  def self.in_subdirectories(*dirs)
    first, *rest = dirs
    dir = first.chomp("/")
    scope = where("path = ? OR path LIKE ?", dir, "#{dir}/%")

    rest.each do |dir|
      dir = dir.chomp("/")
      scope = scope.or(where("path = ? OR path LIKE ?", dir, "#{dir}/%"))
    end
    scope
  end

  # Sometimes we have orphan manifests where the repository doesn't exixt.
  # `allow_nil: true` means we will get nil for their repository id instead of an exception
  delegate :github_repository_id, to: :repository, allow_nil: true

  restrict_type_of :package_manager, to: Types::PackageManager
  restrict_type_of :manifest_type, to: Types::Manifest

  validates :path, :name, length: { maximum: 255 }

  def self.in_same_repository_as(other_manifests)
    where.not(id: other_manifests.map(&:id))
      .where(repository_id: other_manifests.map(&:repository_id))
  end

  def self.created_after(time)
    where("created_at >= ?", time.to_s)
  end

  def self.updated_after(time)
    where("created_at != updated_at")
      .where("updated_at >= ?", time.to_s)
  end

  def self.with_github_repository_id(ids)
    joins(:repository).merge(Repository.with_github_repository_id(ids))
  end

  def self.for_package_manager(package_manager)
    where(package_manager: package_manager.serialize)
  end

  def self.exclude_package_managers(package_managers)
    where.not(package_manager: package_managers.map(&:serialize))
  end

  def self.least_nested_first
    order(Arel.sql("LENGTH(REPLACE(#{table_name}.path, '^/', ''))"), :path)
  end

  def self.alphabetized
    order(:filename)
  end

  def self.with_dependencies
    where(id: ManifestDependency.select(:manifest_id))
  end

  def self.with_entries
    where(id: ManifestEntry.select(:manifest_id))
  end

  def self.of_type(types)
    where(manifest_type: types)
  end

  def has_revisions?
    true
  end

  # The manifest is vendored but not the kind of vendoring we support
  # e.g. not yet supported by project vintage
  def unsupported_vendored_manifest?
    VendorDetection.unsupported_vendored_manifest?(path, filename, manifest_type)
  end

  def full_path
    if self.path.present?
      File.join(self.path, self.filename)
    else
      self.filename
    end
  end

  def ds_arbitrary_ecosystem_enabled?(repository_id)
    if defined?(@ds_arbitrary_ecosystem_enabled)
      return @ds_arbitrary_ecosystem_enabled
    end
    @ds_arbitrary_ecosystem_enabled = DependencyGraph.flipper[:dependency_graph_snapshot_arbitrary_ecosystems].enabled?(FeatureFlags::Actor::Repository.new(repository_id))
  end

  # We expose `vendored?` via the API. For API consumers, `vendored?`
  # specificially indicates whether the manifest is an *unsupported* vendored
  # manifest.
  alias_method :vendored?, :unsupported_vendored_manifest?

  private

  # Private: Deletes associated dependent counts for a dependency specified in manifest
  def decrement_package_release_dependent_counts
    return unless Types::Manifest.superseded.exclude?(self.manifest_type)

    github_owner_id = self.repository&.github_owner_id
    return unless github_owner_id.present?

    relation = if DependencyGraph.use_normalized_tables?
                 self.entries.includes(manifest_package_version: :manifest_package)
               else
                 self.dependencies
               end

    relation
      .as_of_revision(self.revision)
      .find_in_batches(batch_size: 50) do |batch|
        package_release_ids =
          PackageRelease
            .where_in(
              ["package_manager", "package_name", "name"],
              batch.filter_map do |dep|
                if dep.requirement_set.exact_version.present?
                  [dep.package_manager.to_i, dep.package_name, dep.requirement_set.exact_version]
                end
              end
            )
            .pluck(:id)

        Views::PackageReleaseDependentCount
          .where(github_owner_id: github_owner_id, package_release_id: package_release_ids)
          .update_counters(count: -1)

        Views::PackageReleaseDependentCount
          .where(github_owner_id: github_owner_id, package_release_id: package_release_ids)
          .where("count <= 0")
          .delete_all
      end
  end
end
