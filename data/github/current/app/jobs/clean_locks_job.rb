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
    now = Time.now.to_i
    redis.scan_each(match: "#{JobHashLock::LOCK_SET_PREFIX}:*") do |lock_key|
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
      GitHub.dogstats.count("jobs.hash-lock.expire", to_delete.length, tags: ["job_class:#{job_class.underscore}"])
    end
  end

  private

  def redis
    @redis ||= Redis::Namespace.new(JobHashLock::LOCK_SET_NAMESPACE, redis: GitHub.new_job_coord_redis)
  end
end
