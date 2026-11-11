# typed: true
# frozen_string_literal: true

class CodespacesProcessSystemEventJob < CodespacesJob
  locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC
  retry_on_dirty_exit

  def perform(codespaces:, transfer_billable_owner: true, deletion_reason: Codespace.deletion_reasons[:process_system_event])
    Codespaces::ProcessSystemEvent.call(codespaces, transfer_billable_owner: transfer_billable_owner, deletion_reason: deletion_reason)
  end
end
