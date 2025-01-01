require "dependency_graph/manifest_dependency_replicator"

class ManifestDependency < ApplicationRecord
  include DependencyGraph::Tracing

  self.table_name = "dg_manifest_dependencies"
  # exact_version is deprecated and will be removed in the future, c.f. https://github.com/github/dependency-graph/issues/1471
  self.ignored_columns = [:exact_version]

  include Dependency
  include WhereIn
  extend IndexScoping

  belongs_to :manifest

  restrict_type_of :scope, to: Types::Scope
  restrict_type_of :package_manager, to: Types::PackageManager

  delegate :overlap?, :contain?, to: :requirement_set
  delegate :manifest_type, :repository_id, :github_repository_id, to: :manifest
  delegate :path, :filename, :vendored?, to: :manifest, prefix: true

  validates :requirements, length: { maximum: 255 }

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

  after_save :replicate_to_manifest_entry

  # ManifestDependency records are ordered by requirements ascending (primary)
  # then ID ascending (secondary).
  #
  # See: API::ConnectionWrappers::VersionRangeDependentsWrapper
  def self.after(cursor)
    requirements, id = cursor

    # ID and requirements are both non-null columns. A valid cursor will
    # provide truthy values for both.
    return all unless id && requirements

    where(
      # Requirements are equal and ID acts as the tie-breaker...
      arel_table[:requirements].eq(requirements).and(arel_table[:id].gt(id))
        # ...or requirements are greater than the cursor and ID is irrelevant.
        .or(arel_table[:requirements].gt(requirements))
    )
  end

  # ManifestDependency records are ordered by requirements ascending (primary)
  # then ID ascending (secondary).
  #
  # See: API::ConnectionWrappers::VersionRangeDependentsWrapper
  def self.before(cursor)
    requirements, id = cursor

    # ID and requirements are both non-null columns. A valid cursor will
    # provide truthy values for both.
    return all unless id && requirements

    where(
      # Requirements are equal and ID acts as the tie-breaker...
      arel_table[:requirements].eq(requirements).and(arel_table[:id].lt(id))
        # ...or requirements are less than the cursor and ID is irrelevant.
        .or(arel_table[:requirements].lt(requirements))
    )
  end

  def self.as_of_revision(revision)
    where(last_seen_at_revision: revision)
  end

  def supersedes?(other)
    manifest_type.supersedes?(other.manifest_type)
  end

  def current?
    last_seen_at_revision == manifest.revision
  end

  def requirement_set
    @requirement_set ||= Versioning::RequirementSet
      .deserialize(requirements, allow_named_versions: Types::PackageManager.allows_named_versions?(package_manager))
  end

  # TO-DO remove when removing deprecated packageLabel
  def package_label
    self[:package_label].presence || package_name
  end

  # The VersionRangeDependentsQuery orders its ManifestDependency results by
  # requirements ascending (primary) and ID ascending (secondary). Cursors for
  # this query must take its ordering into account.
  def to_cursor
    [requirements, id]
  end

  private

  def manifest_dependency_replicator
    @manifest_dependency_replicator ||= DependencyGraph::ManifestDependencyReplicator.new
  end

  # Replicate changes to dg_manifest_dependencies to dg_manifest_entries, dg_package_versions, and dg_packages
  trace_method :replicate_to_manifest_entry
  def replicate_to_manifest_entry
    return unless DependencyGraph.use_normalized_tables?

    # I don't expect package_manager to be nil, but this works around some tests
    package_manager = self.package_manager || manifest.package_manager
    if package_manager.nil?
      DependencyGraph.logger.info("replicate_to_manifest_entry skipping dependency with no package_manager",
                                  "gh.dependency_graph.manifest.filename", manifest.filename,
                                  "gh.repo.id", manifest.repository.github_repository_id,
                                  "gh.dependency_graph.package.name", package_name)
      return
    end

    manifest_dependency_replicator.to_manifest_entries([self])
  end
end
