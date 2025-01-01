class Manifest < ApplicationRecord
  self.table_name = "dg_manifests"

  extend IndexScoping

  BATCH_SIZE = 200

  belongs_to :repository, optional: true # Make validation optional because, in ManifestLoader, we initialize objects and check their validity w/o having a repository_id

  # Needs to be called before destroying dependencies since it relies on them being present
  before_destroy :decrement_package_release_dependent_counts

  before_destroy :destroy_dependencies_in_batches

  has_many :dependencies,
    class_name: "ManifestDependency",
    dependent: :destroy # covered by the `destroy_dependencies_in_batches` callback, but keeping this here to ensure cleanup

  has_many :entries,
    class_name: "ManifestEntry",
    dependent: :destroy # covered by the `destroy_dependencies_in_batches` callback, but keeping this here to ensure cleanup

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

  # We expose `vendored?` via the API. For API consumers, `vendored?`
  # specificially indicates whether the manifest is an *unsupported* vendored
  # manifest.
  alias_method :vendored?, :unsupported_vendored_manifest?

  private

  # Private: Decrements associated dependent counts for a dependency specified in manifest
  def decrement_package_release_dependent_counts
    # Only superseding manifests are considered when counting package release dependents
    if Types::Manifest.superseded.include?(self.manifest_type)
      DependencyGraph.logger.info(
        "Skipping decrement of package release dependent counts for manifest",
        "cause" => "manifest is superseded",
        "gh.repo.id" => self.repository&.github_repository_id,
        "gh.manifest.id" => self.id,
        "gh.manifest.type" => self.manifest_type)
      return
    end

    # We only proceed if the repository has a github_owner_id set with existing package release dependent counts
    github_owner_id = self.repository&.github_owner_id
    unless github_owner_id.present? && Views::PackageReleaseDependentCount.exists?(github_owner_id: github_owner_id)
      DependencyGraph.logger.info(
        "Skipping decrement of package release dependent counts for manifest",
        "cause" => "owner id is not present or no package release dependent counts exist",
        "gh.repo.id" => self.repository&.github_repository_id,
        "gh.manifest.id" => self.id)
      return
    end

    DependencyGraph.logger.info(
      "Decrementing package release dependent counts for manifest",
      "gh.owner.id" => github_owner_id,
      "gh.repo.id" => self.repository&.github_repository_id,
      "gh.manifest.id" => self.id)

    relation = if DependencyGraph.use_normalized_tables?
                 self.entries.includes(manifest_package_version: :manifest_package)
               else
                 self.dependencies
               end

    relation
      .as_of_revision(self.revision)
      .find_in_batches(batch_size: 50) do |batch|
      exact_matches = batch.filter_map do |dep|
        next unless dep.requirement_set.exact_version.present?
        [dep.package_manager.to_i, dep.package_name, dep.requirement_set.exact_version]
      end

      package_release_ids = PackageRelease
                              .where_in(%w[package_manager package_name name], exact_matches)
                              .pluck(:id)
                              .sort # sort to ensure consistent lock acquisition order

      scope = Views::PackageReleaseDependentCount
                .where(github_owner_id: github_owner_id, package_release_id: package_release_ids)

      scope.update_all("count = count - 1")
      scope.where("count <= 0").delete_all
    end
  end

  # Private: Deletes associated dependencies (and entries) in batches
  def destroy_dependencies_in_batches
    DependencyGraph.logger.info(
      "Deleting all manifest dependencies in batches",
      "gh.repo.id" => self.repository&.github_repository_id,
      "gh.manifest.id" => self.id)

    ManifestDependency
      .select(:id)
      .where(manifest_id: self.id)
      .in_batches(of: BATCH_SIZE) do |batch_of_deps|
      # Using `delete_all` here instead of `destroy_all` for efficiency sake
      # since dependencies don't have any callbacks or associations to be destroyed
      batch_of_deps.delete_all
    end

    ManifestEntry
      .select(:id)
      .where(manifest_id: self.id)
      .in_batches(of: BATCH_SIZE) do |batch_of_deps|
      # Using `delete_all` here instead of `destroy_all` for efficiency sake
      # since entries don't have any callbacks or associations to be destroyed
      batch_of_deps.delete_all
    end
  end
end
