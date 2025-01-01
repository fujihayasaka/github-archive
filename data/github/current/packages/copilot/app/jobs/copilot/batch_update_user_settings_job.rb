# typed: strict
# frozen_string_literal: true

class Copilot::BatchUpdateUserSettingsJob < CopilotJob
  queue_as :copilot_update_org_settings
  retry_on_dirty_exit
  retry_on_recoverable_exceptions


  BATCH_SIZE = 1_000
  # this job enqueues member updates in batches of BATCH_SIZE to parallelize writes
  sig { params(org_id: Integer).void }
  def perform(org_id)
    Copilot::Seat.where(organization_id: org_id)
    .find_in_batches(batch_size: BATCH_SIZE) do |batch|
      start = T.let(T.must(batch[0]), Copilot::Seat).id || 0
      finish = T.let(T.must(batch[-1]), Copilot::Seat).id || 0
      Copilot::UpdateUserSettingsCacheJob.perform_later(org_id, start, finish)
    end
  end
end
