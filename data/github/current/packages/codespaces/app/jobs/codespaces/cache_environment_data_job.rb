# typed: true
# frozen_string_literal: true

class Codespaces::CacheEnvironmentDataJob < CodespacesJob
  locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC

  retry_on_dirty_exit

  def perform(environment_data)
    Codespace.throttle_with_retry { Codespaces::CacheEnvironmentData.call(environment_data) }
  end
end
