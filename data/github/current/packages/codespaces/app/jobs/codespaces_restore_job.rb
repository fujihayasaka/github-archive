# typed: true
# frozen_string_literal: true

class CodespacesRestoreJob < CodespacesJob
  locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC

  retry_on Codespaces::Error, wait: :polynomially_longer, attempts: 15
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  def perform(codespace:)
    Codespaces::Restore.call(codespace)
  end
end
