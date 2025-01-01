# typed: true
# frozen_string_literal: true

class Codespaces::BulkRestoreCodespacesJob < CodespacesJob
  locked_by timeout: 3.hours, key: DEFAULT_LOCK_PROC
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  def perform(user_id:, deletion_reasons: nil)
    Codespaces::BulkRestoreCodespaces.call(user_id: user_id, deletion_reasons: deletion_reasons)
  end
end
