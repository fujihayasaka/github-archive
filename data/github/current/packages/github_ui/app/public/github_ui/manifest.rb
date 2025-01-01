# typed: strict
# frozen_string_literal: true

module GitHubUI
  class Manifest
    Target = T.type_alias { String }
    BundlerManifest = T.type_alias { T::Hash[T.any(String, Symbol), T.untyped] }
    BundlerFlags = T.type_alias { T::Array[T::Hash[T.any(String, Symbol), String]] }
    UIManifest = T.type_alias { T::Hash[T.any(String, Symbol), T.any(String, BundlerManifest)] }

    class CurrentManifest < ActiveSupport::CurrentAttributes
      attribute :manifest
    end

    sig { params(assets: T.nilable(String)).void }
    def initialize(assets: nil)
      @ui_manifest = T.let(nil, T.nilable(UIManifest))
      @assets = T.let(assets || "public/assets", String)
      @ui_manifest_sha = T.let(ui_manifest_sha, T.nilable(String))
    end

    sig { returns(T.nilable(String)) }
    def ui_manifest_sha
      # SHA can be set in the environment
      return GitHub.ui_manifest_sha if GitHub.ui_manifest_sha.present?

      # Only proceed to read the sha from the manifest store if ui_deploys are enabled
      return unless ui_deploys_enabled?

      # Allow overriding the SHA using the context
      return GitHub.context[:ui_sha_override] if GitHub.context[:ui_sha_override].present?

      GitHubUI::ManifestStore.get_sha(target: ui_manifest_target)
    rescue GitHubUI::ManifestStore::MissingError => e
      GitHub.logger.warn("Missing UI manifest SHA", {
        "code.namespace": self.class.name,
        "code.function": __method__,
        "exception.message": e.message
      })

      nil
    end

    sig { returns(String) }
    def git_sha
      T.cast(ui_manifest["gitSha"], String)
    end

    sig { returns(UIManifest) }
    def ui_manifest
      return CurrentManifest.manifest if CurrentManifest.manifest.present?

      sha = @ui_manifest_sha

      CurrentManifest.manifest = if sha.present?
        ui_manifest_for_sha(sha).freeze
      else
        local_ui_manifest.freeze
      end
    end

    sig { returns(Target) }
    def ui_manifest_target
      is_staff = GitHub.context[:staff_request] == "true"
      is_proxima = GitHub.multi_tenant_enterprise?

      if GitHub.enterprise? || is_proxima
        "full"
      elsif is_staff || GitHub.context[:is_snek]
        "canary-0"
      elsif client_in_canary_percentile?(2) # 2% of clients
        "canary-1"
      elsif client_in_canary_percentile?(5) # 5% of clients
        "canary-2"
      else
        "full"
      end
    end

    sig { params(canary_percentage: Integer).returns(T::Boolean) }
    def client_in_canary_percentile?(canary_percentage)
      client_id = GitHub.context[:client_id]
      return false if client_id.nil? || client_id.empty?

      client_percentile_bucket = client_id.sum % 100
      client_percentile_bucket < canary_percentage
    end

    sig { params(bundler: T.any(String, Symbol)).returns(BundlerManifest) }
    def manifest_for_bundler(bundler)
      T.cast(ui_manifest[bundler], BundlerManifest)
    end

    sig { returns(BundlerManifest) }
    def relay_manifest
      GitHub.dogstats.increment("ui.gh.manifest.read_relay_manifest")
      T.cast(ui_manifest[:relay], BundlerManifest)
    end

    sig { returns(T.nilable(T::Hash[String, T.untyped])) }
    def alloy_manifest
      GitHub.dogstats.increment("ui.gh.manifest.read_alloy_manifest")
      T.cast(ui_manifest[:alloy], T.nilable(T::Hash[String, T.untyped]))
    end

    sig { returns(T::Boolean) }
    def ui_deploys_enabled?
      is_rule_enabled?(:ui_deploys)
    end

    sig { void }
    def self.clear!
      @@local_ui_manifest = {} # rubocop:disable Style/ClassVars
      CurrentManifest.manifest = nil
    end


    sig { returns(Symbol) }
    def active_bundler
      return :vite if GitHub.vite_dev_server_enabled?

      bundler_flags.each do |config|
        flag = T.must(config[:flag])

        is_bundler_enabled = if GitHub.ui_dev_server_enabled?
          ENV["BUNDLER_FLAG"] == flag
        else
          !GitHub.ignore_ui_bundler_flags? && is_rule_enabled?(flag)
        end

        if is_bundler_enabled
          return T.must(config[:bundler]).to_sym
        end
      end

      :webpack
    end

    sig { returns(BundlerFlags) }
    def bundler_flags
      T.cast(ui_manifest[:bundlerFlags], BundlerFlags)
    end

    sig { params(type: Symbol).returns(T::Array[Symbol]) }
    def feature_flags(type:)
      feature_flags = T.cast(ui_manifest[:featureFlags], T::Hash[Symbol, T::Array[String]])
      T.must(feature_flags[type]).map(&:to_sym)
    rescue # rubocop:todo Lint/GenericRescue
      # Feature flags are sometimes loaded in CI environments with no UI manifest present
      # The flags aren't actually needed, so return an empty array to avoid breaking builds
      []
    end

    sig { params(type: Symbol).returns(T::Hash[T.any(Symbol, String), T::Array[Symbol]]) }
    def nested_feature_flags(type:)
      feature_flags = T.cast(ui_manifest[:featureFlags], T::Hash[T.any(Symbol, String), T.untyped])
      feature_flags[type].transform_values { |arr| Array(arr).map(&:to_sym) }
    rescue # rubocop:todo Lint/GenericRescue
      # Feature flags are sometimes loaded in CI environments with no UI manifest present
      # The flags aren't actually needed, so return an empty hash to avoid breaking builds
      {}
    end

    private

    # We want to avoid reading the local ui manifest from disk multiple times between requests, so we cache with a class var
    @@local_ui_manifest = T.let({}, T::Hash[T.any(String, Symbol), UIManifest]) # rubocop:disable Style/ClassVars

    sig { returns(UIManifest) }
    def local_ui_manifest
      local_ui_manifest_for_assets = @@local_ui_manifest[@assets]
      return local_ui_manifest_for_assets if local_ui_manifest_for_assets.present?

      # In dev, fetch the manifest from the ui dev server without any caching
      if GitHub.ui_dev_server_enabled?
        dev_ui_manifest = fetch_manifest_http("http://localhost:3014/ui-manifest.json")
        return JSON.parse(dev_ui_manifest).with_indifferent_access
      end

      # In production, Read the local ui manifest from disk and cache it
      assets = Rails.root.join(@assets)
      local_ui_manifest_path = assets.join("ui-manifest.json").to_s
      ui_manifest_content = File.read(local_ui_manifest_path)
      GitHub.dogstats.increment("ui.gh.manifest.read_from_disk")
      @@local_ui_manifest[@assets] = JSON.parse(ui_manifest_content).with_indifferent_access
    end

    sig { params(sha: String).returns(UIManifest) }
    def ui_manifest_for_sha(sha)
      @ui_manifest = GitHubUI::ManifestStore.get_manifest(git_sha: sha).with_indifferent_access
    rescue GitHubUI::ManifestStore::MissingError => e
      GitHub.logger.warn("Missing UI manifest for SHA", {
        "code.namespace": self.class.name,
        "code.function": __method__,
        "exception.message": e.message
      })

      raise e
    end

    sig { params(manifest_url: String).returns(String) }
    def fetch_manifest_http(manifest_url)
      manifest_uri = URI.parse(manifest_url)
      http = Net::HTTP.new(manifest_uri.host, manifest_uri.port)
      http.open_timeout = 60 # 60 seconds for initial connection
      http.read_timeout = 180 # 3 minutes for the dev server to respond (webpack can take ~2 minutes on startup)

      http.request(Net::HTTP::Get.new(manifest_uri)).body
    end

    sig { params(rule: T.any(Symbol, String)).returns(T::Boolean) }
    def is_rule_enabled?(rule)
      feature_enabled = GH.identity_context.domain_actor&.feature_enabled?(rule)
      feature_enabled = GitHub.flipper[rule].enabled? if feature_enabled.nil?

      feature_enabled
    end
  end
end
