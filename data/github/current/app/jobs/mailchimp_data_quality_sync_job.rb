# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class MailchimpDataQualitySyncJob < ApplicationJob
  queue_as :mailchimp

  BATCH_SIZE = 1000

  MailchimpTryLaterError = Class.new(StandardError)
  retry_on MailchimpTryLaterError

  def self.sync_window
    10.days.ago
  end

  def self.user_ids_to_subscribe
    min_user_id = User.where("users.created_at > :sync_window", sync_window: sync_window).minimum(:id)
    return [] if min_user_id.nil?

    NewsletterPreference
      .where("user_id >= :id", id: min_user_id)
      .where("elected_marketing_at IS NOT NULL")
      .where("elected_transactional_at IS NULL")
      .pluck(:user_id)
  end

  # Internal: The list of users who should be synced to MailChimp.
  #
  # By default this method returns users who have taken signed up in the last
  # 10 days.
  #
  # Returns an Arel relation of Users
  def self.users_to_subscribe(user_ids)
    users = User
      .from("users FORCE INDEX(PRIMARY)")
      .where(id: user_ids)
      .not_spammy
      .has_verified_email
      .preload(:developer_program_membership)
      .preload(:coupons)
      .preload(:emails)
      .preload(:primary_user_email)
      .where("users.created_at > :sync_window", sync_window: sync_window)
  end

  # Public: Sync user information to MailChimp.
  #
  # Subscribe or update the merge fields for non-spammy users with a
  # verified email who accept marketing mail. By default, only subscribe or
  # update users created in the last 10 days. Unsubscribe users with a
  # transactional Newsletter Preference. Both subscribes and unsubscribes
  # use MailChimp's API for batched operations.
  #
  # Only users who have been created in the last week will be
  # synced.
  def perform(options = {})
    sync_subscribes
    sync_unsubscribes
  end

  # Internal: Sync and update list of Users who receive marketing mail
  #
  # Returns nil
  def sync_subscribes
    ActiveRecord::Base.connected_to(role: :reading_slow) do
      users = self.class.user_ids_to_subscribe
      return nil unless users.any?

      users.in_groups_of(BATCH_SIZE, false).each do |user_id_batch|
        with_mailchimp_retries do
          user_batch = self.class.users_to_subscribe(user_id_batch)
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
      user_ids = NewsletterPreference.transactional.pluck(:user_id)
      return unless user_ids.present?

      UserEmail.batched_scope(:user_id, values: user_ids, batch_size: BATCH_SIZE) { |s| s.primary }.to_a.in_groups_of(BATCH_SIZE, false) do |email_batch|
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
