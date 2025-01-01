# typed: strict
# frozen_string_literal: true

require "static_asset_paths"

module StaticAssetHelper
  include ActionView::Helpers::AssetUrlHelper
  extend T::Sig

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
end
