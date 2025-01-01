# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class NotifyExpiredTrialsJob < BatchedJob
  queue_as :business_trial_expiration
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  schedule interval: 6.hours, condition: -> { !GitHub.single_business_environment? }

  NOTIFICATION_DAYS = [60, 30, 7, 1]

  sig { params(batch: T::Array[Business], args: T.untyped, options: T.untyped).void }
  def process_batch(batch, *args, **options)
    batch.each do |business|
      next if business.expired_trial_business_deletion_email_sent?
      next unless business.eligible_for_expired_trial_deletion?
      trial_deleted_at = business.trial_deleted_at
      next unless trial_deleted_at.present?

      if GitHub.multi_tenant_enterprise?
        GitHub::CurrentTenant.set(business) do
          send_notification_emails(business, trial_deleted_at)
        end
      else
        send_notification_emails(business, trial_deleted_at)
      end

      with_write { business.expired_trial_business_deletion_email_sent! }

      GlobalInstrumenter.instrument("enterprise_account.expired_trial_deletion", {
        enterprise_id: business.id,
        trial_deleted_at: trial_deleted_at.to_s,
        days_to_deletion: (trial_deleted_at.to_date - Time.zone.now.to_date).to_i,
        action_taken: :EMAIL,
      })
    end
  end

  private

  # Send notification emails to all business owners and organization admins
  # about the upcoming trial expiration and account deletion
  sig { params(business: Business, trial_deleted_at: ActiveSupport::TimeWithZone).void }
  def send_notification_emails(business, trial_deleted_at)
    business.owners.each do |owner|
      BusinessMailer.notify_expired_trial_admins(business, owner, trial_deleted_at).deliver_later
    end

    business.organizations.each do |org|
      org.admins.each do |admin|
        BusinessMailer.notify_expired_org_admins(org, admin, trial_deleted_at).deliver_later
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
    Business.trial_expired
    .where(trial_deleted_at: [notification_date_range])
    .where("id > ?", offset_item_id)
    .limit(BATCH_SIZE)
    .order(id: :asc).to_a
  end


  sig { returns(T::Array[T.nilable(T::Range[T.untyped])]) }
  def notification_date_range
    NOTIFICATION_DAYS.map do |days|
      days.days&.from_now.all_day
    end
  end
end
