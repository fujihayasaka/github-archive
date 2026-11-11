# typed: strict
# frozen_string_literal: true

class Issues::Cache::OpenIssueCountClient
  extend T::Generic
  include GitHub::RemoteCache::Preset

  SourceKeyType = type_member { { fixed: Integer } }
  SourceValueType = type_member { { fixed: Integer } }

  sig { params(repo: Repository, viewer: T.nilable(User)).void }
  def initialize(repo, viewer)
    @repo = repo
    @viewer = viewer
  end

  sig { override.returns(Symbol) }
  def cache_key_name
    :open_issue_count_for_repo
  end

  sig { override.params(source_key: SourceKeyType).returns(String) }
  def cache_key_id(source_key)
    "repo_id:#{source_key}"
  end

  sig { override.returns(T::Array[SourceKeyType]) }
  def source_keys
    [@repo.id]
  end

  sig { override.returns(Integer) }
  def ttl
    100
  end

  # For now, we're restricting cache usage to a specific case of possible execution
  # paths. This specific case is luckily the common case:
  #   - the repo is not spammy, AND
  #   - the viewer is not the owner of the repo or a site admin, AND
  #   - the viewer is not logged in or is logged in and not spammy
  # In that case, the generated SQL query depends only on the repository ID, and not the viewer's ID.
  # So, we can cache the counter and use it for most anonymous and authenticated viewers of that repo.
  sig { override.returns(T::Boolean) }
  def enabled?
    return false if !@repo.persisted?

    logged_in = !@viewer.nil?
    site_admin = @viewer&.site_admin?
    viewer_spammy = @viewer&.spammy?
    repo_spammy = @repo.spammy?
    viewer_owner = @viewer&.id == @repo.owner_id

    return false if repo_spammy   # dont use cache if repo is spammy
    return false if viewer_owner  # show fresh values to repo owners
    return false if site_admin    # show fresh values to site admins

    return true  if !logged_in || !viewer_spammy

    false
  end

  sig { override.returns(SourceValueType) }
  def fallback
    0
  end

  sig { override.returns(T::Array[T.class_of(StandardError)]) }
  def resilience_error_types
    GitHub::ResilienceMixin::DATABASE_ERROR_TYPES_ALLOWLIST
  end

  sig { override.returns(T.class_of(GitHub::RemoteCache::NumericSerializer)) }
  def serializer
    GitHub::RemoteCache::NumericSerializer
  end

  sig { override.returns(GitHub::RemoteCache::StalenessObserver[SourceValueType]) }
  def staleness_observer
    GitHub::RemoteCache::PrimitiveValueStalenessObserver
  end

  sig { override.returns(GitHub::RemoteCache::Client::RolloutMode) }
  def rollout_mode
    if rand < 0.01
      GitHub::RemoteCache::Client::RolloutMode::ReturnSourceValueWithExtendedTelemetry
    else
      GitHub::RemoteCache::Client::RolloutMode::ReturnCacheValueWithBaseTelemetry
    end
  end

  private

  sig { override.returns(GitHub::RemoteCache::Client) }
  def cache_client
    Issues::Cache.client
  end
end
