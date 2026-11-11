# typed: strict
# frozen_string_literal: true

module GitHubUI
  class ManifestStore
    extend GitHub::ResilienceMixin
    class MissingError < StandardError
    end

    class CurrentStore < ActiveSupport::CurrentAttributes
      attribute :git_sha, default: {}
    end

    REDIS_TARGET_SHA_KEY_PREFIX = "sha_for_target:"
    REDIS_SHA_MANIFEST_KEY_PREFIX = "manifest_for_sha:"
    MANIFEST_TTL = T.let(7 * 60 * 60 * 24, Integer) # 1 week in seconds

    sig { params(target: String).returns(ManifestData) }
    def self.get(target:)
      git_sha = self.get_sha(target: target)
      get_manifest(git_sha: git_sha, target: target)
    end

    sig { params(target: String).returns(SHA) }
    def self.get_sha(target:)
      start_time = Time.now

      # Try CurrentAttributes first to avoid hitting Redis multiple times
      store = :memory
      sha = CurrentStore.git_sha[target]
      return sha if sha.present?

      store, sha = get_sha_from_store(target: target)
      sha
    ensure
      store = :missing if sha.blank?

      GitHub.dogstats.distribution("ui.gh.manifest.get_sha.time", Time.now - start_time, tags: ["target:#{target}", "type:#{store}"]) if start_time.present?

      if sha.present?
        # ensure a request always uses the same sha
        CurrentStore.git_sha[target] = sha
        GitHub.dogstats.increment("ui.gh.manifest.get_sha.success", tags: ["target:#{target}", "type:#{store}"])
      else
        GitHub.dogstats.increment("ui.gh.manifest.get_sha.failure", tags: ["target:#{target}", "type:missing"])
      end
    end

    sig { params(target: String).returns([Symbol, SHA]) }
    def self.get_sha_from_store(target:)
      store, sha = sha_mysql_first? ? get_sha_mysql_first(target: target) : get_sha_ui_deploys_first(target: target)

      if sha.present?
        Cache.update_sha_fallback(target: target, sha: sha)
      else
        store = :fallback
        sha = Cache.get_fallback_sha(target: target)
      end

      # If we reach here, it means we couldn't find the SHA in ui-deploys or MySQL or fallback
      raise MissingError.new("Missing SHA for target: #{target}") if sha.blank?

      # First time we load SHA from a store, we also schedule a request for `warmup` to try to keep the cache
      # as up-to-date as possible.
      schedule_warmup_request(sha: sha) if target != GitHubUI::TARGETS[:warmup]

      [store, sha]
    end

    sig { params(target: String).returns([Symbol, T.nilable(SHA)]) }
    def self.get_sha_ui_deploys_first(target:)
      # Try ui-deploys first
      store = :ui_deploys
      git_sha = get_sha_from_ui_deploys(target: target)
      return [store, git_sha] if git_sha.present?

      # Use MySQL as fallback
      store = :mysql
      git_sha = get_sha_from_mysql(target: target)
      return [store, git_sha] if git_sha.present?

      # Failed to load from external stores
      [:missing, nil]
    end

    sig { params(target: String).returns([Symbol, T.nilable(SHA)]) }
    def self.get_sha_mysql_first(target:)
      # Try mysql first
      store = :mysql
      git_sha = get_sha_from_mysql(target: target)
      return [store, git_sha] if git_sha.present?

      # Use ui-deploys as fallback
      store = :ui_deploys
      git_sha = get_sha_from_ui_deploys(target: target)
      return [store, git_sha] if git_sha.present?

      # Failed to load from external stores
      [:missing, nil]
    end

    sig { params(target: String).returns(T.nilable(SHA)) }
    def self.get_sha_from_mysql(target:)
      # If fallback is not cached, fetch from MySQL. Ensure we only load the SHA.
      manifest_record = with_database_error_fallback(fallback: nil) do
        UIManifest.select(:sha).find_by(target: target)
      end

      return unless manifest_record.present?

      manifest_record.sha
    rescue StandardError => e
      GitHub.logger.error("MySQL error when getting SHA for target: #{e.message}", {
        "target": target,
        "code.namespace": self.class.name,
        "code.function": __method__,
        "backtrace": e.backtrace&.join("\n") || "",
      })
      nil
    end

    sig { params(target: String).returns(T.nilable(SHA)) }
    def self.get_sha_from_ui_deploys(target:)
      return unless sha_from_ui_deploys?

      start_time = Time.now
      git_sha = nil

      connection = ui_deploys_faraday_connection
      return nil unless connection.present?

      path = "/target/#{target}"
      response = connection.get(path)

      if response.success?
        git_sha = JSON.parse(response.body).dig("sha")
      end

      git_sha
    rescue StandardError => e
      GitHub.logger.error("ui-deploys error when getting SHA for target: #{e.message}", {
        "target": target,
        "code.namespace": self.class.name,
        "code.function": __method__,
        "backtrace": e.backtrace&.join("\n") || "",
      })
      nil
    ensure
      if start_time.present?
        result = git_sha.present? ? "success" : "missing"
        GitHub.dogstats.distribution("ui.gh.manifest.get_sha_from_ui_deploys.duration", Time.now - start_time, tags: ["target:#{target}", "result:#{result}"])
      end
    end

    sig { params(git_sha: String, target: Target, brotli: T::Boolean).returns(ManifestData) }
    def self.get_manifest(git_sha:, target:, brotli: true)
      start_time = Time.now

      manifest, store = get_manifest_from_cache(git_sha: git_sha, target: target)

      if manifest.blank?
        manifest, store = get_manifest_from_stores(git_sha: git_sha, target: target, brotli: brotli)

        # only update caches if not coming from cache already
        if manifest.present?
          store_manifest_in_disk(git_sha: git_sha, manifest: manifest)
        end
      end

      truncated_sha = git_sha[0, 7]
      if manifest.present?
        Cache.set_manifest(sha: git_sha, manifest: manifest, target: target) if store != :memory

        GitHub.dogstats.distribution("ui.gh.manifest.get_manifest.time", Time.now - start_time, tags: ["target:#{target}", "type:#{store}", "sha:#{truncated_sha}"])
        GitHub.dogstats.increment("ui.gh.manifest.get_manifest.success", tags: ["type:#{store}", "target:#{target}", "sha:#{truncated_sha}"])
      else
        GitHub.dogstats.increment("ui.gh.manifest.get_manifest.failure", tags: ["type:missing", "target:#{target}", "sha:#{truncated_sha}"])
        raise MissingError.new("Missing manifest for SHA: #{git_sha}")
      end

      manifest
    end

    sig { params(git_sha: String, target: Target).returns([T.nilable(ManifestData), Symbol]) }
    def self.get_manifest_from_cache(git_sha:, target:)
      store = :memory
      # Check in-memory cache first
      manifest = Cache.get_manifest(sha: git_sha, target: target)

      return [manifest, store] if manifest.present?
      return [nil, :missing] unless use_disk_cache? && File.exist?(manifest_disk_path(git_sha: git_sha))

      manifest = JSON.parse(File.read(manifest_disk_path(git_sha: git_sha))).with_indifferent_access
      [manifest, :disk]
    rescue StandardError => e
      GitHub.dogstats.increment("ui.gh.manifest.get_manifest.disk.failure", tags: ["target:#{target}"])

      [nil, :missing]
    end

    sig { params(git_sha: String, target: Target, brotli: T::Boolean).returns([T.nilable(ManifestData), Symbol]) }
    def self.get_manifest_from_stores(git_sha:, target:, brotli: true)
      # Fetch manifest from ui-deploys first
      store = :ui_deploys
      manifest = get_manifest_from_ui_deploys(git_sha: git_sha, target: target, brotli: brotli)
      return [manifest, store] if manifest.present?

      # Try CDN next
      store = :cdn
      manifest = get_manifest_from_cdn(git_sha: git_sha, brotli: brotli)

      return [manifest, store] if manifest.present?

      # Fall back to MySQL as last resort
      store = :mysql
      manifest = get_manifest_from_mysql(git_sha: git_sha)

      store = :missing if manifest.blank?

      [manifest, store]
    end

    sig { params(git_sha: String).returns(T.nilable(ManifestData)) }
    def self.get_manifest_from_mysql(git_sha:)
      start_time = Time.now

      # Read the manifest from MySQL by git sha
      manifest = UIManifest.find_by(sha: git_sha)&.manifest&.with_indifferent_access

      manifest
    ensure
      if start_time.present?
        result = manifest.present? ? "success" : "missing"
        GitHub.dogstats.distribution("ui.gh.manifest.get_manifest_from_mysql.duration", Time.now - start_time, tags: ["result:#{result}"])
      end
    end

    sig { params(git_sha: SHA, manifest: ManifestData).void }
    def self.store_manifest_in_disk(git_sha:, manifest:)
      return unless use_disk_cache?

      start_time = Time.now
      written = T.let(false, T::Boolean)
      # Use a lock path so only a single process can access it since atomic_write
      # uses a temporary file.
      lock_path = "#{manifest_disk_path(git_sha: git_sha)}.lock"
      File.open(lock_path, File::RDWR | File::CREAT) do |lock|
        lock_acquired = lock.flock(File::LOCK_EX | File::LOCK_NB)

        if !lock_acquired
          GitHub.dogstats.increment("ui.gh.manifest.disk.lock.fail")
          return
        end

        # atomic_write ensures that another thread won't read half-written files
        File.atomic_write(manifest_disk_path(git_sha: git_sha)) do |f|
          f.write(manifest.to_json)
          f.flush
          f.fsync
        end

        written = true
      end
    rescue StandardError => e
      GitHub.logger.error("Error storing manifest in disk", {
        "exception.message": e.message,
        "git_sha": git_sha,
        "code.namespace": self.class.name,
        "code.function": __method__,
      })
      GitHub.dogstats.increment("ui.gh.manifest.disk.write.failure")
    ensure
      if start_time.present? && use_disk_cache?
        GitHub.dogstats.distribution("ui.gh.manifest.disk.write.duration", Time.now - start_time, tags: ["written:#{written}"])
      end
    end

    sig { params(target: Target, git_sha: SHA, manifest: ManifestData).returns(ManifestData) }
    def self.set(target:, git_sha:, manifest:)
      raise "Expected 'alloy' data in UI manifest" unless manifest.key?("alloy")
      preview = target == GitHubUI::TARGETS[:preview]

      # Store in MySQL for reliable fallbacks (unless preview)
      UIManifest.upsert({ target: target, sha: git_sha, manifest: manifest }) unless preview

      # Send prewarm request to Alloy
      prewarm_alloy(manifest, preview: preview)

      GitHub.dogstats.increment("ui.gh.manifest.set.success", tags: ["target:#{target}"])
      manifest
    end

    sig { void }
    def self.clear
      Cache.clear
      @ui_deploys_production_connection = {}
      @ui_deploys_staging_connection = {}
      @ui_deploys_preview_connection = {}
    end

    sig { params(manifest: ManifestData, preview: T::Boolean).void }
    def self.prewarm_alloy(manifest, preview: false)
      fingerprinted_manifest = manifest.dig("alloy", "manifest")
      raise "Missing 'manifest' key in 'alloy' data" if fingerprinted_manifest.blank?

      response = Alloy::Warmup.new(fingerprinted_manifest, staging: preview).call
      unless response.success?
        raise "Failed to warm up Alloy manifest: #{response.status} #{response.body}"
      end
    end

    sig { params(git_sha: String, brotli: T::Boolean).returns(T.nilable(ManifestData)) }
    def self.get_manifest_from_cdn(git_sha:, brotli: true)
      start_time = Time.now

      response = faraday_connection.get(manifest_url(git_sha: git_sha), nil, brotli ? { "Accept-Encoding" => "br" } : {})
      manifest = response.body

      # Decompress Brotli encoded response
      manifest = decompress(data: manifest) if response.headers&.dig("content-encoding") == "br"

      # Parse the manifest
      manifest_data = if response.success?
        JSON.parse(manifest)
      else
        nil
      end

      manifest_data&.with_indifferent_access
    rescue StandardError
      manifest_data = nil
    ensure
      if manifest_data.blank?
        GitHub.logger.error("Failed to fetch manifest from CDN", {
          "git_sha": git_sha,
          "code.namespace": self.class.name,
          "code.function": __method__,
        })
      end

      if start_time.present?
        result = manifest_data.present? ? "success" : "missing"
        GitHub.dogstats.distribution("ui.gh.manifest.get_manifest_from_cdn.duration", Time.now - start_time, tags: ["result:#{result}"])
      end
    end

    sig { params(git_sha: String).returns(T.nilable(ConcurrentFaraday::FutureResponse[T.untyped])) }
    def self.get_manifest_from_cdn_async(git_sha:)
      client = ConcurrentFaraday.new do |conn|
        conn.use GitHub::FaradayMiddleware::DatadogAsync, stats: GitHub.dogstats, service_name: "github-ui-cdn", custom_tags: ["sha:#{git_sha}"]
        conn.use GitHub::FaradayMiddleware::AsyncDuration

        conn.options[:open_timeout] = 0.250
        conn.options[:timeout] = 0.5
        conn.adapter :concurrent_adapter, persistent: true
      end

      client.get(manifest_url(git_sha: git_sha))
    rescue StandardError => e
      GitHub.logger.error("Failed to asynchronously fetch manifest from CDN", {
        "exception.message": e.message,
        "git_sha": git_sha,
        "code.namespace": self.class.name,
        "code.function": __method__,
      })
    end

    sig { params(git_sha: String, target: Target, brotli: T::Boolean).returns(T.nilable(ManifestData)) }
    def self.get_manifest_from_ui_deploys(git_sha:, target:, brotli: true)
      return unless manifest_from_ui_deploys?

      start_time = Time.now

      connection = ui_deploys_faraday_connection
      return nil unless connection.present?

      manifest_url = ui_deploys_manifest_path(git_sha: git_sha, target: target)
      response = connection.get(manifest_url, nil, brotli ? { "Accept-Encoding" => "br" } : {})
      manifest = response.body

      # Decompress Brotli encoded response when ui-deploys returns br
      manifest = decompress(data: manifest) if response.headers&.dig("content-encoding") == "br"

      # Parse the manifest (ui-deploys doesn't use brotli)
      manifest_data = if response.success?
        JSON.parse(manifest)
      else
        nil
      end

      manifest_data&.with_indifferent_access
    rescue StandardError => e
      GitHub.logger.error("Failed to fetch manifest from ui-deploys", {
        "exception.class": e.class.name,
        "exception.message": e.message,
        "git_sha": git_sha,
        "target": target,
        "code.namespace": self.class.name,
        "code.function": __method__,
      })
      manifest_data = nil
    ensure
      if manifest_data.blank?
        GitHub.logger.error("Failed to load manifest from ui-deploys", {
          "git_sha": git_sha,
          "target": target,
          "code.namespace": self.class.name,
          "code.function": __method__,
        })
      end

      if start_time.present?
        result = manifest_data.present? ? "success" : "missing"
        GitHub.dogstats.distribution("ui.gh.manifest.get_manifest_from_ui_deploys.duration", Time.now - start_time, tags: ["result:#{result}", "target:#{target}"])
      end
    end

    sig { params(git_sha: String, target: Target).returns(T.nilable(ConcurrentFaraday::FutureResponse[T.untyped])) }
    def self.get_manifest_from_ui_deploys_async(git_sha:, target:)
      manifest_url = ui_deploys_manifest_path(git_sha: git_sha, target: target)
      return nil unless manifest_url.present?

      client = ConcurrentFaraday.new do |conn|
        conn.use GitHub::FaradayMiddleware::DatadogAsync, stats: GitHub.dogstats, service_name: "ui-deploys", custom_tags: ["sha:#{git_sha}", "target:#{target}"]
        conn.use GitHub::FaradayMiddleware::AsyncDuration

        conn.options[:open_timeout] = 0.250
        conn.options[:timeout] = 0.5
        conn.adapter :concurrent_adapter, persistent: true
      end

      client.get(manifest_url)
    rescue StandardError => e
      GitHub.logger.error("Failed to asynchronously load manifest from ui-deploys", {
        "exception.class": e.class.name,
        "exception.message": e.message,
        "git_sha": git_sha,
        "target": target,
        "code.namespace": self.class.name,
        "code.function": __method__,
      })
    end

    sig { params(sha: SHA).void }
    def self.schedule_warmup_request(sha:)
      # after_response is required to finish the request
      return unless GitHub.after_response.enabled? && is_rule_enabled?(:ui_manifest_warmup)

      target = T.must(GitHubUI::TARGETS[:warmup])
      warmup_sha = get_sha(target: target)

      return if warmup_sha.blank? || sha == warmup_sha
      cached_manifest, _ = get_manifest_from_cache(git_sha: warmup_sha, target: "warmup")
      return if cached_manifest.present?

      GitHubUI::CacheUpdater.new(target: target, sha: warmup_sha).start
    end

    sig { params(manifest: ManifestData).returns(T.untyped) }
    def self.compress(manifest:)
      start = Time.now
      result = Brotli.deflate(manifest.to_json, quality: 11)
      GitHub.dogstats.distribution("ui.gh.manifest.compress.duration", Time.now - start)
      result
    end

    sig { params(data: T.untyped).returns(T.nilable(String)) }
    def self.decompress(data:)
      start = Time.now
      Brotli.inflate(data)
    rescue Brotli::Error => ex
      GitHub.logger.error("Failed to decompress manifest", {
        "code.namespace": self.class.name,
        "code.function": __method__,
        "error.message": ex.message,
        "backtrace": ex.backtrace&.join("\n") || "",
      })
    ensure
      if start.present?
        GitHub.dogstats.distribution("ui.gh.manifest.decompress.duration", Time.now - start)
      end
    end

    sig { returns(Faraday::Connection) }
    def self.faraday_connection
      GitHub::FaradayClient::External.new do |conn|
        conn.options[:open_timeout] = 0.250
        conn.options[:timeout] = 0.250
      end
    end

    sig { params(git_sha: SHA).returns(Pathname) }
    def self.manifest_disk_path(git_sha:)
      Rails.root.join("tmp", "ui-manifest-#{git_sha}.json")
    end

    sig { params(git_sha: SHA).returns(String) }
    def self.manifest_url(git_sha:)
      # Fetch the manifest from the CDN. Load from the Rails host if no CDN is set. Enterprise
      # instances always load from the Rails host.
      prefix = GitHub.asset_host_url.presence || GitHub.url
      prefix = GitHub.url if GitHub.enterprise?

      "#{prefix}/assets/ui-manifest-#{git_sha}.json"
    end

    sig { returns(T::Boolean) }
    def self.sha_mysql_first?
      is_rule_enabled?(:ui_manifest_sha_mysql_first)
    end

    sig { returns(T::Boolean) }
    def self.manifest_from_ui_deploys?
      !is_rule_enabled?(:disable_ui_deploys_manifest)
    end

    sig { returns(T::Boolean) }
    def self.sha_from_ui_deploys?
      !is_rule_enabled?(:disable_ui_deploys_sha)
    end

    sig { returns(T.nilable(Faraday::Connection)) }
    def self.ui_deploys_faraday_connection
      if GitHub.ui_preview?
        ui_deploys_preview_faraday_connection
      elsif GitHub.review_lab?
        ui_deploys_staging_faraday_connection
      else
        ui_deploys_production_faraday_connection
      end
    end

    @ui_deploys_production_connection = T.let({}, T::Hash[Symbol, Faraday::Connection])
    sig { returns(T.nilable(Faraday::Connection)) }
    def self.ui_deploys_production_faraday_connection
      ui_deploys_url = GitHub.ui_deploys_url
      return nil unless ui_deploys_url.present?

      adapter = resolve_adapter
      return @ui_deploys_production_connection[adapter] if @ui_deploys_production_connection[adapter].present?
      @ui_deploys_production_connection[adapter] = GitHub::FaradayClient::Internal.new(ui_deploys_url) do |conn|
        setup_ui_deploys_connection(conn, adapter: adapter)
      end
    end

    @ui_deploys_staging_connection = T.let({}, T::Hash[Symbol, Faraday::Connection])
    sig { returns(T.nilable(Faraday::Connection)) }
    def self.ui_deploys_staging_faraday_connection
      url = GitHub.ui_deploys_staging_url
      return nil unless url.present?

      adapter = resolve_adapter
      return @ui_deploys_staging_connection[adapter] if @ui_deploys_staging_connection[adapter].present?
      @ui_deploys_staging_connection[adapter] = GitHub::FaradayClient::Internal.new(url) do |conn|
        setup_ui_deploys_connection(conn, adapter: adapter)
      end
    end

    @ui_deploys_preview_connection = T.let({}, T::Hash[Symbol, Faraday::Connection])
    sig { returns(T.nilable(Faraday::Connection)) }
    def self.ui_deploys_preview_faraday_connection
      url = GitHub.ui_deploys_preview_url
      return nil unless url.present?

      adapter = resolve_adapter
      return @ui_deploys_preview_connection[adapter] if @ui_deploys_preview_connection[adapter].present?
      @ui_deploys_preview_connection[adapter] = GitHub::FaradayClient::Internal.new(url) do |conn|
        setup_ui_deploys_connection(conn, adapter: adapter)
      end
    end

    # Dotcom uses the typhoeus adapter (fresh connections per request) to reduce
    # socket failures against the Istio sidecar. Enterprise uses persistent_excon.
    sig { returns(Symbol) }
    def self.resolve_adapter
      if GitHub.single_or_multi_tenant_enterprise?
        :persistent_excon
      else
        :typhoeus
      end
    end

    sig { params(conn: Faraday::Connection, adapter: Symbol).void }
    def self.setup_ui_deploys_connection(conn, adapter:)
      datadog_middleware = ::GitHub::FaradayMiddleware::Datadog
      conn.use datadog_middleware, stats: GitHub.dogstats, service_name: "ui-deploys", custom_tags: []
      conn.use GitHub::FaradayMiddleware::StaffRequest

      conn.options[:open_timeout] = 0.250
      conn.options[:timeout] = 1
      conn.headers[:user_agent] = "github-#{GitHub.role}/#{GitHub.current_sha}"

      if adapter == :typhoeus
        conn.adapter :typhoeus
      else
        # Use persistent_excon with keepalive
        conn.adapter :persistent_excon, {
          tcp_nodelay: true,
          keepalive: {
            time: 60,
            intvl: 5,
            probes: 3,
          }
        }
      end
    end

    sig { params(git_sha: SHA, target: Target).returns(T.nilable(String)) }
    def self.ui_deploys_manifest_path(git_sha:, target:)
      "/target/#{target}/ui-manifest/ui-manifest-#{git_sha}.json"
    end

    sig { returns(T::Boolean) }
    def self.use_disk_cache?
      # In development with a pre-built UI manifest SHA (e.g. BCDR, local dev without UI dev server),
      # enable disk cache so we can load the manifest downloaded by sync-github-ui-version
      # without needing network access to the CDN or ui-deploys.
      return true if Rails.env.development? && GitHub.ui_manifest_sha.present?

      # In other dev environments, avoid using too much disk space
      !Rails.env.development?
    end

    sig { params(rule: T.any(Symbol, String)).returns(T::Boolean) }
    def self.is_rule_enabled?(rule)
      FeatureFlag.vexi.enabled?(rule, GH.identity_context.domain_actor, default: false)
    end
  end
end
