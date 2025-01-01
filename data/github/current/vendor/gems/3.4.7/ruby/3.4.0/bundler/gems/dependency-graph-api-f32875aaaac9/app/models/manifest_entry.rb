class ManifestEntry < ApplicationRecord
  include WhereIn

  self.table_name = "dg_manifest_entries"

  belongs_to :manifest
  belongs_to :manifest_package_version

  # gives us manifest_filename, manifest_path, manifest_vendored? methods
  delegate :filename, :path, :vendored?, to: :manifest, prefix: true
  delegate :repository_id, :manifest_type, :github_repository_id, to: :manifest

  delegate :package_manager, :package_name, :requirements, to: :manifest_package_version
  delegate :requirement_set, to: :manifest_package_version

  restrict_type_of :scope, to: Types::Scope

  scope :latest_revisions, -> {
    joins(:manifest).where("last_seen_at_revision = #{Manifest.table_name}.revision")
  }

  scope :without_superseded_in_repository, -> do
    superseding_cases = Types::Manifest.superseding_cases.map do |manifest_type_id, superseded_by_ids_list|
      "(dg_manifests.manifest_type = #{manifest_type_id} AND superseding_manifest.manifest_type IN (#{superseded_by_ids_list.join(", ")}))"
    end

    joins(:manifest)
      .joins("LEFT JOIN dg_manifests superseding_manifest
        ON superseding_manifest.repository_id = dg_manifests.repository_id
        AND superseding_manifest.path = dg_manifests.path
        AND (#{superseding_cases.join(" OR ")})
      ")
      .where("superseding_manifest.id IS NULL")
  end

  scope :with_package_name, ->(package_name) do
    joins(manifest_package_version: :manifest_package).where("#{ManifestPackage.table_name}.package_name = ?", package_name)
  end

  scope :with_requirements, ->(requirements) do
    joins(:manifest_package_version).where("#{ManifestPackageVersion.table_name}.requirements = ?", requirements)
  end

  # ManifestEntry records are ordered by requirements ascending (primary)
  # then ID ascending (secondary).
  #
  # See: API::ConnectionWrappers::VersionRangeDependentsWrapper
  def self.after(cursor)
    requirements, id = cursor

    # ID and requirements are both non-null columns. A valid cursor will
    # provide truthy values for both.
    return all unless id && requirements

    self.joins(:manifest_package_version)
        .where(
          # Requirements are equal and ID acts as the tie-breaker...
          Arel.sql("manifest_package_version.requirements").eq(requirements).and(arel_table[:id].gt(id))
          # ...or requirements are greater than the cursor and ID is irrelevant.
          .or(Arel.sql("manifest_package_version.requirements").gt(requirements))
        )
  end

  def self.as_of_revision(revision)
    where(last_seen_at_revision: revision)
  end

  def current?
    last_seen_at_revision == manifest.revision
  end

  def supersedes?(other)
    manifest_type.supersedes?(other.manifest_type)
  end

  # The VersionRangeDependentsQuery orders its ManifestDependency results by
  # requirements ascending (primary) and ID ascending (secondary). Cursors for
  # this query must take its ordering into account.
  def to_cursor
    [manifest_package_version.requirements, id]
  end
end
