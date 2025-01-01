# typed: true
# frozen_string_literal: true

class CodespacesCacheSkusJob < CodespacesJob
  locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC
  schedule interval: 1.hour, condition: -> { !GitHub.enterprise? }

  retry_on_dirty_exit

  def perform
    Codespaces::CacheSkus.call
  end
end
