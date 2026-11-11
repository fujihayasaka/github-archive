# typed: true
# frozen_string_literal: true

class DatabaseSelector
  class LastOperations
    def self.from_session(session, cookies = nil)
      new(SessionPersistence.new(session, cookies))
    end

    def self.from_token(token)
      digest = OpenSSL::Digest::SHA256.hexdigest(token)

      # If the provided token is an Internal Exchange Token, we don't have access to the plaintext of the user-provided
      # access token, which is the thing upon which we tracking writes.  Instead, we need to extract the hash of that
      # token from the JWT claims and transcode it for usage in last operations cache keys.
      if GitHub::Authnd::InternalExchangeToken.valid_token?(token)
        digest = digest_from_internal_exchange_token(token)
      end

      cache_key = build_cache_key(type: "token-auth", digest: digest)
      new(CachePersistence.new(cache_key))
    end

    # Public: Records the latest writes for a freshly granted OAuth code, keyed by the code itself rather than by an
    # actor token. This lets the code -> access-token exchange (OauthAccess::Provider#access_for_code) ask "has the
    # replica caught up to the GTIDs we wrote during OauthAccess#grant?" before reading oauth_accesses on the replica,
    # and fall back to the primary if it hasn't.
    #
    # Differences from #from_token:
    # * Scope is the OAuth code, not an actor. Two different requests redeeming the same code see the same entry; an
    #   actor's other reads are unaffected. The cache key namespace is separate (`replica-read:oauth-code:...`) so
    #   there's no collision with token-keyed entries.
    # * The consumer does an exact GTID check via DatabaseSelector, not the middleware's time-bounded "force primary
    #   for N seconds after a write" heuristic. Freshness is determined by GTID position, not wall clock.
    # * The entry's effective lifetime is bounded by how quickly OAuth codes get redeemed (p99 ~10s -- see
    #   'oauth_access.code_lookup.age_ms' in Datadog), not by the 30s LastOperations DEFAULT_TTL.
    #
    # Each call writes to every regional cache via LastOperations.set, so the memcache `set` rate added by enabling
    # this path is roughly: OAuth grant rate x number of regional caches.
    sig { params(code: String).returns(LastOperations) }
    def self.from_oauth_code(code)
      digest = OpenSSL::Digest::SHA256.hexdigest(code)
      cache_key = build_cache_key(type: "oauth-code", digest: digest)
      new(CachePersistence.new(cache_key))
    end

    def self.from_creds(login)
      cache_key = build_cache_key(type: "basic-auth", digest: OpenSSL::Digest::SHA256.hexdigest(login))
      new(CachePersistence.new(cache_key))
    end

    def self.from_job(job)
      new(JobPersistence.new(job))
    end

    def self.from_hydro_message_job(job)
      new(HydroMessageJobPersistence.new(job))
    end

    def self.from_hydro_message(message)
      new(HydroMessagePersistence.new(message))
    end

    def self.empty
      new(NullPersistence.new)
    end

    def self.with_static_replication_state(replication_state, &block)
      if replication_state
        new(NullPersistence.new(replication_state)).with_static_replication_state(&block)
      else
        block.call
      end
    end

    # Fetch LastOperations from an `Api::RequestCredentials` object.
    def self.from_request_creds(creds)
      if creds.token
        from_token(creds.token)
      elsif creds.login
        from_creds(creds.login)
      else
        new(NullPersistence.new)
      end
    end

    def initialize(persistence)
      @persistence = persistence
    end

    def last_write_timestamp
      return @last_write_timestamp if defined?(@last_write_timestamp)
      @last_write_timestamp = Timestamp.to_time(last_writes.values.map { |w| w[:time] }.max.to_i)
    end

    def last_writes
      @last_writes ||= persistence.read
    end

    def track_writes
      return yield if ReplicationState.current.present?

      ReplicationState.current = ReplicationState.new(last_writes)

      begin
        yield
      ensure
        latest_writes = ReplicationState.current
        persistence.write(latest_writes.to_hash)
        ReplicationState.current = nil
      end
    end

    def with_static_replication_state
      return yield if ReplicationState.current.present?

      ReplicationState.current = ReplicationState.new(last_writes, static: true)

      begin
        yield
      ensure
        ReplicationState.current = nil
      end
    end

    def store_latest_writes
      @last_writes = latest_writes
      persistence.write(last_writes)
    end

    attr_reader :persistence

    sig { params(type: T.any(String, Symbol), digest: String).returns(String) }
    def self.build_cache_key(type:, digest:)
      "api:replica-read:#{type}:v3:#{digest}"
    end
    private_class_method :build_cache_key

    private_class_method def self.digest_from_internal_exchange_token(token)
      meta = GitHub::Authnd::InternalExchangeToken.unsafe_token_metadata(token)

      # This is the base64-encoded SHA256 digest of the token plaintext, which is used for all storage in `hashed_token`
      # columns in MySQL.
      #
      #  ref: https://github.com/github/github/blob/7c2be3a0fc079fa3dd80e432b2c98febca835b58/packages/access_tokens/app/public/access_tokens.rb#L36
      base64_hash = meta["token.hash"]

      # The cache keys used via DatabaseSelector::LastOperations expect the SHA256 digest to be hex-encoded.  So we
      # need to transcode here.
      Digest.hexencode(Base64.decode64(base64_hash))
    end

    private

    def latest_writes
      Hash.new.tap do |latest_writes|
        now = Timestamp.from_time(Time.now)

        # Drop anything that's older than 30 seconds
        # since we don't care about it anymore.
        last_writes.each do |cluster, write|
          if now - write[:time] < 30_000
            latest_writes[cluster] = write
          end
        end

        ApplicationRecord.clusters.each do |cluster|
          if last_gtid = cluster.connection.last_gtid
            cluster.cluster_names.each do |cluster_name|
              latest_writes[cluster_name] = { gtid: last_gtid, time: now }
            end
          end
        end
      end
    end
  end

  class CachePersistence
    DEFAULT_TTL = 30.seconds

    # Client for the :ryow partition (bidirectional, proxy-routed) — non-blocking for writes
    def self.ryow_partition_cache_client
      return @ryow_partition_cache_client if defined?(@ryow_partition_cache_client)

      @ryow_partition_cache_client = begin
        GitHub::Cache::ClientBuilder.non_blocking_client_for(
          partition: :ryow,
          sites: [GitHub.server_site],
        )
      rescue => e
        Failbot.report(e, context: { location: "CachePersistence.ryow_partition_cache_client" })
        nil
      end
    end

    # Client for the :ryow partition — blocking for reads
    def self.ryow_partition_read_client
      return @ryow_partition_read_client if defined?(@ryow_partition_read_client)

      @ryow_partition_read_client = begin
        GitHub::Cache::ClientBuilder.client_for(
          partition: :ryow,
          sites: [GitHub.server_site],
        )
      rescue => e
        Failbot.report(e, context: { location: "CachePersistence.ryow_partition_read_client" })
        nil
      end
    end

    def self.ryow_partition_enabled?
      GitHub.kube? && ENV["MEMCACHED_PROXY_ENABLED"] == "true"
    end

    def self.ryow_read_from_partition_enabled?
      ryow_partition_enabled? &&
        FeatureFlag.vexi.enabled?("ryow-azure-memcached-read-from-partition", default: false)
    end

    def initialize(cache_key)
      @cache_key = cache_key
    end

    def read
      value =
        if self.class.ryow_read_from_partition_enabled?
          read_from_ryow_partition || GitHub.cache.get(cache_key)
        else
          GitHub.cache.get(cache_key)
        end

      if value
        GitHub::JSON.parse(value).deep_symbolize_keys
      else
        {}
      end
    end

    def write(value)
      serialized_value = value.to_json
      GitHub.cache.set(cache_key, serialized_value, DEFAULT_TTL)
      GitHub.regional_caches.each do |_, region_cache|
        region_cache.set(cache_key, serialized_value, DEFAULT_TTL)
      end

      replicate_to_remote_region_caches(serialized_value)
    end

    private

    # Bidirectional replication via :ryow partition (proxy-routed)
    def replicate_to_remote_region_caches(serialized_value)
      return unless GitHub::AppEnvironment.production?
      return unless self.class.ryow_partition_enabled?
      return unless FeatureFlag.vexi.enabled?("ryow-azure-memcached-dual-write", default: false)

      client = self.class.ryow_partition_cache_client
      return unless client

      begin
        client.set(cache_key, serialized_value, DEFAULT_TTL)
      rescue => e
        Failbot.report(e, context: { location: "LastOperations#replicate_to_remote_region_caches" })
      end
    end

    # Reads from the :ryow partition. Returns nil on failure so caller can fall back to global cache.
    def read_from_ryow_partition
      client = self.class.ryow_partition_read_client
      return nil unless client

      client.get(cache_key)
    rescue => e
      Failbot.report(e, context: { location: "LastOperations#read_from_ryow_partition" })
      nil
    end

    attr_reader :cache_key
  end

  class NullPersistence
    def initialize(static_value = {})
      @static_value = static_value
    end

    def read
      static_value
    end

    def write(*)
      # No-op
    end

    private

    attr_reader :static_value
  end

  class SessionPersistence
    def initialize(session, cookies = nil)
      @session = session
      @cookies = cookies
    end

    def read
      session[:last_gtids]&.deep_symbolize_keys || {}
    end

    def write(value)
      session[:last_gtids] = value if !session.respond_to?(:enabled?) || session.enabled?

      # Set cookie to track when a write operation occurred for GLB routing
      # Calculate timestamp from the latest write in the value hash
      if @cookies && value.is_a?(Hash)
        times = value.values.filter_map { |w| w[:time] if w.is_a?(Hash) }
        max_time = times.max
        if max_time
          @cookies[:last_write_ms] = {
            value: Timestamp.from_time(Timestamp.to_time(max_time)).to_s,
            secure: true,
            httponly: true,
          }
        end
      end
    end

    private

    attr_reader :session
  end

  class JobPersistence
    def initialize(job)
      @job = job
    end

    def read
      GitHub.dogstats.increment(
        "github.active_job.replication_state",
        tags: job.all_stats_tags.concat(["tracked:#{!!job.tracked_replication_state}"])
      )

      if job.tracked_replication_state
        job.tracked_replication_state
      else
        Naive.for(time: job.initially_enqueued_at)
      end
    end

    def write(*)
      # No-op since the only time the replication state is read from the job is at the start of execution.
      # If the job is retried for some reason we want it to use the original replication state rather than
      # a later replication state which could mean excessive waiting.
    end

    private

    attr_reader :job
  end

  class HydroMessagePersistence
    def initialize(message)
      @message = message
    end

    def read
      GitHub.dogstats.increment(
        "github.stream_processor.replication_state",
        tags: ["topic:#{message.topic}", "tracked:#{message.headers.key?("replication_state")}"]
      )

      if message.headers.key?("replication_state")
        JSON.parse(message.headers["replication_state"]).deep_symbolize_keys
      else
        Naive.for(time: Time.at(message.timestamp))
      end
    end

    def write(*)
      # No-op because the only time the replication state is read from the message is at the start of
      # message processing. If the message is retried for some reason we want it to use the original
      # replication state rather than a later replication state which could mean excessive waiting.
    end

    private

    attr_reader :message
  end

  class HydroMessageJobPersistence
    def initialize(job)
      @job = job
    end

    def read
      GitHub.dogstats.increment(
        "github.hydro_message_job.replication_state",
        tags: job.all_stats_tags.concat(["tracked:#{job.headers.key?("replication_state")}"])
      )

      if job.headers.key?("replication_state")
        JSON.parse(job.headers["replication_state"]).deep_symbolize_keys
      else
        Naive.for(time: Time.at(job.timestamp))
      end
    end

    def write(*)
      # No-op since the only time the replication state is read from the job is at the start of execution.
      # If the job is retried for some reason we want it to use the original replication state rather than
      # a later replication state which could mean excessive waiting.
    end

    private

    attr_reader :job
  end

  class Naive
    def self.for(time:)
      ApplicationRecord.clusters.each_with_object({}) do |cluster, result|
        result[cluster.cluster_name] = { gtid: nil, time: Timestamp.from_time(time) }
      end
    end
  end
end
