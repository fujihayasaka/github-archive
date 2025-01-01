# typed: strict
# frozen_string_literal: true

module GitHubUI
  class ManifestStore
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
      store, sha = sha_redis_first? ? get_sha_redis_first(target: target) : get_sha_mysql_first(target: target)
      # If we reach here, it means we couldn't find the SHA in Redis or MySQL
      raise MissingError.new("Missing SHA for target: #{target}") if sha.blank?

      # First time we load SHA from a store, we also schedule a request for `warmup` to try to keep the cache
      # as up-to-date as possible.
      schedule_warmup_request(sha: sha)

      [store, sha]
    end

    sig { params(target: String).returns([Symbol, T.nilable(SHA)]) }
    def self.get_sha_redis_first(target:)
      # Use redis if it's not cached in the request
      store = :redis
      git_sha = get_sha_from_redis(target: target)

      if git_sha.present?
        Cache.update_sha_fallback(target: target, sha: git_sha)
        return [store, git_sha]
      end

      # Redis failed, see if we have a fallback SHA cached in fallback
      store = :fallback
      git_sha = Cache.get_fallback_sha(target: target)

      return [store, git_sha] if git_sha.present?

      store = :mysql
      # If fallback is not cached, fetch from MySQL. Ensure we only load the SHA.
      git_sha = get_sha_from_mysql(target: target)

      [store, git_sha]
    end

    sig { params(target: String).returns([Symbol, T.nilable(SHA)]) }
    def self.get_sha_mysql_first(target:)
      store = :mysql
      git_sha = get_sha_from_mysql(target: target)

      return [store, git_sha] if git_sha.present?

      # Redis failed, see if we have a fallback SHA cached in fallback
      store = :fallback
      git_sha = Cache.get_fallback_sha(target: target)

      return [store, git_sha] if git_sha.present?

      # Use redis if it's not cached in the request
      store = :redis
      git_sha = get_sha_from_redis(target: target)

      [store, git_sha]
    end

    sig { params(target: String).returns(T.nilable(SHA)) }
    def self.get_sha_from_redis(target:)
      start_time = Time.now

      # Read the sha from Redis by target
      redis_key = "#{REDIS_TARGET_SHA_KEY_PREFIX}#{target}"
      git_sha = GitHubUI::Redis.client.get(redis_key)

      # Return the git sha or nil
      git_sha || nil
    rescue StandardError => e # rubocop:todo Lint/RescueException
      GitHub.logger.error("Redis error when getting SHA for target: #{e.message}", {
        "target": target,
        "code.namespace": self.class.name,
        "code.function": __method__,
        "backtrace": e.backtrace&.join("\n") || "",
      })
      nil
    ensure
      if start_time.present?
        result = git_sha.present? ? "success" : "missing"
        GitHub.dogstats.distribution("ui.gh.manifest.get_sha_from_redis.duration", Time.now - start_time, tags: ["target:#{target}", "result:#{result}"])
      end
    end

    sig { params(target: String).returns(T.nilable(SHA)) }
    def self.get_sha_from_mysql(target:)
      # If fallback is not cached, fetch from MySQL. Ensure we only load the SHA.
      manifest_record = UIManifest.select(:sha).find_by(target: target)

      return unless manifest_record.present?

      Cache.update_sha_fallback(target: target, sha: manifest_record.sha)
      manifest_record.sha
    rescue StandardError => e # rubocop:todo Lint/RescueException
      GitHub.logger.error("MySQL error when getting SHA for target: #{e.message}", {
        "target": target,
        "code.namespace": self.class.name,
        "code.function": __method__,
        "backtrace": e.backtrace&.join("\n") || "",
      })
      nil
    end

    sig { params(git_sha: String, target: Target, brotli: T::Boolean).returns(ManifestData) }
    def self.get_manifest(git_sha:, target:, brotli: true)
      start_time = Time.now

      manifest, store = get_manifest_from_cache(git_sha: git_sha, target: target)

      if manifest.blank?
        manifest, store = if manifest_redis_first?
          get_manifest_redis_first(git_sha: git_sha, target: target, brotli: brotli)
        else
          get_manifest_cdn_first(git_sha: git_sha, target: target, brotli: brotli)
        end

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
    rescue StandardError => e # rubocop:todo Lint/RescueException
      GitHub.dogstats.increment("ui.gh.manifest.get_manifest.disk.failure", tags: ["target:#{target}"])

      [nil, :missing]
    end

    sig { params(git_sha: String, target: Target, brotli: T::Boolean).returns([T.nilable(ManifestData), Symbol]) }
    def self.get_manifest_cdn_first(git_sha:, target:, brotli: true)
      # Try ui-deploys first if feature flag is enabled
      if manifest_from_ui_deploys?
        store = :ui_deploys
        manifest = get_manifest_from_ui_deploys(git_sha: git_sha, target: target)
        return [manifest, store] if manifest.present?
      end

      # Fetch from CDN if there's no in-memory cache
      store = :cdn
      manifest = get_manifest_from_cdn(git_sha: git_sha, brotli: brotli)

      return [manifest, store] if manifest.present?

      # Check Redis next
      store = :redis
      manifest = get_manifest_from_redis(git_sha: git_sha)
      return [manifest, store] if manifest.present?

      # Fall back to MySQL if Redis fails
      store = :mysql
      manifest = get_manifest_from_mysql(git_sha: git_sha)

      store = :missing if manifest.blank?

      [manifest, store]
    end

    sig { params(git_sha: String, target: Target, brotli: T::Boolean).returns([T.nilable(ManifestData), Symbol]) }
    def self.get_manifest_redis_first(git_sha:, target:, brotli: true)
      # Fetch from Redis if there's no in-memory cache
      store = :redis
      manifest = get_manifest_from_redis(git_sha: git_sha)

      return [manifest, store] if manifest.present?

      # CDN second
      store = :cdn
      manifest = get_manifest_from_cdn(git_sha: git_sha, brotli: brotli)

      return [manifest, store] if manifest.present?

      # MySQL as last resort
      store = :mysql
      manifest = get_manifest_from_mysql(git_sha: git_sha)

      store = :missing if manifest.blank?

      [manifest, store]
    end

    sig { params(git_sha: String).returns(T.nilable(ManifestData)) }
    def self.get_manifest_from_redis(git_sha:)
      start_time = Time.now

      # Read the manifest from Redis by git sha
      redis_key = "#{REDIS_SHA_MANIFEST_KEY_PREFIX}#{git_sha}"
      data = GitHubUI::Redis.client.get(redis_key)

      # Return nil if the manifest is not in Redis
      return nil if !data.present?

      manifest_json = decompress(data: data)

      return nil if !manifest_json.present?

      # Parse the manifest
      manifest = JSON.parse(manifest_json)
      manifest&.with_indifferent_access
    rescue StandardError => e # rubocop:todo Lint/RescueException
      GitHub.logger.error("Redis error when getting manifest: #{e.message}", {
        "git_sha": git_sha,
        "code.namespace": self.class.name,
        "code.function": __method__,
        "backtrace": e.backtrace&.join("\n") || "",
      })
      nil
    ensure
      if start_time.present?
        result = manifest_json.present? ? "success" : "missing"
        GitHub.dogstats.distribution("ui.gh.manifest.get_manifest_from_redis.duration", Time.now - start_time, tags: ["result:#{result}"])
      end
    end

    sig { params(git_sha: String).returns(T.nilable(ManifestData)) }
    def self.get_manifest_from_mysql(git_sha:)
      start_time = Time.now

      # Read the manifest from MySQL by git sha
      manifest = UIManifest.find_by(sha: git_sha)&.manifest&.with_indifferent_access

      if manifest.present? && !manifest_exists?(git_sha: git_sha)
        set_in_redis(git_sha: git_sha, manifest: manifest)
      end

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
    rescue StandardError => e # rubocop:todo Lint/RescueException
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

      # The upsert will be rolled back if redis fails to save
      UIManifest.transaction do
        # Store in MySQL first for reliable fallbacks
        UIManifest.upsert({ target: target, sha: git_sha, manifest: manifest }) unless preview

        # Update Redis
        set_in_redis(target: target, git_sha: git_sha, manifest: manifest, preview: preview)
      end

      # Send prewarm request to Alloy
      prewarm_alloy(manifest, preview: preview)

      GitHub.dogstats.increment("ui.gh.manifest.set.success", tags: ["target:#{target}"])
      manifest
    end

    sig { params(git_sha: SHA, manifest: ManifestData, target: T.nilable(Target), preview: T::Boolean).void }
    def self.set_in_redis(git_sha:, manifest:, target: nil, preview: false)
      compressed_manifest = compress(manifest: manifest)

      GitHubUI::Redis.client.set("#{REDIS_SHA_MANIFEST_KEY_PREFIX}#{git_sha}", compressed_manifest, ex: MANIFEST_TTL)
      GitHubUI::Redis.client.set("#{REDIS_TARGET_SHA_KEY_PREFIX}#{target}", git_sha) if !preview && target.present?
    rescue StandardError => e # rubocop:todo Lint/RescueException
      GitHub.dogstats.increment("ui.gh.manifest.set.failure", tags: ["target:#{target}", "type:redis"])
      GitHub.logger.error("Redis error when setting manifest: #{e.message}", {
        "target": target,
        "git_sha": git_sha,
        "code.namespace": self.class.name,
        "code.function": __method__,
        "backtrace": e.backtrace&.join("\n") || "",
      })
    end

    sig { void }
    def self.clear
      Cache.clear
      GitHubUI::Redis.client.flushall
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
    rescue StandardError # rubocop:todo Lint/RescueException
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
    rescue StandardError => e # rubocop:todo Lint/RescueException
      GitHub.logger.error("Failed to asynchronously fetch manifest from CDN", {
        "exception.message": e.message,
        "git_sha": git_sha,
        "code.namespace": self.class.name,
        "code.function": __method__,
      })
    end

    @ui_deploys_connection = T.let(nil, T.nilable(Faraday::Connection))
    sig { params(git_sha: String, target: Target).returns(T.nilable(ManifestData)) }
    def self.get_manifest_from_ui_deploys(git_sha:, target:)
      start_time = Time.now

      connection = ui_deploys_faraday_connection
      return nil unless connection.present?

      manifest_url = ui_deploys_manifest_path(git_sha: git_sha, target: target)
      response = connection.get(manifest_url)
      manifest = response.body

      # Parse the manifest (ui-deploys doesn't use brotli)
      manifest_data = if response.success?
        JSON.parse(manifest)
      else
        nil
      end

      manifest_data&.with_indifferent_access
    rescue StandardError => e # rubocop:todo Lint/RescueException
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
    rescue StandardError => e # rubocop:todo Lint/RescueException
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
      warmup_sha = get_sha_from_redis(target: target)

      return if warmup_sha.blank? || sha == warmup_sha
      cached_manifest, _ = get_manifest_from_cache(git_sha: warmup_sha, target: "warmup")
      return if cached_manifest.present?

      GitHubUI::CacheUpdater.new(target: target, sha: warmup_sha).start
    end

    sig { params(git_sha: String).returns(T::Boolean) }
    def self.manifest_exists?(git_sha:)
      GitHubUI::Redis.client.exists?("#{REDIS_SHA_MANIFEST_KEY_PREFIX}#{git_sha}")
    rescue StandardError
      false
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
    def self.manifest_redis_first?
      is_rule_enabled?(:ui_manifest_redis_first)
    end

    sig { returns(T::Boolean) }
    def self.sha_redis_first?
      is_rule_enabled?(:ui_manifest_sha_redis_first)
    end

    sig { returns(T::Boolean) }
    def self.manifest_from_ui_deploys?
      is_rule_enabled?(:ui_manifest_from_ui_deploys)
    end

    sig { returns(T.nilable(Faraday::Connection)) }
    def self.ui_deploys_faraday_connection
      ui_deploys_url = GitHub.ui_deploys_url
      return nil unless ui_deploys_url.present?

      return @ui_deploys_connection if @ui_deploys_connection.present?
      @ui_deploys_connection = GitHub::FaradayClient::Internal.new(ui_deploys_url) do |conn|
        datadog_middleware = ::GitHub::FaradayMiddleware::Datadog
        conn.use datadog_middleware, stats: GitHub.dogstats, service_name: "ui-deploys", custom_tags: []
        conn.use GitHub::FaradayMiddleware::StaffRequest

        conn.options[:open_timeout] = 0.250
        conn.options[:timeout] = 1
        conn.headers[:user_agent] = "github-#{GitHub.role}/#{GitHub.current_sha}"

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
      # avoid using too much disk space in development
      !Rails.env.development?
    end

    sig { params(rule: T.any(Symbol, String)).returns(T::Boolean) }
    def self.is_rule_enabled?(rule)
      FeatureFlag.vexi.enabled?(rule, GH.identity_context.domain_actor, default: false)
    end
  end
end
