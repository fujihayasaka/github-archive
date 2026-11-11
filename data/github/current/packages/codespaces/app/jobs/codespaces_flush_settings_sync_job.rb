# typed: strict
# frozen_string_literal: true

class CodespacesFlushSettingsSyncJob < CodespacesJob

  locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC

  retry_on Codespaces::Error, wait: :polynomially_longer, attempts: 15
  retry_on_dirty_exit
  retry_on_recoverable_exceptions


  sig { params(user: User).void }
  def perform(user:)
    Codespaces::FlushSettingsSync.call(user: user)
  end
end
