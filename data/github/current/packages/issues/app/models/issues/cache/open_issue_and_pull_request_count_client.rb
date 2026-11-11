# typed: strict
# frozen_string_literal: true

class Issues::Cache::OpenIssueAndPullRequestCountClient
  extend T::Generic
  include GitHub::RemoteCache::Preset

  SourceKeyType = type_member { { fixed: Integer } }
  SourceValueType = type_member { { fixed: [Integer, Integer] } }

  sig { params(repo_ids: T::Array[Integer]).void }
  def initialize(repo_ids)
    @repo_ids = repo_ids
  end

  sig { override.returns(Symbol) }
  def cache_key_name
    :open_issue_and_pr_count_for_repo
  end

  sig { override.returns(T::Array[SourceKeyType]) }
  def source_keys
    @repo_ids
  end

  sig { override.params(source_key: SourceKeyType).returns(String) }
  def cache_key_id(source_key)
    "repo_id:#{source_key}"
  end

  sig { override.returns(Integer) }
  def ttl
    [10, (FeatureFlag.vexi.percentage_of_actors_value_or_raise(:open_issue_and_pr_count_caching_ttl) * 100).to_i].max # rubocop:disable GitHub/FeatureManagement/NoVexiNonStandardUsage
  end

  sig { override.returns(T::Boolean) }
  def enabled?
    true
  end

  sig { override.returns(SourceValueType) }
  def fallback
    [0, 0]
  end

  sig { override.returns(T::Array[T.class_of(StandardError)]) }
  def resiliency_error_types
    GitHub::ResilienceMixin::DATABASE_ERROR_TYPES_ALLOWLIST
  end

  sig { override.returns(T::class_of(GitHub::RemoteCache::NumericArraySerializer)) }
  def serializer
    GitHub::RemoteCache::NumericArraySerializer
  end

  sig { override.returns(GitHub::RemoteCache::Client::RolloutMode) }
  def rollout_mode
    if FeatureFlag.vexi.enabled?(:open_issue_and_pr_count_caching_disable_shadow_mode, default: false)
      GitHub::RemoteCache::Client::RolloutMode::ReturnCacheValueWithBaseTelemetry
    else
      GitHub::RemoteCache::Client::RolloutMode::ReturnSourceValueWithExtendedTelemetry
    end
  end

  private

  sig { override.returns(GitHub::RemoteCache::Client) }
  def cache_client
    Issues::Cache.client
  end
end
