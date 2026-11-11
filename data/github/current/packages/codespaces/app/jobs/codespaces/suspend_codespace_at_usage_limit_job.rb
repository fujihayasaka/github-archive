# typed: true
# frozen_string_literal: true

module Codespaces
  class SuspendCodespaceAtUsageLimitJob < CodespacesJob
    locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC
    retry_on_dirty_exit

    def perform(codespace:)
      SuspendCodespaceAtUsageLimit.call(codespace: codespace)
    end
  end
end
