# typed: true
# frozen_string_literal: true

module PackageRegistry
  class PackageSummary
    attr_reader :package, :package_versions, :latest_version, :total_download_count, :total_version_count

    delegate :id, :owner, :package_type, :name, :repository, :visibility, :repo_id, :deleted_at, :original_name, to: :package

    def initialize(resp)
      @package = PackageRegistry::Package.new(resp.package)
      @latest_version = resp.latest_version.nil? ? nil : PackageRegistry::PackageVersion.new(resp&.latest_version)
      @total_download_count = resp.try(:total_download_count) || 0
      @total_version_count = resp.try(:total_version_count) || 0
    end

  end
end
