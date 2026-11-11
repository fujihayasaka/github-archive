# typed: strict
# frozen_string_literal: true

class Profiles::RemoveFollowGraphJob < ApplicationJob
  queue_as :remove_follow_graph_on_destroy

  retry_on_dirty_exit

  BATCH_SIZE = 1000
  MAX_THROTTLE_RETRIES = 5

  sig { params(user_id: T.nilable(Integer)).void }
  def perform(user_id)
    return if user_id.nil?

    recalculate_user_ids = []
    invalidate_actor_ids = []

    loop do
      count = 0
      Following.involving(user_id).limit(BATCH_SIZE).each do |following|
        Following.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
          with_write { following.destroy! }
        end

        recalculate_user_ids << following.user_id
        recalculate_user_ids << following.following_id
        invalidate_actor_ids << following.user_id
        count += 1
      end
      break if count < BATCH_SIZE
    end

    recalculate_user_ids.uniq.each do |id|
      CalculateFolloweringsCountJob.enqueue_once_per_interval(
        args: [id, false],
        interval: User::FollowDependency::FOLLOW_CALCULATION_INTERVAL_IN_SECONDS,
      )
    end

    invalidate_actor_ids.uniq.each do |id|
      with_write do
        Conduit::KVBackedCache.invalidate_all_for_you_feed_caches_for(User.new(id: id))
      end
    end
  end
end
