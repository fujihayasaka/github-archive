# typed: strict
# frozen_string_literal: true

require "digest"

class Memex::Cache::OpenMemexProjectsCountClient
  extend T::Generic
  include GitHub::RemoteCache::Preset

  CachedType = type_member { { fixed: Numeric } }

  sig { params(repo: Repository, viewer: T.nilable(User)).void }
  def initialize(repo, viewer)
    @repo = repo
    @viewer = viewer
  end

  sig { override.returns(Symbol) }
  def cache_key_name
    :open_projects_count
  end

  sig { override.returns(String) }
  def cache_key_id
    memex_projects_ids = @repo.memex_project_links.pluck(:memex_project_id)
    memex_ids = MemexProject.where(id: memex_projects_ids).open_projects.order(:id).pluck(:id).join(",")
    memexes_ids_hash = Digest::SHA256.hexdigest(memex_ids)
    "v1:#{@repo.id}:#{@viewer&.id || "anon"}:#{memexes_ids_hash}"
  end

  sig { override.returns(Integer) }
  def ttl
    [10, (FeatureFlag.vexi.percentage_of_actors_value_or_raise(:navbar_counter_caching_project_count_ttl) * 100).to_i].max # rubocop:disable GitHub/FeatureManagement/NoVexiNonStandardUsage
  end

  sig { override.returns(T::Boolean) }
  def enabled?
    true
  end

  sig { override.returns(CachedType) }
  def fallback
    0
  end

  sig { override.returns(T.class_of(GitHub::RemoteCache::RoundedNumericSerializer)) }
  def serializer
    GitHub::RemoteCache::RoundedNumericSerializer
  end

  sig { override.returns(T::Boolean) }
  def shadow?
    !FeatureFlag.vexi.enabled?(:navbar_counter_caching_project_count_shadow, @repo, default: false)
  end

  sig { override.returns(T::Array[T.class_of(StandardError)]) }
  def resiliency_error_types
    GitHub::ResilienceMixin::DATABASE_ERROR_TYPES_ALLOWLIST
  end

  private

  sig { override.returns(GitHub::RemoteCache::Client) }
  def cache_client
    Planning::Cache.client
  end
end
