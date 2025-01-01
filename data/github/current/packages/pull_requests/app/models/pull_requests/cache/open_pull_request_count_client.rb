# typed: strict
# frozen_string_literal: true

class PullRequests::Cache::OpenPullRequestCountClient
  extend T::Generic
  include GitHub::RemoteCache::Preset

  CachedType = type_member { { fixed: Numeric } }

  TTL = T.let(
    -> (count) { count > 25 ? 300.seconds : 100.seconds },
    T.proc.params(count: T.untyped).returns(Integer)
  )

  sig { params(repo: Repository, viewer: T.nilable(User)).void }
  def initialize(repo, viewer)
    @repo = repo
    @viewer = viewer
  end

  sig { override.returns(Symbol) }
  def cache_key_name
    :navbar_open_pull_request_count_anon_non_spammy_viewer
  end

  sig { override.returns(String) }
  def cache_key_id
    "repo_id:#{@repo.id}"
  end

  # Determine the TTL for caching the counter's value based on the value itself.
  #
  # The idea is to take advantage of how we display the counter depending its value:
  #   - values under 1000 get displayed in full precision,
  #   - values between 1000 and 5000 get rounded to the closest 100, and
  #   - values over 5000 are displayed as 5k+.
  #
  # For example:
  #   - 424, 120, and 7 all get displayed as such,
  #   - 1156, 1182, and 1231 all get displayed as 1.2k, and
  #   - 5003, 6430, and 10243 all get displayed as 5k+.
  #
  # With that in mind, we can cache some values for longer because we know that small changes
  # in the value won't affect the displayed counter.
  #
  # For now, we decided to cache the counter for a longer time period only if there are more
  # than 25 open pull requests. 25 is the number of pull requests that are shown on a single
  # page in the web UI. So, we make an assumption that stale values will be more visible and
  # affect the UX if they happen when all the open pull requests fit on a single page.
  sig { override.returns(T.proc.params(count: T.untyped).returns(Integer)) }
  def ttl
    TTL
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
    !FeatureFlag.vexi.enabled?(:navbar_counter_caching_pull_requests_count_shadow, @repo, default: false)
  end

  sig { override.returns(T::Array[T.class_of(StandardError)]) }
  def resiliency_error_types
    GitHub::ResilienceMixin::DATABASE_ERROR_TYPES_ALLOWLIST
  end

  private

  sig { override.returns(GitHub::RemoteCache::Client) }
  def cache_client
    PullRequests::Cache.client
  end
end
