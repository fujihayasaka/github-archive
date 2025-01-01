# typed: true
# frozen_string_literal: true

class DatabaseSelector
  class LastOperations
    def self.from_session(session)
      new(SessionPersistence.new(session))
    end

    def self.from_token(token)
      cache_key = "api:replica-read:token-auth:v3:#{OpenSSL::Digest::SHA256.hexdigest(token)}"
      new(CachePersistence.new(cache_key))
    end

    def self.from_creds(login)
      cache_key = "api:replica-read:basic-auth:v3:#{OpenSSL::Digest::SHA256.hexdigest(login)}"
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

    def initialize(cache_key)
      @cache_key = cache_key
    end

    def read
      if value = GitHub.cache.get(cache_key)
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
    end

    private

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
    def initialize(session)
      @session = session
    end

    def read
      session[:last_gtids]&.deep_symbolize_keys || {}
    end

    def write(value)
      session[:last_gtids] = value if !session.respond_to?(:enabled?) || session.enabled?
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
