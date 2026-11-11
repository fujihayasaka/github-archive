# typed: true
# frozen_string_literal: true

# Delete any old notifications that are over the limit for the given user
# The offset_item_id that this job uses is a Time in its epoch form (Time#to_i).
# The deletion is based on when entries have been updated, and we look for old ones,
# meaning that each batch continues from the last updated_at value from the previous batch
#
# This job uses its own lock system. Instead of locking for a single job execution, a lock
# is created for the whole sequence of batches, and released once all batches are done. This
# way we avoid new jobs enqueued for a user while a batch sequence is ongoing.
# The lock has a timeout, so even if there is an unknown failure during a sequence it will
# expire allowing the process to start again.
class NotificationEntriesLimitEnforcerJob < BatchedJob
  extend T::Helpers

  class BatchedLock
    attr_reader :key, :ttl, :redis, :tags

    VALUE = "1"

    def initialize(key:, ttl:, tags: [], redis: GitHub.new_job_coord_redis)
      @key = key
      @ttl = ttl
      @tags = tags
      @redis = redis
    end

    def obtain
      redis.set(key, VALUE, ex: ttl.to_i, nx: true).tap do |result|
        if result
          GitHub.dogstats.increment("jobs.batched-lock.obtain", tags: tags)
        else
          GitHub.dogstats.increment("jobs.batched-lock.fail-to-obtain", tags: tags)
        end
      end
    rescue ::Redis::BaseError => e
      false
    end

    def extend_time
      redis.setex(key, ttl.to_i, VALUE).tap do |result|
        if result
          GitHub.dogstats.increment("jobs.batched-lock.extend-time", tags: tags)
        else
          GitHub.dogstats.increment("jobs.batched-lock.fail-to-extend-time", tags: tags)
        end
      end
    rescue ::Redis::BaseError => e
      false
    end

    def release
      redis.del(key).tap do |amount|
        if amount > 0
          GitHub.dogstats.increment("jobs.batched-lock.release", tags: tags)
        end
      end

      true
    rescue ::Redis::BaseError => e
      false
    end
  end

  LOCK_PREFIX = "notifications:limit-enforcer-job:user-id"
  LOCK_TTL = 20.minutes
  BATCH_SIZE = 100

  queue_as :notifications_maintenance

  use_replicas ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::NotificationsEntries

  retry_on_dirty_exit do |job, error|
    job.batched_lock.release
    raise error
  end

  retry_on_recoverable_exceptions do |job, error|
    job.batched_lock.release
    raise error
  end

  resolve_tenant_context do |user_id|
    ActiveRecord::Base.connected_to_many([ApplicationRecord::Collab], role: :reading) do
      user = User.find_by(id: user_id)
      user&.enterprise_managed_business
    end
  end

  around_enqueue do |job, block|
    if in_batch_sequence?
      job.batched_lock.extend_time
      block.call
      next
    end

    if job.batched_lock.obtain
      block.call
    else
      GitHub.logger.info({
        "code.namespace" => job.class.name,
        "code.function" => "around_enqueue",
        "gh.job.name" => job.class.name,
        "gh.job.id" => job.job_id,
        "gh.notification_entries_limit_enforcer_job.lock_not_obtained" => true,
        "gh.notification_entries_limit_enforcer_job.user_id" => job.user_id,
      })
    end
  end

  around_perform do |job, block|
    # skip the job if the feature flag is disabled
    unless FeatureFlag.vexi.enabled?(:notification_entries_limit_enforcer_job, User.new(id: job.user_id), default: false)
      GitHub.logger.info({
        "code.namespace" => job.class.name,
        "code.function" => "around_perform",
        "gh.job.name" => job.class.name,
        "gh.job.id" => job.job_id,
        "gh.notification_entries_limit_enforcer_job.disabled" => true,
        "gh.notification_entries_limit_enforcer_job.user_id" => job.user_id,
      })
      next
    end

    block.call
  rescue StandardError, Aqueduct::Worker::JobKilled => exception
    job.batched_lock.release unless in_batch_sequence?
    raise exception
  end

  def in_batch_sequence?
    options = arguments.last

    if options.is_a?(Hash) && options.with_indifferent_access.key?(:offset_item_id)
      return true
    end

    false
  end

  def next_batch(*args, timestamp: Time.now.utc, offset_item_id: 0, progress: 0, **options)
    user_id = args.first
    offset_id = T.let(offset_item_id, T.nilable(Integer))

    with_read do
      if offset_id == 0
        offset_id = Newsies::NotificationEntry.throttle do
          Newsies::NotificationEntry
            .select(:updated_at)
            .where(user_id: user_id)
            .order(updated_at: :desc)
            .limit(1)
            .offset(Newsies::NotificationEntry::LIMIT_PER_USER)
            .first
            &.updated_at
            &.to_i
        end
      end

      return [] if offset_id.nil? || offset_id == 0

      offset_updated_at = Time.at(offset_id).utc.strftime("%Y-%m-%d %H:%M:%S")

      # Array in the form: [[Integer, Time], ...]
      Newsies::NotificationEntry.throttle do
        Newsies::NotificationEntry
          .where(user_id: user_id)
          .where(Newsies::NotificationEntry.arel_table[:updated_at].lteq(offset_updated_at))
          .order(updated_at: :desc)
          .limit(BATCH_SIZE)
          .pluck(:id, :updated_at)
      end
    end
  end

  def process_batch(batch, *args, **options)
    user_id = args.first
    return unless FeatureFlag.vexi.enabled?(:notification_entries_limit_enforcer_job_deletion, User.new(id: user_id), default: false)

    ids = batch.map(&:first)
    with_write do
      Newsies::NotificationEntry.throttle do
        Newsies::NotificationEntry.where(id: ids).delete_all.tap do |deleted|
          GitHub.dogstats.count("notifications.enforce_entries_limit.deleted", deleted, tags: stat_tags)
          GitHub.logger.info("Deleted notification entries for user", {
            "code.namespace" => self.class.name,
            "code.function" => "process_batch",
            "gh.job.name" => self.class.name,
            "gh.job.id" => job_id,
            "gh.notification_entries_limit_enforcer_job.user_id" => user_id,
            "gh.notification_entries_limit_enforcer_job.deleted_entries" => deleted,
          })
        end
      end
    end
  end

  def next_batch_offset_item_id(batch, *args, **options)
    batch.map(&:last).last&.to_i || 0
  end

  def ensure_perform(finished_successfully:, **options)
    return unless finished_successfully
    batched_lock.release
  end

  def batched_lock
    @batched_lock ||= BatchedLock.new(key: batched_lock_key, ttl: LOCK_TTL, tags: stat_tags)
  end

  def batched_lock_key
    @batched_lock_key ||= "#{LOCK_PREFIX}:#{user_id}"
  end

  def user_id
    @user_id ||= arguments.first
  end

  def stat_tags
    @stat_tags ||= ["class:#{self.class.name&.underscore}", "queue:#{queue_name}"]
  end
end
