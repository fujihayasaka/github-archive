# typed: true
# frozen_string_literal: true

require "json"

class AssetBundles
  class AssetVerifyError < StandardError; end

  def self.get(bundler: :webpack, ui_manifest_sha: nil)
    return @@cache[ui_manifest_sha][bundler] if defined?(@@cache) && @@cache&.dig(ui_manifest_sha, bundler)

    @@cache ||= {} # make sure @@cache is initialized
    @@cache[ui_manifest_sha] ||= {}
    @@cache[ui_manifest_sha][bundler] = self.new(bundler: bundler, ui_manifest_sha: ui_manifest_sha)
    @@cache[ui_manifest_sha][bundler]
  end

  def self.cache_clear
    @@cache = {}
  end

  def self.verify_assets!
    get.verify!
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

  attr_reader :bundler, :ui_manifest_sha
  def initialize(assets: "public/assets", package: "package.json", bundler: :webpack, ui_manifest_sha: nil)
    bundler = :vite if GitHub.vite_dev_server_enabled?
    @package_path = Rails.root.join(package)
    assets = Rails.root.join(assets)
    @js_manifest_file_name = "manifest.#{bundler == :webpack ? "" : "#{bundler}."}json"
    @js_manifest_path = assets.join(@js_manifest_file_name).to_s
    @css_manifest_file_name = "manifest.#{bundler == :vite ? "vite." : "css."}json"
    @css_manifest_path = assets.join(@css_manifest_file_name).to_s
    @ui_manifest_sha = ui_manifest_sha
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
    elsif GitHub.vite_dev_server_enabled?
      # When using vite, the manifest is fetched via http instead of writing it to the disk
      fetch_manifest_http("http://localhost:3013/vite/#{@js_manifest_file_name}")
    elsif File.exist?(@js_manifest_path)
      File.read(@js_manifest_path)
    else
      "{}"
    end

    @js_data = {
      **JSON.parse(manifest).with_indifferent_access,
      **ui_manifest
    }

    @js_data
  end

  def css_data
    return @css_data if defined? @css_data

    manifest = if GitHub.webpack_dev_server_enabled?
      # When using webpack-dev-server, the manifest is fetched via http instead of writing it to the disk
      fetch_manifest_http("http://localhost:3012/manifest.css.json")
    elsif GitHub.vite_dev_server_enabled?
      # When using vite, the manifest is fetched via http instead of writing it to the disk
      fetch_manifest_http("http://localhost:3013/vite/#{@css_manifest_file_name}")
    elsif File.exist?(@css_manifest_path)
      File.read(@css_manifest_path)
    else
      "{}"
    end

    @css_data = JSON.parse(manifest)
  end

  def ui_manifest
    return {} unless @ui_manifest_sha.present?
    return @ui_manifest if defined?(@ui_manifest)

    @ui_manifest = GitHubUI::ManifestStore.get_manifest(git_sha: @ui_manifest_sha).with_indifferent_access[@bundler]
  rescue GitHubUI::ManifestStore::MissingError => e
    GitHub.logger.warn("Missing UI manifest", {
      "code.namespace": self.class.name,
      "code.function": __method__,
      "exception.message": e.message
    })

    {}
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

  # Lists all the bundles required to load dotcom's CSS, which are:
  #
  # - primer-primitives.css
  # - primer.css
  # - global.css
  # - github.css
  #
  # The bundles are listed in the order they should be loaded.
  #
  # Returns Array<String> of required bundle names.
  def required_stylesheet_bundles
    return @required_stylesheet_bundles if defined?(@required_stylesheet_bundles)

    @required_stylesheet_bundles = %w[primer-primitives primer global github]
    @required_stylesheet_bundles << "development" if Rails.env.development?
    @required_stylesheet_bundles
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
    assets_path = if GitHub.webpack_dev_server_enabled?
      "webpack"
    elsif GitHub.vite_dev_server_enabled?
      "vite"
    else
      "assets"
    end
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

    return [bundle.symbolize_keys] unless bundle["files"] || bundle["cssFiles"]

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

  def verify!
    css_bundles = required_stylesheet_bundles
    js_bundles = required_bundles

    all_assets_valid = (css_bundles + js_bundles).map do |bundle|
      result = expand_bundle_files(bundle)
      File.exist?(@package_path.join(result[:src]))
    end.all?(true)
    raise AssetVerifyError.new("Asset verification failed") unless all_assets_valid
  rescue KeyError
    raise AssetVerifyError.new("Asset verification failed")
  end
end
