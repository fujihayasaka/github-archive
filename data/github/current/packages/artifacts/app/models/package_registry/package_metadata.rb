# typed: true
# frozen_string_literal: true

module PackageRegistry
  class PackageMetadata
    attr_reader :package, :package_versions, :total_version_count, :total_tagged_versions_count, :total_untagged_versions_count

    attr_accessor :latest_version, :total_download_count, :package_type_for_ui

    delegate :id, :owner, :package_type, :name, :repository, :visibility, :repo_id, :deleted_at, :created_at, :author_type, :author, :original_name, :package_type_for_actor, :latest_non_signature_version, :is_actions_package?, to: :package

    def initialize(resp, package_type: nil)
      @package = PackageRegistry::Package.new(resp.package, package_type: package_type)
      @package.latest_version = PackageRegistry::PackageVersion.new(resp.latest_version) if resp&.latest_version
      @latest_version = PackageRegistry::PackageVersion.new(resp.latest_version) if resp&.latest_version
      @total_version_count = resp.try(:total_version_count) || 0
      @total_untagged_versions_count = resp.try(:total_untagged_versions_count) || 0
      @total_tagged_versions_count = resp.try(:total_tagged_versions_count) || 0
      versions = resp.try(:versions) || []
      if @package.ecosystem == :container
        # The #uniq is temporary pending https://github.com/github/c2c-package-registry/issues/2302
        @package_versions = versions.map { |v| PackageRegistry::PackageVersion.new(v) }.uniq { |v| v.metadata.manifest.digest }
      else
        @package_versions = versions.map { |v| PackageRegistry::PackageVersion.new(v) }
      end
    end

    def target_for_conditional_access
      owner
    end

    def migrated?
      false
    end

  end
end
