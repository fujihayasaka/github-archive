# typed: strict
# frozen_string_literal: true

module CopilotSweAgent
  module Public

    sig { returns(Dials::CopilotLogsPollingIntervalSeconds) }
    def self.copilot_logs_polling_interval_seconds
      Dials::CopilotLogsPollingIntervalSeconds.new(force_cache_miss: true)
    end

    sig { returns(Dials::CopilotSessionsPollingIntervalSeconds) }
    def self.copilot_sessions_polling_interval_seconds
      Dials::CopilotSessionsPollingIntervalSeconds.new(force_cache_miss: true)
    end
  end
end
