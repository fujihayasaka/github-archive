# typed: true
# frozen_string_literal: true

class HydroScheduledRemindersOnPushJob < Repositories::PushHydroMessageJob
  queue_as :hydro_scheduled_reminders_on_push

  sig { void }
  def perform
    ref_updates.each do |ref_update|
      next if ref_update.deleted? || ref_update.created?
      next unless ref_update.recordable?

      Reminders::TriggerMergeableUpdateJob.perform_later_with_delay(
        push_id: nil,
        repo_id: repository.id,
        ref: ref_update.ref,
        event_at: pushed_at,
        transaction_id: nil,
      )
    end
  end
end
