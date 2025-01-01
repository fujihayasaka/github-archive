class PackageRelease < ApplicationRecord
  include WhereIn

  self.table_name = "dg_package_versions"

  scope :vulnerable, -> {
    joins(:vulnerability_count_view).where("#{Views::PackageReleaseVulnerabilitiesCount.table_name}.total_count > 0")
  }

  scope :with_severity, ->(severity) {
    joins(:vulnerability_count_view).where("#{Views::PackageReleaseVulnerabilitiesCount.table_name}.#{severity}_count > 0")
      .order("#{Views::PackageReleaseVulnerabilitiesCount.table_name}.#{severity}_count DESC")
  }

  scope :with_dependent_counts, -> {
    sql = <<~SQL
      LEFT OUTER JOIN #{Views::AbstractRepositoryDependencyCount.table_name} dependent_counts
        ON dependent_counts.package_name = #{table_name}.package_name
          AND dependent_counts.package_manager = #{table_name}.package_manager
    SQL

    joins(sql)
  }

  belongs_to :package

  # Maps to a line in this package's specification file.
  # e.g. `bundler < 2.0`
  #
  # returns ActiveRecord::Relation<PackageDependency>
  has_many :dependencies,
    foreign_key: :dependent_id,
    class_name:  "PackageDependency",
    dependent: :destroy

  has_many :dependents_count_view,
    foreign_key: :package_release_id,
    class_name: "Views::PackageReleaseDependentCount",
    dependent: :destroy

  has_one :vulnerability_count_view,
    class_name: "Views::PackageReleaseVulnerabilitiesCount",
    dependent: :destroy

  has_one :repository,
    primary_key: :repository_id,
    foreign_key: :github_repository_id

  has_many :attributions,
    class_name: "Attribution",
    foreign_key: :dg_package_versions_id,
    dependent: :destroy

  validates :version, presence: true

  restrict_type_of :package_manager, to: Types::PackageManager

  # NOTE:
  # We utilize this specific delegation in our graphql queries only, for the
  # most part.
  # `prefix: true` means you will have to call `package_github_repository_id`
  # to access the delegation
  #
  # this table has repository_id, repository_nwo, and
  # repository_id_certainty fields. We currently are not using
  # the table data anywhere in the product.
  delegate :github_repository_id, to: :package, prefix: true, allow_nil: true
  delegate :nwo, to: :repository, prefix: :repository, allow_nil: true

  alias_attribute :github_repository_id, :repository_id

  alias_attribute :version, :name

  def self.latest
    latest_first.first
  end

  # This orders the NULL encoded versions (aka NamedVersions) to be first,
  # and then semantic versions will be ordered as expected (newest to oldest)
  def self.latest_first
    order(Arel.sql("encoded IS NOT NULL, encoded DESC"))
  end

  def self.recently_updated
    order(updated_at: :desc)
  end

  def self.least_recently_updated
    order(updated_at: :asc)
  end

  def self.recently_published
    order(published_at: :desc)
  end

  def self.least_recently_published
    order(published_at: :asc)
  end

  def self.matching_license(license)
    where(license: license)
  end

  def self.published
    where(unpublished_at: nil)
  end

  def self.newer_than(release, allow_named_versions: false)
    if allow_named_versions
      selection = select { |other_release| release.parsed_version < other_release.parsed_version }.pluck(:id)
      return where(id: selection)
    end

    where("encoded > :encoded OR (encoded = :encoded AND name > :version)", {
      encoded: release.encoded,
      version: release.version,
    })
  end

  def self.matching_requirement_set(requirement_set)
    if requirement_set.exact_version
      where(version: requirement_set.exact_version)
    else
      matching_releases = select { |release| release if requirement_set.valid? && requirement_set.contain?(Versioning::RequirementSet.deserialize("= #{release.version}", allow_named_versions: requirement_set.allow_named_versions)) }
      where(id: matching_releases.map(&:id))
    end
  end

  def siblings
    PackageRelease.where(package_id: package_id)
  end

  def full_name
    [package_name, version].join(" ")
  end

  def parsed_version
    Versioning::VersionParser.parse(version, allow_named_versions: Types::PackageManager.allows_named_versions?(package_manager))
  end

  def has_revisions?
    false
  end

  def vulnerabilities_count
    vulnerability_count_view&.total_count || 0
  end

  def self.find_metadata_by_batch_coords(batched_coords)
    batched_coords.uniq.each_slice(500).flat_map do |slice|
      PackageRelease
        .with_dependent_counts
        .where_in(["dg_package_versions.package_manager", "dg_package_versions.package_name", "dg_package_versions.name"], slice.map { |coords|
          [coords[:package_manager].to_i, coords[:package_name], coords[:package_version]]
        })
        .select(:name, :package_name, :package_manager, :license, :github_repository_id, :published_at, :unpublished_at, :dependent_count)
        .to_a
    end
  end
end
