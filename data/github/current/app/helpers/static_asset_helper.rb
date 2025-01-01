# typed: strict
# frozen_string_literal: true

require "static_asset_paths"

module StaticAssetHelper
  include ActionView::Helpers::AssetUrlHelper

  delegate :asset_host_url, :mailer_asset_host_url, to: StaticAssetPaths

  sig { params(source: String, options: T.untyped).returns(String) }
  def compute_asset_path(source, options = {})
    StaticAssetPaths.fingerprinted_asset(public_compute_asset_path(source, options))
  end

  # Returns full path to static asset.
  #
  # @param path [String] The asset relative path.
  #
  # @return [String] The full asset path.
  sig { params(path: String).returns(String) }
  def static_asset_path(path)
    StaticAssetPaths.static_asset_path(path)
  end

  # Returns full path to static asset for mailers.
  #
  # @param path [String] The asset relative path.
  #
  # @return [String] The full asset path.
  sig { params(path: String).returns(String) }
  def mailer_static_asset_path(path)
    StaticAssetPaths.static_asset_path(path, mailer: true)
  end

  sig { params(name: String).returns(String) }
  def web_worker_url(name)
    asset_bundle = AssetBundles.new
    bundle_name = asset_bundle.expand_bundle_name(name)
    if GitHub.enterprise? && Rails.env.production? # rubocop:disable GitHub/DoNotBranchOnRailsEnv
      # In GHES we have some customers who rely on a proxy which requires a cookie. These get stripped
      # when accessing assets cross-origin, so we serve worker scripts directly from the main origin.
      asset_bundle.bundle_url(
        bundle_name,
        expand: false, # Already expanded above
        asset_host_url: "" # Use a relative path instead of separate asset host
      )
    else
      Rails.application.routes.url_helpers.web_worker_path(bundle_name)
    end
  end
end
