# typed: true
# frozen_string_literal: true

class Codespaces::DeleteDependentCodespacesJob < CodespacesJob
  locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  def perform(owner_id:, reason: Codespace.deletion_reasons[:bulk_dependent_deletion])
    Codespaces::DeleteDependentCodespaces.call(owner_id: owner_id, reason: reason)
  end
end
