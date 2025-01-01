# typed: strict
# frozen_string_literal: true

module CopilotSweAgent
  module Dials
    class CopilotLogsPollingIntervalSeconds < Codespaces::Dial
      validates :value, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 600 }

      sig { override.returns(String) }
      def key
        "copilot_agent_logs_polling_interval_seconds"
      end

      sig { override.returns(Integer) }
      def default_value
        1
      end

      sig { override.returns(String) }
      def description
        "This value restricts the amount of time (in seconds) between polling intervals for fetching the logs for a given Copilot agent session from CAPI."
      end

      private

      sig { override.params(value: String).returns(Integer) }
      def transform_value_to_use(value)
        value.to_i
      end
    end
  end
end
