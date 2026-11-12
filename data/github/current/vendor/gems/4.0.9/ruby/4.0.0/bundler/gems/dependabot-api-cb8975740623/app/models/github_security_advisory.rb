# frozen_string_literal: true

require "nullable_serializer"
require "github/version_range"

class GitHubSecurityAdvisory
  include ActiveModel::Model
  include ActiveModel::Validations

  class AdvisoryNotFoundError < StandardError; end
  class PackageManagerNotSupported < StandardError; end

  GHSA_ID_REGEX = /\A(?:GHSA|GHIS)(?:-[23456789cfghjmpqrvwx]{4}){3}\z/

  attr_accessor :ghsa_id, :dependency_name, :package_manager, :affected_versions, :patched_versions, :published_at,
                :github_updated_at, :withdrawn_at

  validates :dependency_name, presence: true
  validates :package_manager, inclusion: { in: PackageManagers::ALL }
  validates :ghsa_id, presence: true, format: { with: GHSA_ID_REGEX }

  # GHSA records use bundler-like notation for all version ranges so we provide these methods to access it
  # in the package manager's notation.
  def native_affected_versions
    return @native_affected_versions if defined?(@native_affected_versions)

    @native_affected_versions = affected_versions.map(&method(:github_range))
  end

  # TODO: Start returning patched_versions.map(&method(:github_range)) giving dependabot-core more information about
  # which versions are not vulnerable.
  #
  # See: https://github.com/github/dependabot-updates/issues/878
  def native_patched_versions
    []
  end

  class << self
    def fetch(package_manager, dependencies, repo_id)
      unless PackageManagers::ALL.include?(package_manager)
        raise PackageManagerNotSupported, "Package manager #{package_manager} is not supported"
      end

      ecosystem = Advisorydb.to_advisorydb_ecosystem(package_manager)
      advisorydb_input = { packages: dependencies.map { |name| { ecosystem:, name: } }, repo_id: repo_id }

      advisories = Dependabot::Application.advisorydb_client.request_advisories(advisorydb_input).advisories
      from_advisorydb_advisories(advisories, ecosystem, dependencies)
    end

    def from_advisorydb_advisories(advisories, ecosystem, dependencies)
      lowercase_dependencies = dependencies.map(&:downcase)
      # remove advisories that are not for the given ecosystem
      advisories.each do |advisory|
        advisory.vulnerable_version_ranges.select! do |range|
          range.package[:ecosystem].to_s == ecosystem.to_s &&
            lowercase_dependencies.include?(range.package[:name].downcase)
        end
      end
      filtered_advisories = advisories.reject { |advisory| advisory.vulnerable_version_ranges.empty? }
      filtered_advisories.map(&method(:from_advisorydb_advisory))
    end

    def from_advisorydb_advisory(advisory)
      new(
        ghsa_id: advisory.ghsa_id,
        package_manager: Advisorydb.to_package_manager(advisory.vulnerable_version_ranges.first.package[:ecosystem]),
        dependency_name: advisory.vulnerable_version_ranges.first.package[:name],
        affected_versions: advisory.vulnerable_version_ranges.map(&:vulnerable_version_range),
        published_at: advisory.published_at,
        github_updated_at: advisory.updated_at
      )
    end
  end

  private

  def github_range(version_range_string)
    ::GitHub::VersionRange.convert_for_dependabot(version_range_string: version_range_string,
                                                  package_manager: package_manager)
  end
end
