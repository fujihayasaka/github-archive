# typed: strict
# frozen_string_literal: true

module GitHubUI
  class ManifestStore
    class MissingError < StandardError
    end

    class CurrentStore < ActiveSupport::CurrentAttributes
      attribute :git_sha, default: {}
    end
    ManifestData = T.type_alias { T::Hash[String, T.untyped] }
    SHA = T.type_alias { String }
    Target = T.type_alias { String }
    SHAFallbackEntry = T.type_alias { { sha: SHA, expires_at: Time } }

    @manifest_store = T.let({}, T::Hash[SHA, ManifestData])
    @sha_fallback = T.let({}, T::Hash[Target, SHAFallbackEntry])
    FALLBACK_CACHE_TTL = T.let(30.seconds, T.any(Integer, ActiveSupport::Duration))

    REDIS_TARGET_SHA_KEY_PREFIX = "sha_for_target:"
    REDIS_SHA_MANIFEST_KEY_PREFIX = "manifest_for_sha:"

    sig { params(target: String).returns(ManifestData) }
    def self.get(target:)
      git_sha = self.get_sha(target: target)
      get_manifest(git_sha: git_sha)
    end

    sig { params(target: String).returns(SHA) }
    def self.get_sha(target:)
      # Try CurrentAttributes first
      store = :memory
      git_sha = CurrentStore.git_sha[target]
      return git_sha if git_sha.present?

      # Use redis if it's not cached in the request
      store = :redis
      git_sha = get_sha_from_redis(target: target)

      if git_sha.present?
        @sha_fallback[target] = { sha: git_sha, expires_at: Time.now + FALLBACK_CACHE_TTL }
        return git_sha
      end

      # Redis failed, see if we have a fallback SHA cached in fallback
      store = :fallback
      git_sha = get_fallback_sha(target: target)

      return git_sha if git_sha.present?

      store = :mysql
      # If fallback is not cached, fetch from MySQL
      manifest_record = UIManifest.find_by(target: target)

      if manifest_record.present?
        # Cache the manifest for the sha in memory, avoiding additional DB lookups
        git_sha = manifest_record.sha
        @manifest_store[git_sha] = manifest_record.manifest.deep_symbolize_keys

        # Add a fallback cache for the target in case redis fails for a while
        @sha_fallback[target] = { sha: manifest_record.sha, expires_at: Time.now + FALLBACK_CACHE_TTL }
      end

      git_sha
    ensure
      if git_sha.present?
        # ensure a request always uses the same sha
        CurrentStore.git_sha[target] = git_sha
        GitHub.dogstats.increment("ui.gh.manifest.get_sha.success", tags: ["target:#{target}", "type:#{store}"])
      else
        GitHub.dogstats.increment("ui.gh.manifest.get_sha.failure", tags: ["target:#{target}", "type:missing"])
        raise MissingError.new("Missing SHA for target: #{target}")
      end
    end

    sig { params(target: String).returns(T.nilable(SHA)) }
    def self.get_sha_from_redis(target:)
      start_time = Time.now

      # Read the sha from Redis by target
      redis_key = "#{REDIS_TARGET_SHA_KEY_PREFIX}#{target}"
      git_sha = redis.get(redis_key)

      # Return the git sha or nil
      git_sha || nil
    rescue StandardError => e # rubocop:todo Lint/GenericRescue
      GitHub.logger.error("Redis error when getting SHA for target: #{e.message}", {
        "target": target,
        "code.namespace": self.class.name,
        "code.function": __method__,
      })
      nil
    ensure
      if start_time.present?
        result = git_sha.present? ? "success" : "missing"
        GitHub.dogstats.distribution("ui.gh.manifest.get_sha_from_redis.duration", Time.now - start_time, tags: ["target:#{target}", "result:#{result}"])
      end
    end

    sig { params(git_sha: String).returns(ManifestData) }
    def self.get_manifest(git_sha:)
      store = :memory
      # Check in-memory cache first
      manifest = @manifest_store[git_sha]

      return manifest if manifest.present?

      # Check Redis next
      store = :redis
      manifest = get_manifest_from_redis(git_sha: git_sha)
      return manifest if manifest.present?

      # Fall back to MySQL if Redis fails
      store = :mysql
      manifest = get_manifest_from_mysql(git_sha: git_sha)
      return manifest if manifest.present?

      # Fetch from CDN if MySQL fails
      # This will be common for when testing a specific SHA
      store = :cdn
      manifest = get_manifest_from_cdn(git_sha: git_sha)

      if manifest.blank?
        GitHub.logger.error("Missing fallback manifest in MySQL and CDN", {
          "git_sha": git_sha,
          "code.namespace": self.class.name,
          "code.function": __method__,
        })
        raise MissingError.new("Missing manifest for SHA: #{git_sha}")
      end

      manifest
    ensure
      if manifest.present?
        # store manifest in the memory cache
        @manifest_store[git_sha] = manifest
        GitHub.dogstats.increment("ui.gh.manifest.get_manifest.success", tags: ["type:#{store}"])
      else
        GitHub.dogstats.increment("ui.gh.manifest.get_manifest.failure", tags: ["type:missing"])
        raise MissingError.new("Missing manifest for SHA: #{git_sha}")
      end
    end

    sig { params(git_sha: String).returns(T.nilable(ManifestData)) }
    def self.get_manifest_from_redis(git_sha:)
      start_time = Time.now

      # Read the manifest from Redis by git sha
      redis_key = "#{REDIS_SHA_MANIFEST_KEY_PREFIX}#{git_sha}"
      manifest_json = redis.get(redis_key)

      # Return nil if the manifest is not in Redis
      return nil if !manifest_json.present?

      # Parse the manifest
      manifest = JSON.parse(manifest_json)
      manifest
    rescue StandardError => e # rubocop:todo Lint/GenericRescue
      GitHub.logger.error("Redis error when getting manifest: #{e.message}", {
        "git_sha": git_sha,
        "code.namespace": self.class.name,
        "code.function": __method__,
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
      manifest = UIManifest.find_by(sha: git_sha)&.manifest

      manifest
    ensure
      if start_time.present?
        result = manifest.present? ? "success" : "missing"
        GitHub.dogstats.distribution("ui.gh.manifest.get_manifest_from_mysql.duration", Time.now - start_time, tags: ["result:#{result}"])
      end
    end

    sig { params(target: String).returns(T.nilable(SHA)) }
    def self.get_fallback_sha(target:)
      entry = @sha_fallback[target]

      # Use the fallback if it's present and not expired
      if entry.present? && entry[:expires_at] > Time.now
        return entry[:sha]
      end

      # Otherwise remove the fallback and return nil
      @sha_fallback.delete(target)
      nil
    end

    sig { params(target: Target, git_sha: SHA, manifest: ManifestData).returns(ManifestData) }
    def self.set(target:, git_sha:, manifest:)
      raise "Expected 'alloy' data in UI manifest" unless manifest.key?("alloy")
      # Store in MySQL first for reliable fallbacks
      UIManifest.upsert({ target: target, sha: git_sha, manifest: manifest })

      # Update Redis
      set_in_redis(target: target, git_sha: git_sha, manifest: manifest)

      # Send prewarm request to Alloy
      prewarm_alloy(manifest)

      GitHub.dogstats.increment("ui.gh.manifest.set.success", tags: ["target:#{target}"])
      manifest
    end

    sig { params(git_sha: SHA, manifest: ManifestData, target: T.nilable(Target)).void }
    def self.set_in_redis(git_sha:, manifest:, target: nil)
      redis.set("#{REDIS_SHA_MANIFEST_KEY_PREFIX}#{git_sha}", manifest.to_json)
      redis.set("#{REDIS_TARGET_SHA_KEY_PREFIX}#{target}", git_sha) if target.present?
    rescue StandardError => e # rubocop:todo Lint/GenericRescue
      GitHub.dogstats.increment("ui.gh.manifest.set.failure", tags: ["target:#{target}", "type:redis"])
      GitHub.logger.error("Redis error when setting manifest: #{e.message}", {
        "target": target,
        "git_sha": git_sha,
        "code.namespace": self.class.name,
        "code.function": __method__,
      })
    end

    sig { void }
    def self.clear
      @manifest_store = {}
      @sha_fallback = {}
      GitHubUI::ManifestStore.redis.flushall
    end

    sig { returns(::Redis) }
    def self.redis
      @github_ui_deploys_redis ||= T.let(::Redis.new(GitHub.read_redis_config("config/redis_github_ui_deploys.yml")), T.nilable(::Redis))
    end

    sig { params(manifest: ManifestData).void }
    def self.prewarm_alloy(manifest)
      fingerprinted_manifest = manifest.dig("alloy", "manifest")
      raise "Missing 'manifest' key in 'alloy' data" if fingerprinted_manifest.blank?

      response = Alloy::Warmup.new(fingerprinted_manifest).call
      unless response.success?
        raise "Failed to warm up Alloy manifest: #{response.status} #{response.body}"
      end
    end

    sig { params(git_sha: String).returns(T.nilable(ManifestData)) }
    def self.get_manifest_from_cdn(git_sha:)
      start_time = Time.now

      # Fetch the manifest from the CDN. Load from the Rails host if no CDN is set
      manifest_url = "#{GitHub.asset_host_url.presence || GitHub.url}/assets/ui-manifest-#{git_sha}.json"
      response = GitHub::FaradayClient::External.new.get(manifest_url)
      manifest = response.body

      # Parse the manifest
      manifest_data = if response.success?
        begin
          JSON.parse(manifest)
        rescue JSON::ParserError
          nil
        end
      else
        GitHub.logger.error("Failed to fetch manifest from CDN: #{response.status}", {
          "git_sha": git_sha,
          "code.namespace": self.class.name,
          "code.function": __method__,
        })
        nil
      end

      # Cache the manifest in Redis
      set_in_redis(git_sha: git_sha, manifest: manifest_data) if manifest_data.present?
      manifest_data
    ensure
      if start_time.present?
        result = manifest_data.present? ? "success" : "missing"
        GitHub.dogstats.distribution("ui.gh.manifest.get_manifest_from_cdn.duration", Time.now - start_time, tags: ["result:#{result}"])
      end
    end
  end
end
