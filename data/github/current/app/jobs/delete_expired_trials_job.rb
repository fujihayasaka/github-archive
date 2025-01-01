# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class DeleteExpiredTrialsJob < BatchedJob
  queue_as :business_trial_expiration
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  schedule interval: 6.hours, condition: -> { !GitHub.single_business_environment? }

  sig { params(batch: T::Array[Business], args: T.untyped, options: T.untyped).void }
  def process_batch(batch, *args, **options)
    batch.each do |business|
      next unless business.eligible_for_expired_trial_deletion?

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

      instrument_expired_trial_deletion_processing(
        business,
        business.trial_deleted_at,
        action_taken)
    end
  end

  sig do
    params(
      args: T.untyped,
      timestamp: Time,
      offset_item_id: Integer,
      progress: Integer,
      options: T.untyped
    ).returns(T::Array[Business])
  end
  def next_batch(*args, timestamp: Time.now.utc, offset_item_id: 0, progress: 0, **options)
    Business.trial_expired.trial_deletable
    .where("id > ?", offset_item_id)
    .limit(BATCH_SIZE)
    .order(id: :asc).to_a
  end

  private

  def instrument_expired_trial_deletion_processing(business, trial_deleted_at, action_taken)
    return unless action_taken

    GlobalInstrumenter.instrument("enterprise_account.expired_trial_deletion", {
      enterprise_id: business.id,
      trial_deleted_at: trial_deleted_at.to_s,
      days_to_deletion: (trial_deleted_at.to_date - Time.zone.now.to_date).to_i,
      action_taken: action_taken,
    })
  end
end
