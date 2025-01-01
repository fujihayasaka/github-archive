# typed: strict
# frozen_string_literal: true

class StaticAssetPaths
  extend T::Sig

  MANIFEST_PATH = T.let(Rails.root.join("public", "assets", "manifest.static.json").to_s.freeze, String)
  @@manifest = T.let(nil, T.nilable(T::Hash[String, String]))

  sig { returns(T::Hash[String, String]) }
  def self.manifest
    return @@manifest unless @@manifest.nil?

    manifest = if File.exist?(MANIFEST_PATH)
      File.read(MANIFEST_PATH)
    else
      "{}"
    end

    @@manifest = JSON.parse(manifest)
  end

  # Wrapper on GitHub.asset_host_url. We can use this to feature flag the host URL.
  sig { returns(String) }
  def self.asset_host_url
    GitHub.asset_host_url.presence || GitHub.url
  end

  # Wrapper on GitHub.mailer_asset_host_url. We can use this to feature flag the host URL.
  sig { returns(String) }
  def self.mailer_asset_host_url
    GitHub.mailer_asset_host_url
  end

  sig { params(path: String, mailer: T::Boolean).returns(String) }
  def self.static_asset_path(path, mailer: false)
    base = mailer ? mailer_asset_host_url : asset_host_url

    File.join(base, fingerprinted_asset(path))
  end

  sig { params(path: String).returns(String) }
  def self.fingerprinted_asset(path)
    path = T.must(path.start_with?("/") ? path[1..-1] : path)

    # fallback to original path if manifest doesn't support the asset
    if asset = manifest[path]
      "/#{File.join("assets", asset)}"
    else
      "/#{path}"
    end
  end
end
