# typed: strict
# frozen_string_literal: true

class PullRequests::Cache::InboxSearchIssueIdsClient
  extend T::Generic
  include GitHub::RemoteCache::Preset

  CACHE_KEY_VERSION = 1
  TTL_SECONDS = 30

  SourceKeyType = type_member { { fixed: String } }
  SourceValueType = type_member { { fixed: T::Array[Integer] } }

  sig { params(current_user: User, phrase: String, page: Integer, per_page: Integer, section: String).void }
  def initialize(current_user:, phrase:, page:, per_page:, section:)
    @current_user = current_user
    @phrase = phrase
    @page = page
    @per_page = per_page
    @section = section
  end

  sig { override.returns(Symbol) }
  def cache_key_name
    :dashboard_surface_inbox_search_issue_ids
  end

  sig { override.params(source_key: SourceKeyType).returns(String) }
  def cache_key_id(source_key)
    source_key
  end

  sig { override.returns(T::Array[SourceKeyType]) }
  def source_keys
    [source_key]
  end

  sig { override.returns(Integer) }
  def ttl
    TTL_SECONDS
  end

  sig { override.returns(T::Boolean) }
  def enabled?
    true
  end

  sig { override.returns(SourceValueType) }
  def fallback
    []
  end

  sig { override.returns(T.class_of(GitHub::RemoteCache::NumericArraySerializer)) }
  def serializer
    GitHub::RemoteCache::NumericArraySerializer
  end

  sig { override.returns(GitHub::RemoteCache::StalenessObserver[SourceValueType]) }
  def staleness_observer
    GitHub::RemoteCache::PrimitiveValueStalenessObserver
  end

  sig { override.returns(GitHub::RemoteCache::Client::RolloutMode) }
  def rollout_mode
    if FeatureFlag.vexi.enabled?(:dashboard_surface_inbox_search_remote_cache_shadow, @current_user, default: false)
      GitHub::RemoteCache::Client::RolloutMode::ReturnCacheValueWithBaseTelemetry
    else
      GitHub::RemoteCache::Client::RolloutMode::ReturnSourceValueWithExtendedTelemetry
    end
  end

  sig { override.returns(T::Array[T.class_of(StandardError)]) }
  def resilience_error_types
    []
  end

  private

  sig { returns(String) }
  def source_key
    phrase_digest = Digest::SHA256.hexdigest(@phrase)
    user_id = @current_user.id

    [
      "v#{CACHE_KEY_VERSION}",
      "user_id:#{user_id}",
      "section:#{@section}",
      "page:#{@page}",
      "per_page:#{@per_page}",
      "phrase_sha256:#{phrase_digest}",
    ].join(":")
  end

  sig { override.returns(GitHub::RemoteCache::Client) }
  def cache_client
    PullRequests::Cache.client
  end
end
