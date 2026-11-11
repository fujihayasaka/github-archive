# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# CleanLocksJob is a periodic maintenance job that clears out expired hash locks
# from locking jobs. These expired locks can't expire themselves, and may have
# been left behind because a job was never enqueued or failed to release its
# lock. This prevents unbounded memory growth of the hash locks in redis.
class CleanLocksJob < ApplicationJob
  queue_as :clean_locks
  schedule interval: 1.hour

  DELETE_BATCH_SIZE = 500

  def perform(...)
    # When flat_key_only is enabled, flat keys self-expire via Redis TTL
    # and there are no hash-based locks to clean up.
    return if FeatureFlag.vexi.enabled?(JobHashLock::FLAT_KEY_ONLY_FLAG, default: false)

    now = Time.now.to_i
    any_flat_key_flag = FeatureFlag.vexi.enabled?(JobHashLock::FLAT_KEY_DUAL_WRITE_FLAG, default: false) ||
      FeatureFlag.vexi.enabled?(JobHashLock::FLAT_KEY_READ_FLAG, default: false)
    redis.scan_each(match: "#{JobHashLock::LOCK_SET_PREFIX}:*") do |lock_key|
      # During flat key migration, flat keys (strings) also match the glob.
      # Only process hash keys; flat keys self-expire via Redis TTL.
      if any_flat_key_flag
        next unless redis.type(lock_key) == "hash"
      end

      to_delete = []
      redis.hscan_each(lock_key, count: 1000) do |key, value|
        ts = value.split(":").first.to_i
        to_delete << key if ts < now
      end

      next if to_delete.empty?

      to_delete.each_slice(DELETE_BATCH_SIZE) do |batch|
        redis.hdel lock_key, *batch
      end
      job_class = lock_key.split(":", 2).last # key doesn't include namespace
      GitHub.dogstats.count("jobs.hash_lock.expire", to_delete.length, tags: ["job_class:#{job_class.underscore}"])
    end
  end

  private

  def redis
    @redis ||= Redis::Namespace.new(JobHashLock::LOCK_SET_NAMESPACE, redis: GitHub.new_job_coord_redis)
  end
end
