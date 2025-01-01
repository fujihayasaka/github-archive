# typed: true
# frozen_string_literal: true

# This Job will purge followers records that are associated with users that no longer exist.
class PurgeOrphanedFollowersJob < ApplicationJob

  queue_as :purge_orphaned_followers

  retry_on_dirty_exit

  # This job will run every 24 hours
  schedule interval: 24.hours

  # Don't run more than one of this job at a time
  locked_by timeout: 10.minutes, key: DEFAULT_LOCK_PROC

  BATCH_SIZE = 5000

  # This job is exempt from tenant scoping as we're solely deleting existing associated records
  exempt_from_tenant_context_requirement

  def perform
    start = Following.minimum(:id)
    finish = Following.maximum(:id)
    ranges = (start..finish).each_slice(BATCH_SIZE).map { |slice| slice.first..slice.last }

    orphans = Following.
      from("#{Following.table_name} AS follows").
      joins("LEFT JOIN users AS followers ON follows.user_id = followers.id").
      joins("LEFT JOIN users AS followees ON follows.following_id = followees.id").
      where("followers.id IS NULL or followees.id IS NULL")

    ranges.each do |range|
      batch = Following.throttle do
        orphans.
          where("follows.id BETWEEN ? AND ?", range.first, range.last).
          pluck("follows.following_id, followees.id, follows.user_id, followers.id")
      end

      nonexistent_user_ids = batch.flat_map do |orphan|
        orphan_follower = orphan[0] if orphan[1].nil?
        orphan_followee = orphan[2] if orphan[3].nil?
        [orphan_follower, orphan_followee].compact
      end.uniq

      with_write do
        Following.where("user_id IN (?) OR following_id IN (?)", nonexistent_user_ids, nonexistent_user_ids).delete_all
      end
    end
  end
end
