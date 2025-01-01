# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class MailchimpDataQualitySyncJob < ApplicationJob
  queue_as :mailchimp

  BATCH_SIZE = 1000

  MailchimpTryLaterError = Class.new(StandardError)
  retry_on MailchimpTryLaterError

  # Internal: The list of users who should be synced to MailChimp.
  #
  # By default this method returns users who have taken a specific action in the last
  # 10 days. If `sync_all_users` is true, it sends to MailChimp
  # all users who have not unsubscribed from marketing mail.
  #
  # Returns an Arel relation of Users
  def self.users_to_subscribe(sync_all_users: false)
    users = User
      .from("users FORCE INDEX(PRIMARY)")
      .accepts_marketing_mail
      .not_spammy
      .has_verified_email
      .preload(:developer_program_membership)
      .preload(:coupons)
      .preload(:emails)
      .preload(:primary_user_email)

    return users.preload(:interaction) if sync_all_users

    sync_window            = 10.days.ago
    recent_activity_clause = "last_active_at > :sync_window OR users.created_at > :sync_window"

    users.joins("LEFT JOIN interactions ON interactions.user_id = users.id")
      .where(recent_activity_clause, sync_window: sync_window)
  end

  # Public: Sync user information to MailChimp.
  #
  # Subscribe or update the merge fields for non-spammy users with a
  # verified email who accept marketing mail. By default, only subscribe or
  # update users active in the last 10 days. Unsubscribe users with a
  # transactional Newsletter Preference. Both subscribes and unsubscribes
  # use MailChimp's API for batched operations.
  #
  #   sync_all_users - flag to pass in the options; if set, all users are
  #                    subscribed or update regardless of recent activity.
  #
  # By default only users who have been active in the last week will be
  # synced; use the `sync_all_users` flag to override that behavior and sync
  # all non-spammy users with verified emails who accept marketing mail.
  def perform(options = {})
    @sync_all_users = options.with_indifferent_access[:sync_all_users] || false
    sync_subscribes
    sync_unsubscribes
  end

  # Internal: Sync and update list of Users who receive marketing mail
  #
  # Returns nil
  def sync_subscribes
    ActiveRecord::Base.connected_to(role: :reading_slow) do
      users = self.class.users_to_subscribe(sync_all_users: @sync_all_users)
      return nil unless users.present?

      users.find_in_batches(batch_size: BATCH_SIZE) do |user_batch|
        with_mailchimp_retries do
          batch = GitHub::Mailchimp.batch_subscribe(user_batch)
          raise "Status of MailChimp batch operations is unknown" unless request_succeeded?(batch["status"])
          MailchimpBatchStatusJob.perform_later(batch["id"])
        end
      end
    end
  end

  # Internal: Sync list of Users who have unsubscribed from marketing mail
  #
  # Returns nil
  def sync_unsubscribes
    ActiveRecord::Base.connected_to(role: :reading_slow) do
      emails = UserEmail.primary.where({
        user_id: NewsletterPreference.transactional.select(:user_id),
      })
      return unless emails.present?

      emails.find_in_batches(batch_size: BATCH_SIZE) do |email_batch|
        with_mailchimp_retries do
          GitHub::Mailchimp.list_ids.each do |list_id|
            batch = GitHub::Mailchimp.batch_unsubscribe(emails: email_batch, list_id: list_id)
            raise "Status of MailChimp batch operations is unknown" unless request_succeeded?(batch["status"])
            MailchimpBatchStatusJob.perform_later(batch["id"])
          end
        end
      end
    end
  end

  # Internal: Did our request to MailChimp error out before they enqueued our batch operation?
  #
  # Fun fact about MailChimp's API: if the request fails, `status`
  # will return a status code, and if it succeeds, it will be a string
  # indicating the state of the batch operation, either "pending",
  # "started", or "finished".
  #
  # Returns a Boolean indicating if our request to MailChimp went through.
  def request_succeeded?(status)
    acceptable_states = %w(pending started finished)
    acceptable_states.include?(status)
  end

  # Internal: When MailChimp API calls fail due to 5xx server errors,
  # retry the call up to 25 times. Otherwise, raise an exception
  # and fail the job.
  def with_mailchimp_retries(&block)
    yield
  rescue GitHub::Mailchimp::Error => boom
    if GitHub::Mailchimp::ServerErrorStatuses.include?(boom.status_code)
      GitHub.dogstats.increment "mailchimp", tags: ["job:quality_job_sync", "type:retry"]
      raise MailchimpTryLaterError
    else
      raise
    end
  end
end
