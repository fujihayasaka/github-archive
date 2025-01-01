# typed: true
# frozen_string_literal: true

# Note: this is exploratory code for navbar counter caching invalidation. It is not yet ready for broad production use.
# Don't copy/paste this code or use it in production otherwise. See https://github.com/github/data-model/issues/1 for details.

class RedisCacheInvalidator
  def self.counter_cache_key(parts)
    parts.prepend("repo_navbar").join("-")
  end

  def self.invalidate_repo_navbar_issue_counter_cache(repo_id, event)
    repo_actor = "Repository:#{repo_id}"

    return unless FeatureFlag.vexi.enabled?("navbar_counter_caching_invalidation", repo_actor, default: false)
    return unless FeatureFlag.vexi.enabled?("navbar_counter_caching_backend_redis", repo_actor, default: false)

    # Datadog metric tags

    # In the future, we might do a cache update instead of just invalidating the cache. So,
    # we add an operation_type tag from the start and will change to "operation_type:update"
    # if we decide to do an update instead of invalidation.
    metric_tags = ["operation_type:invalidation", "event:#{event}"]

    # Add tag with the repo ID so that we can track the number of invalidations per repo
    # for a small number of repos. Tracking for all repos would make the Datadog metric
    # too expensive.
    if repo_id && FeatureFlag.vexi.enabled?("navbar_hits_details", repo_actor, default: false)
      metric_tags << "repo_id:#{repo_id}"
    end

    # Record starting values for MySQL, Memcached, Redis, and Timer tracking
    mysql_queries_start = GitHub::MysqlInstrumenter.query_count
    mysql_time_start = GitHub::MysqlInstrumenter.query_time
    memcached_queries_start = Memcached::Rails.query_count
    memcached_time_start = Memcached::Rails.query_time
    redis_queries_start = ::Redis::Client.query_count
    redis_time_start = ::Redis::Client.query_time
    timer = ::Timer.start

    # Construct the cache key based on repo ID
    cache_key = RedisCacheInvalidator.counter_cache_key(["open_issue_count", "viewer-anon-or-not-spammy", "repo_id:#{repo_id}"])

    # Invalidate the cache for the repo by deleting the cache key and rescuing exceptions.
    begin
      GitHub.mysql_cache_redis.del(cache_key)
      metric_tags << "redis_error:false"
    rescue *GitHub::Config::Redis::REDIS_DOWN_EXCEPTIONS => e
      GitHub.logger.error("Failed to delete Redis cache key #{cache_key}", { exception: e })
      metric_tags << "redis_error:true"
    end

    timer.stop
    mysql_queries = GitHub::MysqlInstrumenter.query_count - mysql_queries_start
    mysql_time = GitHub::MysqlInstrumenter.query_time - mysql_time_start
    memcached_queries = Memcached::Rails.query_count - memcached_queries_start
    memcached_time = Memcached::Rails.query_time - memcached_time_start
    redis_queries = ::Redis::Client.query_count - redis_queries_start
    redis_time = ::Redis::Client.query_time - redis_time_start

    GitHub.dogstats.distribution("github.nav_bar.issue_count.invalidation.time", timer.elapsed_ms(5), tags: metric_tags)
    GitHub.dogstats.distribution("github.nav_bar.issue_count.invalidation.cpu_time", timer.elapsed_cpu_ms(5), tags: metric_tags)
    GitHub.dogstats.distribution("github.nav_bar.issue_count.invalidation.cpu_thread_time", timer.elapsed_thread_cpu_ms(5), tags: metric_tags)
    GitHub.dogstats.distribution("github.nav_bar.issue_count.invalidation.idle_time", timer.elapsed_idle_ms(5), tags: metric_tags)
    GitHub.dogstats.distribution("github.nav_bar.issue_count.invalidation.mysql_queries", mysql_queries, tags: metric_tags)
    GitHub.dogstats.distribution("github.nav_bar.issue_count.invalidation.mysql_time", mysql_time, tags: metric_tags)
    GitHub.dogstats.distribution("github.nav_bar.issue_count.invalidation.memcached_queries", memcached_queries, tags: metric_tags)
    GitHub.dogstats.distribution("github.nav_bar.issue_count.invalidation.memcached_time", memcached_time, tags: metric_tags)
    GitHub.dogstats.distribution("github.nav_bar.issue_count.invalidation.redis_queries", redis_queries, tags: metric_tags)
    GitHub.dogstats.distribution("github.nav_bar.issue_count.invalidation.redis_time", redis_time, tags: metric_tags)
  end
end

GitHub.subscribe(/issue\.(create|destroy|transform_to_pull)/) do |event, _, _, _, payload|
  repo_id = payload[:repo_id]
  next unless repo_id

  RedisCacheInvalidator.invalidate_repo_navbar_issue_counter_cache(repo_id, event)
end

GitHub.subscribe(/issue\.event\.(closed|reopened|converted_to_discussion)/) do |event, _, _, _, payload|
  repo_id = payload[:repository_id]
  next unless repo_id
  next if payload[:pull_request_id]

  RedisCacheInvalidator.invalidate_repo_navbar_issue_counter_cache(repo_id, event)
end
