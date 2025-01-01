# typed: true
# frozen_string_literal: true

require "asset_bundles"

# `AssetBundlesHelper` is a wrapper around `AssetBundles` that provides information
# about the `current_user` and feature flags. It's only responsibility is calling
# `AssetBundles` with the correct `bundler` parameter.
class AssetBundlesHelper
  attr_reader :asset_bundles
  def initialize(current_user = nil)
    @current_user = current_user
    # webpack is the default bundler, but we can use current_user + feature flags to select a different bundler here
    @asset_bundles = AssetBundles.get(bundler: bundler)
  end

  def self.bundler_flags
    @@bundler_flags ||= begin
      JSON.parse(File.read(Rails.root.join("ui/packages/webpack/bundler-flags.json"))).with_indifferent_access
    rescue JSON::ParserError, Errno::ENOENT
      {}
    end
  end

  def self.feature_flags
    bundler_flags.values.map { |v| v[:flag].to_sym }
  end

  delegate :bare_bundle_name,
           :bundle_exists?,
           :bundle_url,
           :dynamic_chunk?,
           :expand_bundle_files,
           :expand_bundle_name,
           :expand_bundle,
           :integrity,
           :required_bundles,
           to: :asset_bundles

  private

  def bundler
    bundler_flags.keys.each do |key|
      return bundler_flags[key][:bundler].to_sym if bundler_flag_enabled?(bundler_flags[key][:flag])
    end

    :webpack
  end

  def bundler_flag_enabled?(flag)
    ENV["BUNDLER_FLAG"] == flag || (Rails.env.production? && (GitHub.flipper[flag.to_sym].enabled?(@current_user) || GitHub.flipper[flag.to_sym].enabled?))
  end

  def bundler_flags
    self.class.bundler_flags
  end
end
