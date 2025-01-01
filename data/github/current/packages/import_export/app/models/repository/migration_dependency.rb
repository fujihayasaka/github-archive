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
    GitHub.job_coordination_redis.exists(migration_cache_key)
  rescue Redis::TimeoutError
    # If redis is unavailable (which is rare), we should assume that we're not importing.
    false
  end

  def migration_cache_key
    "repository:migration:importing:#{repository.id}"
  end
end
