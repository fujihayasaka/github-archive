# typed: strict
# frozen_string_literal: true

require "digest"

class Memex::Cache::OpenMemexProjectsCountClient
  extend T::Generic
  include GitHub::RemoteCache::Preset

  SourceKeyType = type_member { { fixed: [Repository, T.nilable(User)] } }
  SourceValueType = type_member { { fixed: Integer } }

  sig { params(repo: Repository, viewer: T.nilable(User)).void }
  def initialize(repo, viewer)
    @repo = repo
    @viewer = viewer
  end

  sig { override.returns(Symbol) }
  def cache_key_name
    :open_projects_count
  end

  sig { override.params(source_key: SourceKeyType).returns(String) }
  def cache_key_id(source_key)
    repo, viewer = source_key
    memex_projects_ids = repo.memex_project_links.pluck(:memex_project_id)
    memex_ids = MemexProject.where(id: memex_projects_ids).open_projects.order(:id).pluck(:id).join(",")
    memexes_ids_hash = Digest::SHA256.hexdigest(memex_ids)
    "v1:#{repo.id}:#{viewer&.id || "anon"}:#{memexes_ids_hash}"
  end

  sig { override.returns(T::Array[SourceKeyType]) }
  def source_keys
    [[@repo, @viewer]]
  end

  sig { override.returns(Integer) }
  def ttl
    [10, (FeatureFlag.vexi.percentage_of_actors_value_or_raise(:navbar_counter_caching_project_count_ttl) * 100).to_i].max # rubocop:disable GitHub/FeatureManagement/NoVexiNonStandardUsage
  end

  sig { override.returns(T::Boolean) }
  def enabled?
    true
  end

  sig { override.returns(T.class_of(GitHub::RemoteCache::RoundedNumericStalenessObserver)) }
  def staleness_observer
    GitHub::RemoteCache::RoundedNumericStalenessObserver
  end

  sig { override.returns(SourceValueType) }
  def fallback
    0
  end

  sig { override.returns(T.class_of(GitHub::RemoteCache::NumericSerializer)) }
  def serializer
    GitHub::RemoteCache::NumericSerializer
  end

  sig { override.returns(GitHub::RemoteCache::Client::RolloutMode) }
  def rollout_mode
    if FeatureFlag.vexi.enabled?(:navbar_counter_caching_project_count_shadow, @repo, default: false)
      GitHub::RemoteCache::Client::RolloutMode::ReturnCacheValueWithBaseTelemetry
    else
      GitHub::RemoteCache::Client::RolloutMode::ReturnSourceValueWithExtendedTelemetry
    end
  end

  sig { override.returns(T::Array[T.class_of(StandardError)]) }
  def resilience_error_types
    GitHub::ResilienceMixin::DATABASE_ERROR_TYPES_ALLOWLIST
  end

  private

  sig { override.returns(GitHub::RemoteCache::Client) }
  def cache_client
    Planning::Cache.client
  end
end
