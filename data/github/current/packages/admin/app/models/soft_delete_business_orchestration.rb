# typed: true
# frozen_string_literal: true

class SoftDeleteBusinessOrchestration < BusinessOrchestration
  step :update_deleted_status do
    with_write { found_business.touch(:deleted_at) }
  end

  job_start

  step :instrument do
    payload = {}
    payload[:actor] = actor if actor.present?
    found_business.instrument_deletion(payload)
  end

  step :suspend_first_emu_owner do
    return unless found_business.enterprise_managed_user_enabled?

    with_write { found_business.find_first_emu_owner&.suspend("Soft-deleted enterprise", actor: actor) }
  end

  step :send_email_notification do
    if data[:self_serve]
      BusinessMailer.business_deleted(actor, found_business.id).deliver_later
    end
  end

  step :enqueue_soft_delete_business_job do
    SoftDeleteBusinessJob.perform_later(found_business.id, self_serve: data[:self_serve], actor: actor)
  end

  private

  memoize def found_business
    Business.including_deleted.find_by(id: self.business_id)
  end
end
