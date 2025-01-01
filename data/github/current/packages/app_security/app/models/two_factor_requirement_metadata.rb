# typed: true
# frozen_string_literal: true

class TwoFactorRequirementMetadata < ApplicationRecord::Domain::Users
  belongs_to :user

  validates_presence_of :user_id, :requirement_reason

  # Returns users who have not yet been sent a final notification that 2FA is now required for their account.
  scope :final_notification_not_sent,
    -> {
      from("two_factor_requirement_metadata USE INDEX (index_two_factor_requirement_metadata_on_user_id_and_state)")
        .where(state: User::AccountTwoFactorRequirementDependency::TWO_FACTOR_REQUIREMENT_STATES[:required])
        .where("last_email_notified_at IS NULL OR last_email_notified_at < required_by")
    }

  # Returns users who have not yet been notified that 2FA will be required for their account.
  scope :not_yet_notified,
    -> {
      from("two_factor_requirement_metadata USE INDEX (index_two_factor_requirement_metadata_on_user_id_and_state)")
        .where(state: User::AccountTwoFactorRequirementDependency::TWO_FACTOR_REQUIREMENT_STATES[:warning])
        .where(last_email_notified_at: nil)
    }

  # Returns users who have not yet been sent the first (31 days remaining / 4 weeks and 3 days) warning that 2FA will be required for their account.
  # Note that this scope does not handle DST changes, so we have a known bug of alerting users 1 hour earlier than expected when within 31 days of a DST change.
  scope :first_warning_not_sent,
    -> (now: Time.now.utc) {
      # required by is between 3 weeks and 31 days from now
      from("two_factor_requirement_metadata USE INDEX (index_two_factor_requirement_metadata_on_user_id_and_state)")
        .where(state: User::AccountTwoFactorRequirementDependency::TWO_FACTOR_REQUIREMENT_STATES[:warning])
        .where("(required_by > ? AND required_by <= ? AND (last_email_notified_at IS NULL OR last_email_notified_at < DATE_SUB(required_by, INTERVAL 31 DAY)))", now + 3.weeks, now + 31.days)
    }

  # Returns users who have not yet been sent the 2nd (3 weeks remaining) warning that 2FA will be required for their account.
  # Note that this scope does not handle DST changes, so we have a known bug of alerting users 1 hour earlier than expected when within 3 weeks of a DST change.
  scope :second_warning_not_sent,
    -> (now: Time.now.utc) {
      # required by is between 1 week and 3 weeks from now
      from("two_factor_requirement_metadata USE INDEX (index_two_factor_requirement_metadata_on_user_id_and_state)")
        .where(state: User::AccountTwoFactorRequirementDependency::TWO_FACTOR_REQUIREMENT_STATES[:warning])
        .where("(required_by > ? AND required_by <= ? AND (last_email_notified_at IS NULL OR last_email_notified_at < DATE_SUB(required_by, INTERVAL 3 WEEK)))", now + 1.week, now + 3.weeks)
    }

  # Returns users who have not yet been sent the 3rd (1 week remaining) warning that 2FA will be required for their account.
  # Note that this scope does not handle DST changes, so we have a known bug of alerting users 1 hour earlier than expected when within 1 week of a DST change.
  scope :third_warning_not_sent,
    -> (now: Time.now.utc) {
      # required by is between 1 day and 1 week from now
      from("two_factor_requirement_metadata USE INDEX (index_two_factor_requirement_metadata_on_user_id_and_state)")
        .where(state: User::AccountTwoFactorRequirementDependency::TWO_FACTOR_REQUIREMENT_STATES[:warning])
        .where("(required_by > ? AND required_by <= ? AND (last_email_notified_at IS NULL OR last_email_notified_at < DATE_SUB(required_by, INTERVAL 1 WEEK)))", now + 1.day, now + 1.week)
    }

  # Returns users who have not yet been sent the last (1 day remaining) warning that 2FA will be required for their account.
  # Note that this scope does not handle DST changes, so we have a known bug of alerting users 1 hour earlier than expected when within 1 day of a DST change.
  scope :final_warning_not_sent,
    -> (now: Time.now.utc) {
      # required by is between now and 1 day from now
      from("two_factor_requirement_metadata USE INDEX (index_two_factor_requirement_metadata_on_user_id_and_state)")
        .where(state: User::AccountTwoFactorRequirementDependency::TWO_FACTOR_REQUIREMENT_STATES[:warning])
        .where("(required_by > ? AND required_by <= ? AND (last_email_notified_at IS NULL OR last_email_notified_at < DATE_SUB(required_by, INTERVAL 1 DAY)))", now, now + 1.day)
    }

  # Returns users whose 2FA requirement deadline has passed, and interrupt grace period has elapsed.
  scope :interrupt_seen_and_grace_elapsed,
    -> (now: Time.now.utc, state: nil) {
      where(state: state).where("interrupt_first_seen_at <= ?", now - User::AccountTwoFactorRequirementDependency::INTERRUPT_BYPASS_GRACE_PERIOD)
        .required_by_elapsed(now: now, state: state)
    }

  # Returns users whose 2FA requirement deadline has passed.
  scope :required_by_elapsed,
    -> (now: Time.now.utc, state: nil) {
      where(state: state)
        .where("required_by <= ?", now)
    }

  # Finds users whose 2FA requirement state should be updated.
  def self.find_for_progression(batch_size: 1000, now: Time.now.utc, &block)
    return unless block_given?

    # interrupt -> required
    self.interrupt_seen_and_grace_elapsed(now: now, state: User::AccountTwoFactorRequirementDependency::TWO_FACTOR_REQUIREMENT_STATES[:interrupt]).in_batches(of: batch_size) do |batch|
      block.call(batch.pluck(:user_id), User::AccountTwoFactorRequirementDependency::TWO_FACTOR_REQUIREMENT_STATES[:required])
    end

    # warning -> interrupt
    self.required_by_elapsed(now: now, state: User::AccountTwoFactorRequirementDependency::TWO_FACTOR_REQUIREMENT_STATES[:warning]).in_batches(of: batch_size) do |batch|
      block.call(batch.pluck(:user_id), User::AccountTwoFactorRequirementDependency::TWO_FACTOR_REQUIREMENT_STATES[:interrupt])
    end
  end
end
