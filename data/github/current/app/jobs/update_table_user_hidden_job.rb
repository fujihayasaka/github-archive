# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class UpdateTableUserHiddenJob < ApplicationJob
  queue_as :update_table_user_hidden

  include GitHub::CacheLock
  class CouldNotObtainLock < StandardError; end

  retry_on CouldNotObtainLock
  retry_on_dirty_exit

  attr_reader :user_id

  # Updates the content tables, ensuring we're only running a single job
  # at a time per user.
  #
  # user_id - The User ID for the user whose content we're updating
  # tables - The table or tables containing the content we're updating
  def perform(user_id, tables)
    @user_id = user_id
    tables = Array.wrap(tables)
    completed_tables = []

    return unless user
    raise CouldNotObtainLock unless obtain_lock

    user_hidden = user.content_hidden?

    tables.each do |table|
      with_write { Spam::UpdateUserHidden.update_table(table, user_hidden, user_id) }
      completed_tables << table
    end

    ToggleHiddenUserInNotificationsJob.perform_later(user.id, user_hidden ? "hide" : "unhide")
    ToggleIssueNotificationsForSpammyUsersJob.perform_later(user.id, nil)
    user.calculate_followerings_count

    CalculateStarsCountJob.perform_later(user)
    ClearGraphDataOnSpammyJob.perform_later(user.id)
    UserForkCountJob.perform_later(user.id)

    if user_hidden
      PurgeSpammyFromSearchIndexJob.perform_later(user.id)
      DelistSpammyActionFromMarketplaceJob.perform_later(user: user)
      RecalculateUserDiscussionsJob.perform_later(user) if GitHub.discussions_available_on_platform?
      if GitHub.sponsors_enabled?
        DelistSpammySponsorsListingJob.perform_later(sponsorable: user)
        with_write do
          user.potential_sponsorships_as_sponsorable.destroy_all
          user.potential_sponsorships_as_sponsor.destroy_all
        end
      end
    else
      RestoreUserFromSpammyJob.perform_later(user.id)
      RelistNonSpammySponsorsListingJob.perform_later(sponsorable: user) if GitHub.sponsors_enabled?
    end
  rescue UpdateTableUserHiddenJob::CouldNotObtainLock => e
    dogstats_tags = ["error:could_not_obtain_lock"]
    if T.must(completed_tables).any?
      # The job has completed some work before error, requeue new job with new args.
      requeue(tables: tables - completed_tables, dogstats_tags: dogstats_tags)
    else
      # The job didn't do any work, reque through ActiveJob to manage retry attempts.
      GitHub.dogstats.increment("data.table_user_hidden_requeued", tags: dogstats_tags)
      raise e
    end
  rescue Freno::Throttler::CircuitOpen, Freno::Throttler::WaitedTooLong
    requeue(tables: tables - completed_tables, dogstats_tags: ["error:replication_throttler"])
  ensure
    release_lock
  end

  def requeue(tables:, dogstats_tags:)
    self.class.perform_later(user_id, tables)
    GitHub.dogstats.increment("data.table_user_hidden_requeued", tags: dogstats_tags)

    self
  end

  def obtain_lock
    cache_lock_obtain(cache_lock_key, 5.minutes)
  end

  def release_lock
    cache_lock_release(cache_lock_key)
  end

  private

  def cache_lock_key
    "update_table_user_hidden_#{user_id}"
  end

  def user
    @user ||= User.find_by(id: user_id)
  end
end
