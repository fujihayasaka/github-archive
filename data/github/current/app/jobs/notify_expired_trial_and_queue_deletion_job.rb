# typed: true
# frozen_string_literal: true

class NotifyExpiredTrialAndQueueDeletionJob < ApplicationJob
  queue_as :business_trial_expiration
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  schedule interval: 1.day, condition: -> { !GitHub.single_business_environment? }

  SLICE_SIZE = 1000

  def perform
    candidate_businesses.to_a.in_groups_of(SLICE_SIZE, false) do |slice|
      slice.each do |business|
        next unless business.eligible_for_expired_trial_deletion?
        trial_deleted_at = business.trial_deleted_at
        next unless trial_deleted_at.present?
        action_taken = nil

        if send_email_notification?(trial_deleted_at, business)
          business.owners.each do |owner|
            BusinessMailer.notify_expired_trial_admins(business, owner, trial_deleted_at).deliver_later
          end
          with_write { business.expired_trial_business_deletion_email_sent! }
          action_taken = :EMAIL
        elsif trial_deleted_at.to_date <= Time.zone.now.to_date
          begin
            ActiveRecord::Base.connected_to(role: :writing) do
              business.soft_delete!
            end
            GitHub.dogstats.increment("expired_trials_soft_delete.count")
            business.owners.each do |owner|
              BusinessMailer.notify_expired_enterprise_trial_deleted(business, owner).deliver_later
            end
            action_taken = :DELETE
          rescue Business::SoftDeletionUnsupportedError => error
            GitHub.logger.error("Business #{business.id} does not support soft deletion: #{error.message}")
            action_taken = :ERROR
          end
        end

        instrument_expired_trial_deletion_processing(
          business,
          trial_deleted_at,
          action_taken)
      end
    end
  end

  private

  def candidate_businesses
    Business.trial_expired.where("trial_expires_at < ?", Business::EXPIRED_TRIAL_DELETION_CUTOFF_DATE)
  end

  def send_email_notification?(trial_deleted_at, business)
    [60, 30, 7, 1].each do |num_days_to_deletion|
      if (Time.zone.now.to_date + num_days_to_deletion.days) == trial_deleted_at && \
        !business.expired_trial_business_deletion_email_sent?
        return true
      end
    end
    false
  end

  def instrument_expired_trial_deletion_processing(business, trial_deleted_at, action_taken)
    return unless action_taken
    days_to_deletion = (trial_deleted_at.to_date - Time.zone.now.to_date).to_i

    GlobalInstrumenter.instrument("enterprise_account.expired_trial_deletion", {
      enterprise_id: business.id,
      trial_deleted_at: trial_deleted_at.to_s,
      days_to_deletion: days_to_deletion,
      action_taken: action_taken,
    })
  end
end
