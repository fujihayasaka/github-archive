# typed: strict
# frozen_string_literal: true

class Copilot::BatchUpdateStandaloneUserSettingsJob < CopilotJob
  queue_as :copilot_update_standalone_settings
  retry_on_dirty_exit
  retry_on_recoverable_exceptions


  # this job enqueues member updates in batches of BATCH_SIZE to parallelize writes
  BATCH_SIZE = 1_000

  sig { params(business: Business).void }
  def perform(business)
    return unless Copilot::Business.new(business).copilot_standalone?
    Copilot::Seat.includes(:seat_assignment).where(copilot_seat_assignments: { owner_type: "Business", owner_id: business.id })
      .find_in_batches(batch_size: BATCH_SIZE) do |batch|
        start = T.let(T.must(batch[0]), Copilot::Seat).id || 0
        finish = T.let(T.must(batch[-1]), Copilot::Seat).id || 0
        Copilot::UpdateStandaloneUserSettingsCacheJob.perform_later(T.must(business.id), start, finish)
      end
  end
end
