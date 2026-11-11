# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class DeleteEmailUnverifiedTrialsJob < BatchedJob
  queue_as :business_trial_email_unverified_deletion
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  schedule interval: 6.hours, condition: -> { !GitHub.single_business_environment? }

  sig { params(batch: T::Array[Business], args: T.untyped, options: T.untyped).void }
  def process_batch(batch, *args, **options)
    batch.each do |business|
      next unless business.eligible_for_email_unverified_trial_deletion?

      # Skip businesses that have organizations as a safety measure.
      # Businesses shouldn't be able to have orgs without verifying email,
      # so if they have any, something unexpected happened and we should not delete.
      if business.organizations.any?
        GitHub.logger.info("Skipping deletion of business #{business.id} because it has organizations")
        GitHub.dogstats.increment("email_unverified_trials_delete.skipped_has_orgs")
        next
      end

      # Dry run mode: only log what would be deleted unless feature flag is enabled
      if FeatureFlag.vexi.enabled?(:delete_email_unverified_trials_job_enabled, default: false)
        begin
          ActiveRecord::Base.connected_to(role: :writing) do
            business.soft_delete!
          end
          GitHub.dogstats.increment("email_unverified_trials_delete.count")
          GitHub.logger.info("Soft-deleted email-unverified trial business #{business.id}")
        rescue Business::SoftDeletionUnsupportedError => error
          GitHub.logger.error("Business #{business.id} does not support soft deletion: #{error.message}")
        end
      else
        GitHub.dogstats.increment("email_unverified_trials_delete.dry_run")
        GitHub.logger.info("DRY RUN: Would delete email-unverified trial business #{business.id}")
      end
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
    Business.trial_email_unverified
    .where("id > ?", offset_item_id)
    .limit(BATCH_SIZE)
    .order(id: :asc).to_a
  end
end
