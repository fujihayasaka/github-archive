# typed: true
# frozen_string_literal: true

class CodespacesCacheSkusJob < CodespacesJob
  locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC
  schedule interval: 1.hour, condition: -> { !GitHub.enterprise? }

  retry_on_dirty_exit

  # This job operates at the stamp level, not the tenant level
  exempt_from_tenant_context_requirement

  def perform
    Codespaces::CacheSkus.call
  end
end
