# typed: true
# frozen_string_literal: true

require "json"

class AssetBundles
  def self.get(bundler: :webpack)
    return @@cache[bundler] if defined?(@@cache) && @@cache&.dig(bundler)

    @@cache ||= {} # make sure @@cache is initialized
    @@cache[bundler] = self.new(bundler: bundler)
    @@cache[bundler]
  end

  def self.cache_clear
    @@cache = {}
  end

  class CachePerRequest
    def initialize(app)
      @app = app
    end

    def call(env)
      AssetBundles::cache_clear
      @app.call(env)
    end
  end

  attr_reader :bundler
  def initialize(assets: "public/assets", package: "package.json", bundler: :webpack)
    @package_path = Rails.root.join(package)
    assets = Rails.root.join(assets)
    @js_manifest_file_name = "manifest.#{bundler == :webpack ? "" : "#{bundler}."}json"
    @js_manifest_path = assets.join(@js_manifest_file_name).to_s
    @css_manifest_path = assets.join("manifest.css.json").to_s
    @bundler = bundler
  end

  def manifest(file)
    return js_data if file.ends_with?(".module.css")
    return css_data if file.ends_with?(".css", ".css.js")

    js_data
  end

  def fetch_manifest_http(manifest_url)
    manifest_uri = URI.parse(manifest_url)
    http = Net::HTTP.new(manifest_uri.host, manifest_uri.port)
    http.open_timeout = 60
    http.read_timeout = 60

    http.request(Net::HTTP::Get.new(manifest_uri)).body
  end

  def js_data
    return @js_data if defined? @js_data

    manifest = if GitHub.webpack_dev_server_enabled?
      # When using webpack-dev-server, the manifest is fetched via http instead of writing it to the disk
      fetch_manifest_http("http://localhost:3011/#{@js_manifest_file_name}")
    elsif File.exist?(@js_manifest_path)
      File.read(@js_manifest_path)
    else
      "{}"
    end

    @js_data = JSON.parse(manifest)
  end

  def css_data
    return @css_data if defined? @css_data

    manifest = if GitHub.webpack_dev_server_enabled?
      # When using webpack-dev-server, the manifest is fetched via http instead of writing it to the disk
      fetch_manifest_http("http://localhost:3012/manifest.css.json")
    elsif File.exist?(@css_manifest_path)
      File.read(@css_manifest_path)
    else
      "{}"
    end

    @css_data = JSON.parse(manifest)
  end

  # Finds the top-level script bundles produced by Rollup during
  # compilation. Chunk files, output from Rollup's code splitting algorithm,
  # are not listed here.
  #
  # Examples
  #
  #   AssetBundles.get.bundles
  #   # => ["github.js", "projects.js", ...]
  #
  # Returns an Array<String> of bundle names.
  def bundles
    @bundles ||= js_data.keys.select do |bundle|
      !bundle.starts_with?("chunk-") &&
      (bundle.ends_with?(".js") || bundle.ends_with?(".css"))
    end.freeze
  end

  # Lists all the bundles required to load dotcom's JS, which are:
  #
  #  - environment.js
  #  - behaviors.js
  #  - development.js
  #
  # The bundles are listed in the order they should be loaded.
  #
  # Returns Array<String> of required bundle names.
  def required_bundles
    return @required_bundles if defined?(@required_bundles)

    @required_bundles = @bundler != :webpack ? [] : ["wp-runtime.js"]
    @required_bundles += ["environment.js", "github-elements.js", "element-registry.js", "behaviors.js", "notifications-global.js"]
    @required_bundles << "development.js" if Rails.env.development?
    @required_bundles
  end

  # Returns true if the bundle's short name exists in the manifest file.
  #
  # name - The bundle's short name (e.g. github.js).
  #
  # Examples
  #
  #   assets = AssetBundles.get
  #   assets.bundle_exists?("github.js")
  #   # => true
  #   assets.bundle_exists?("github-deadbeef.js")
  #   # => false
  #
  # Returns true for bundle names in `manifest.json`.
  def bundle_exists?(name)
    manifest(name).key?(name)
  end

  # Expands the script bundle's short name into a fingerprinted file name
  # to be served in production. The fingerprint is a content addressable hash
  # of the file's content.
  #
  # source - The bundle's short name (e.g. github.js).
  #
  # Examples
  #
  #   AssetBundles.get.expand_bundle_name("github.js")
  #   # => "github-deadbeef.js"
  #
  # Returns a fingerprinted file name.
  def expand_bundle_name(source)
    expand_bundle(source)["src"]
  end

  # Strips the path and fingerprint from a file name to resolve it to the
  # bundle's short name.
  #
  # source - The bundle's fingerprinted name (e.g. /assets/github-deadbeef.js).
  #
  # Examples
  #
  #   AssetBundles.get.bare_bundle_name("/assets/github-deadbeef.js")
  #   # => "github.js"
  #
  # Returns a bundle's short name.
  def bare_bundle_name(source)
    File.basename(source).sub(/\A([\w(\-|\.)]+)-[a-f0-9]+(\.\w+)\Z/, '\1\2')
  end

  # Returns the script bundle's full URL on the CDN.
  #
  # source - A String bundle short name to expand (e.g. github.js).
  # asset_host_url - A String URL to use as the asset host.
  #
  # Examples
  #
  #   AssetBundles.get.bundle_url("github.js")
  #   # => "https://github.githubassets.com/assets/github-deadbeef.js"
  #   # => "http://github.localhost/webpack/github.js"
  #
  # Returns a URL string.
  def bundle_url(source, asset_host_url: GitHub.asset_host_url, expand: true)
    assets_path = GitHub.webpack_dev_server_enabled? ? "webpack" : "assets"
    filename = expand ? expand_bundle_name(source) : source
    File.join(asset_host_url, assets_path, filename)
  end

  # Expands the bundle's required files to load.
  #
  # source - The bundle's short name (e.g. github.js).
  #
  # Examples
  #
  #   AssetBundles.get.expand_bundle_files("github.js")
  #   # => [{ "src" => "github-deadbeef.js" }, { "css_src" => "github-deadbeef.module.css" }]
  #
  # Returns an array of files, each with a `src` key.
  def expand_bundle_files(source)
    bundle = expand_bundle(source)

    return [bundle.symbolize_keys] unless bundle["files"]

    js_bundles = bundle["files"].map do |file|
      {
        src: file
      }
    end

    css_bundles = (bundle["cssFiles"] || []).map do |file|
      {
        css_src: file
      }
    end

    js_bundles + css_bundles
  end

  # Expands the bundle's information.
  #
  # source - The bundle's short name (e.g. github.js).
  #
  # Examples
  #
  #   AssetBundles.get.expand_bundle("github.js")
  #   # => { "src" => "github-deadbeef.js" }
  def expand_bundle(source)
    manifest(source).fetch(source)
  end

  def package
    @package ||= JSON.parse(File.read(@package_path))
  end
end
