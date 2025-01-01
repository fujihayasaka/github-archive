# typed: false
# frozen_string_literal: true

module Repository::MigrationDependency

  # Repository import has started.
  def importing_started!
    GitHub.job_coordination_redis.set(
      migration_cache_key,
      true.to_s,
      # This is to avoid stuck repos in importing state
      ex: 6.hours.to_i)
  end

  # Repository import has finished.
  def importing_stopped!
    GitHub.job_coordination_redis.del(migration_cache_key)
  end

  # Is any of our import tooling working on this?
  def is_importing?
    return false if feature_enabled?(:skip_model_importing_check_on_old_repositories) && created_at.present? && created_at < 90.days.ago

    GitHub.job_coordination_redis.exists(migration_cache_key)
  rescue *GitHub::Config::Redis::REDIS_DOWN_EXCEPTIONS, ::Redis::BaseError => e
    # If redis is unavailable (which is rare), we should assume that we're not importing.
    false
  end

  def migration_cache_key
    "repository:migration:importing:#{repository.id}"
  end
end
