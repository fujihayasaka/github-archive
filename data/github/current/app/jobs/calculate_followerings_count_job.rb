# typed: true
# frozen_string_literal: true

# Public: Recalculates the cached number of followers/followees of users that are followed by or
# follow another user. This is used when a user's spammy or suspended status changes. We hide
# spammy and suspended users, so this number has to match.
#
# The methods that calculate the follower/following count already know to exclude spammy users. We
# just have to run them.
class CalculateFolloweringsCountJob < ApplicationJob
  include ActiveJob::InitiallyEnqueuedAt

  queue_as :calculate_followerings_count

  retry_on_dirty_exit

  BATCH_SIZE = 1000

  # Public: Run the job to update follower and following counts.
  #
  # user_id - the Integer database ID of a User record whose counts should be updated
  # cascade - whether or not to update the counts of all the followers and followed users of the
  #           specified user; Boolean, defaults to true
  #
  # Returns nothing.
  def perform(user_id,
    cascade = true,
    following_offset = 0,
    follower_offset = 0,
    start_time = initially_enqueued_at)

    user = ActiveRecord::Base.connected_to(role: :reading) { User.find_by(id: user_id) }
    return unless user

    # Only update the current user on the initial call, if we are on a nested cascade call, we can ignore.
    if first_batch?(follower_offset, following_offset)
      user.followers_count!
      user.following_count!
    end

    if cascade
      GitHub.dogstats.distribution_time("follow_count.time", tags: ["follow_aggregate_count:total_batch"]) do
        need_to_requeue_followers, follower_offset = update_followers(user, follower_offset)
        need_to_requeue_following, following_offset = update_followings(user, following_offset)

        if need_to_requeue_followers || need_to_requeue_following
          CalculateFolloweringsCountJob.perform_later(user_id, cascade, following_offset, follower_offset, start_time)
        else
          report_duration(start_time)
        end
      end
    end
  end

  def first_batch?(followers_offset, following_offset)
    followers_offset == 0 && following_offset == 0
  end

  def update_followings(user, following_offset)
    # .following performs an inner join on the user table, returning user objects.
    # We filter by following_id here as the inner join pegs the inner result set to the current user_id.
    # Meaning all results will have the user_id equal to the current user, so we then filter by the following ids.
    following = user.following.where("following_id > ?", following_offset).limit(BATCH_SIZE).order(:id)

    following.each do |followed_user|
      begin
        followed_user.followers_count!
      rescue ActiveRecord::RecordNotFound => boom
        Failbot.report(boom)
        next
      end
    end

    if following.size > 0
      following_offset = following.last.id
    end

    requeue = following.size == BATCH_SIZE
    [requeue, following_offset]
  end

  def update_followers(user, follower_offset)
    # .followers performs an inner join on the user table, returning user objects.
    # We filter by user_id here as the inner join pegs the inner result set by the followers table following_id to the current user_id.
    # Meaning all results will have the following_id equal to the current users id, so we then filter by the user ids.
    followers = user.followers.where("user_id > ?", follower_offset).limit(BATCH_SIZE).order(:id)
    followers.each do |follower|
      begin
        follower.following_count!
      rescue ActiveRecord::RecordNotFound => boom
        Failbot.report(boom)
        next
      end
    end

    if followers.size > 0
      follower_offset = followers.last.id
    end

    requeue = followers.size == BATCH_SIZE
    [requeue, follower_offset]
  end

  sig { params(start_time: Time).void }
  def report_duration(start_time)
    duration = (Time.now.utc - start_time) * 1_000
    GitHub.dogstats.distribution(
      "calculate_followerings_count_job.dist.duration",
      duration)
  end
end
