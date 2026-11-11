class PackageRelease < ApplicationRecord
  include WhereIn

  PARTITION_SIZE = 250

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

  before_save :truncate_license_to_db_limit

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
    original_licenses = Array(license).map { |l| untransform_license(l) || l }
    where(license: original_licenses)
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

  # Scancode LicenseRefs that should be removed from license expressions
  SCANCODE_JUNK_LICENSE_REFS = [
    "LicenseRef-scancode-unknown-license-reference",
    "LicenseRef-scancode-free-unknown",
    "LicenseRef-scancode-generic-cla",
    "LicenseRef-scancode-other-permissive",
    "LicenseRef-scancode-warranty-disclaimer",
  ].freeze

  # Reverses the simple license transformations, converting "LicenseRef-github-*" format back to original values
  # ("OTHER", "NONE", "NOASSERTION"). This returns the value back to what is stored in the database.
  # Note that this does NOT reverse other transformations (e.g., invalid SPDX to LicenseRef-bad-*), so
  # it's possible the database values may not match.
  def self.untransform_license(license)
    return nil if license.nil?

    license
    .gsub(/\bLicenseRef-github-OTHER\b/, "OTHER")
    .gsub(/\bLicenseRef-github-NOASSERTION\b/, "NOASSERTION")
    .gsub(/\bLicenseRef-github-NONE\b/, "NONE")
  end

  # Removes scancode junk LicenseRefs from a license expression.
  # Only removes them if they are ANDed with other licenses (e.g., "MIT AND LicenseRef-scancode-junk" -> "MIT")
  # If the junk LicenseRef is the only license, it's left alone.
  def self.remove_scancode_junk(license)
    return nil if license.nil?

    result = license.dup

    # Remove each junk license ref individually
    SCANCODE_JUNK_LICENSE_REFS.each do |junk_ref|
      # Remove " AND junk" pattern at the end or followed by space
      result = result.gsub(/\s+AND\s+#{Regexp.escape(junk_ref)}(?=\s|$)/, "")
      # Remove "junk AND " pattern at the beginning or preceded by space
      result = result.gsub(/(?<=^|\s)#{Regexp.escape(junk_ref)}\s+AND\s+/, "")
    end

    # Clean up any resulting double spaces
    result = result.gsub(/\s+/, " ").strip

    # If we removed everything, return the original (don't want empty string)
    result.empty? ? license : result
  end

  # Transforms completely invalid SPDX license strings into valid LicenseRef format.
  # Rules:
  # - Start with "LicenseRef-bad-"
  # - Change spaces to "-"
  # - Change all alpha characters to lower case
  # - Numbers, hyphens, and periods are allowed unchanged
  # - Other characters are dropped
  # - Length limited to 255 characters
  def self.transform_invalid_to_license_ref(license)
    return nil if license.nil? || license.strip.empty?

    # Check if it's already valid SPDX
    return license if valid_spdx?(license)

    # Transform to LicenseRef-bad-* format using gsub for efficiency
    transformed = "LicenseRef-bad-" + license.gsub(/[^a-zA-Z0-9.\- ]/) { |char|
      char == ' ' ? '-' : ''
    }.gsub(/[A-Z]/, &:downcase).gsub(/\s+/, '-')

    # Remove leading/trailing hyphens and consecutive hyphens
    transformed = transformed.gsub(/-+/, '-').gsub(/-+$/, '')

    # Limit to 255 characters (DB column size)
    transformed[0...255]
  end

  # Checks if a license string is a valid SPDX expression
  def self.valid_spdx?(license)
    return false if license.nil? || license.empty?
    Spdx.valid?(license)
  rescue StandardError
    # If there's any error checking validity, assume it's invalid
    false
  end

  # Transforms non-standard license values ("OTHER", "NONE", "NOASSERTION") to "LicenseRef-github-*" format
  # without modifying their raw database values. This will make these licenses valid for our SPDX parser.
  # Uses word boundaries (\b) to avoid transforming substrings (e.g., "ANOTHER" remains unchanged),
  # but will transform these keywords even when followed by non-word characters (e.g., "OTHER-X" becomes "LicenseRef-github-OTHER-X").
  #
  # Note: Memoization is safe here because:
  # - repository_id doesn't change for a PackageRelease instance
  # - Feature flag state is stable during a request/instance lifetime
  # - New instances are created for each request, so stale flags aren't an issue
  # - The underlying license value doesn't change because we don't modify licenses in the database currently
  def license
    @transformed_license ||= begin
      original_license = super
      return nil if original_license.nil?

      # Apply standard OTHER/NONE/NOASSERTION transformation
      transformed = original_license.gsub(/(^|[ \(])(other|noassertion|none)($|[ \)])/i) do
        "#{$1}LicenseRef-github-#{$2.upcase}#{$3}"
      end

      # Apply new transformations if feature flag is enabled
      if should_apply_license_fixes?
        # First, remove scancode junk
        transformed = PackageRelease.remove_scancode_junk(transformed)

        # Then, transform invalid SPDX to LicenseRef-bad-* format
        transformed = PackageRelease.transform_invalid_to_license_ref(transformed)
      end

      transformed
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

  private

  # Check if the license fix feature flag is enabled for this package's repository
  def should_apply_license_fixes?
    return false unless repository_id.present?

    repo_actor = FeatureFlags::Actor::Repository.new(repository_id)
    DependencyGraph.flipper[:dependency_graph_license_fixes].enabled?(repo_actor)
  rescue StandardError => e
    # If there's any error checking the feature flag, default to disabled
    DependencyGraph.logger.warn("Error checking license fixes feature flag: #{e.message}")
    false
  end

  # Truncates the license string to 255 characters before saving to the database to avoid errors
  # with overly long license strings.
  def truncate_license_to_db_limit
    return unless should_apply_license_fixes?
    return unless license_changed?
    return if self[:license].nil?
    return if self[:license].length <= 255

    # Only truncates, no transformations
    self[:license] = self[:license][0...255]
  end

  def vulnerabilities_count
    vulnerability_count_view&.total_count || 0
  end

  def self.find_metadata_by_batch_coords(batched_coords)
    batched_coords.uniq.each_slice(PARTITION_SIZE).flat_map do |slice|
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
