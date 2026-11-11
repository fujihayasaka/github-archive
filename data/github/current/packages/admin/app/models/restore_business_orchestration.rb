# typed: true
# frozen_string_literal: true

class RestoreBusinessOrchestration < BusinessOrchestration
  step :update_deleted_status do
    return :skipped unless deleted_business&.deleted?

    data[:business_deleted_at] = deleted_business.deleted_at.to_s
    deleted_business.update! deleted_at: nil
  end

  job_start

  step :unsuspend_first_emu_owner do
    if deleted_business.enterprise_managed_user_enabled?
      deleted_business.find_first_emu_owner.unsuspend(
        "Soft-deleted enterprise restored",
        actor: actor
      )
    end
  end

  step :restore_soft_deleted_repositories do
    if deleted_business.soft_deleted_organizations.any?
      business_deleted_at = Time.zone.parse(data[:business_deleted_at])
      RestoreSoftDeletedBusinessOrganizationsJob.perform_now(deleted_business, business_deleted_at.to_i)
    end
  end

  step :update_trial_status do
    if deleted_business.eligible_for_expired_trial_deletion?
      deleted_business.update! trial_deleted_at: 8.days.from_now
    end
  end

  step :instrument do
    payload = {}
    payload[:actor] = actor if actor.present?
    deleted_business.instrument_restoration(payload)
  end

  step :resume_billing do
    deleted_business.resume_billing
  end

  private

  memoize def deleted_business
    Business.including_deleted.find_by(id: self.business_id)
  end
end
