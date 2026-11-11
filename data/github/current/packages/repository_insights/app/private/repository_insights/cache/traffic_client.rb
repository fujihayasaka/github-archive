# typed: strict
# frozen_string_literal: true

class RepositoryInsights::Cache::TrafficClient
  extend T::Generic
  include GitHub::RemoteCache::Preset

  # SourceKeyType defines the shape of the input used to generate cache keys.
  # The key is just the repo ID.
  SourceKeyType = type_member { { fixed: Integer } }

  # SourceValueType defines what we're caching. Must match what the serializer handles.
  SourceValueType = type_member { { fixed: MonolithTwirp::ReposInsights::ReposInsights::V1::GetRepoTrafficResponse } }

  sig { params(repo: Repository).void }
  def initialize(repo)
    @repo = repo
  end

  # A symbol identifying this cache for metrics, feature flags, and logging.
  # Shows up in Datadog as `cache_key_name:repos_insights_traffic`.
  sig { override.returns(Symbol) }
  def cache_key_name
    :repos_insights_traffic
  end

  # Converts a source key into the string portion of the Redis key.
  # The full key becomes: "repos_insights:repos_insights_traffic:v1.2.0:repo_id:123"
  sig { override.params(source_key: SourceKeyType).returns(String) }
  def cache_key_id(source_key)
    "v#{MonolithTwirp::Reposinsights::Reposinsights::VERSION}:repo_id:#{source_key}"
  end

  # Returns an array of source keys to fetch. For single-key fetches, return a
  # one-element array. For batch fetches, return multiple keys.
  sig { override.returns(T::Array[SourceKeyType]) }
  def source_keys
    [@repo.id]
  end

  # Time-to-live in seconds. The client caps this at MAX_TTL (24 hours).
  sig { override.returns(Integer) }
  def ttl
    6.hours.to_i
  end

  sig { override.returns(T::Boolean) }
  def enabled?
    true
  end

  # The value returned when the source of truth throws a handled error or cache is disabled.
  # Keep this immutable—the client freezes it when possible.
  sig { override.returns(SourceValueType) }
  def fallback
    MonolithTwirp::ReposInsights::ReposInsights::V1::GetRepoTrafficResponse.new(
      traffic_data: nil,
    )
  end

  # Error types that trigger graceful degradation (return fallback instead of raising).
  # Common choices: DATABASE_ERROR_TYPES_ALLOWLIST for MySQL errors.
  sig { override.returns(T::Array[T.class_of(StandardError)]) }
  def resilience_error_types
    [RepositoryInsights::Twirp::Error, Faraday::Error]
  end

  # The serializer converts Ruby values to/from the binary format stored in Redis.
  # Use built-in serializers when possible, see `GitHub::RemoteCache::Serializer` for details.
  sig { override.returns(T.class_of(RepositoryInsights::Cache::TwirpSerializer)) }
  def serializer
    RepositoryInsights::Cache::TwirpSerializer
  end

  # Controls cache vs source of truth behavior. Start with
  # ReturnSourceValueWithExtendedTelemetry during rollout, then graduate to
  # ReturnCacheValueWithBaseTelemetry once validated.
  sig { override.returns(GitHub::RemoteCache::Client::RolloutMode) }
  def rollout_mode
    GitHub::RemoteCache::Client::RolloutMode::ReturnCacheValueWithBaseTelemetry
  end

  # Staleness observer compares cache vs source values during extended telemetry.
  # Use built-in observers for common types:
  #   - PrimitiveValueStalenessObserver: for strings, numbers, booleans, arrays, hashes
  #   - ApplicationRecordStalenessObserver: for ActiveRecord models
  #   - RoundedNumericStalenessObserver: for counters with display rounding
  # Or implement GitHub::RemoteCache::StalenessObserver for custom comparison logic and telemetry.
  sig { override.returns(T.nilable(GitHub::RemoteCache::StalenessObserver[SourceValueType])) }
  def staleness_observer
    nil
  end

  private

  # Returns the Redis client from the domain's cache module.
  sig { override.returns(GitHub::RemoteCache::Client) }
  def cache_client
    RepositoryInsights::Cache.client
  end
end
