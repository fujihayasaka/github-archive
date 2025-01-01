# typed: true
# frozen_string_literal: true

class CodespacesCleanUpEnvironmentJob < CodespacesJob
  queue_as :codespaces
  locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  def perform(plan_id:, codespace_guid:, vscs_target:, location: nil)
    Codespaces::CleanUpEnvironment.call(
        plan_id: plan_id,
        codespace_guid: codespace_guid,
        vscs_target: vscs_target,
        location: location,
    )
  end
end
