# typed: true
# frozen_string_literal: true

module Releases
  class AssetsComponent < ApplicationComponent
    renders_one :buttons
    renders_one :additional_labels

    def initialize(release, current_repository, open_assets: true, truncate_assets: true)
      @release = release
      @current_repository = current_repository
      @open_assets = open_assets
      @package_versions = @release.package_versions.take(30).sort_by(&:id) || []
      @uploaded_assets = @release.uploaded_assets || []
      @truncate_assets = truncate_assets
    end

    def render?
      total_asset_count > 0
    end

    memoize def total_asset_count
      count = @uploaded_assets.size
      unless GitHub.enterprise?
        count += @package_versions.size
      end
      if release.tagged?
        count += 2  # add in the implied source code asset count
      end
      count
    end

    attr_reader :release, :open_assets, :current_repository, :truncate_assets

    private

    def expand_assets_url
      expanded_assets_url(user_id: current_repository.owner_display_login, repository: current_repository.name, name: release.tag_name)
    end

  end
end
