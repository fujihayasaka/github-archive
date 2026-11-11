# typed: true
# frozen_string_literal: true

class Codespaces::CreateUsageRecordJob < CodespacesJob
  locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  def perform(payload)
    with_write do
      if usage_seconds = payload[:usage_seconds]
        payload[:usage_seconds] = usage_seconds.round
      end
      Codespaces::UsageRecord.create!(payload)
    end
  end
end
