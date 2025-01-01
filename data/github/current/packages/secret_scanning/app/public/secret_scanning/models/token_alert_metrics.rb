# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module SecretScanning
  module Models
    class TokenAlertMetrics
      attr_reader :open_alert_count, :closed_alert_count, :false_positive_count

      sig do
        params(open_alert_count: Integer,
               closed_alert_count: Integer,
               false_positive_count: Integer).void
      end
      def initialize(open_alert_count: 0, closed_alert_count: 0, false_positive_count: 0)
        @open_alert_count = open_alert_count
        @closed_alert_count = closed_alert_count
        @false_positive_count = false_positive_count
      end
    end
  end
end
