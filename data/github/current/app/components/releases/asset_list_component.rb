# typed: true
# frozen_string_literal: true

module Releases
  class AssetListComponent < ApplicationComponent
    def initialize(release, current_repository, truncate: false)
      @release = release
      @current_repository = current_repository
      @package_versions = @release.package_versions.take(30).sort_by(&:id) || []
      @truncate = truncate
    end

    attr_reader :release, :current_repository, :truncate

    private

    memoize def total_asset_count
      uploaded_assets.size + source_code_assets.size
    end

    memoize def assets_to_display
      uploaded_assets_display_count = @truncate ? Release::UPLOADED_ASSET_DISPLAY_LIMIT : uploaded_assets.count
      uploaded_assets.first(uploaded_assets_display_count) + source_code_assets + release_attestation_asset
    end

    memoize def uploaded_assets
      assets = []
      release_uploaded_assets = @release.uploaded_assets || []
      release_uploaded_assets.each do |asset|
        assets << Asset.new(asset.display_name, download_release_path(release, asset), asset.created_at, asset.size, asset.digest, icon: :package)
      end

      unless GitHub.enterprise?
        @package_versions.each do |package_version|
          assets << Asset.new(
            "#{package_version.package.name} (#{package_version.package.package_type.downcase})",
            package_path(
              *package_version.package.repository.name_with_display_owner.split("/"),
              package_version.package.id,
              version: package_version.version
            ),
            package_version.created_at,
            icon: :package,
            test_selector: "release-package-version"
          )
        end
      end

      assets
    end

    memoize def source_code_assets
      if release.tagged?
        [
          Asset.new("Source code", zipball_path(@current_repository.user, @current_repository, release.tag.qualified_name), release.created_at, icon: "file-zip", extension: "(zip)"),
          Asset.new("Source code", tarball_path(@current_repository.user, @current_repository, release.tag.qualified_name), release.created_at, icon: "file-zip", extension: "(tar.gz)")
        ]
      else
        []
      end
    end

    memoize def release_attestation_asset
      if release.attestation_id
        [
          Asset.new("Release attestation", release_attestation_path(@current_repository, @release), release.created_at, icon: "verified", extension: "(json)", test_selector: "release-attestation")
        ]
      else
        []
      end
    end

    def release_attestation_path(repo, release)
      download_attestation_path(user_id: repo.owner_display_login, repository: repo.name, attestation_id: release.attestation_id)
    end

    class Asset
      def initialize(title, href, created_at, size = nil, digest = nil, icon:, extension: nil, test_selector: nil)
        @title = title
        @href = href
        @created_at = created_at
        @size = size
        @digest = digest
        @icon = icon
        @extension = extension
        @test_selector = test_selector
      end

      attr_reader :title, :href, :icon, :extension, :size, :test_selector, :digest

      def creation_timestamp
        @created_at&.utc&.iso8601
      end
    end
  end
end
