# typed: true
# frozen_string_literal: true

module SecretScanning
  module CustomPatterns
    class AlertMetricsComponent < ApplicationComponent
      extend T::Sig

      attr_reader :pattern_published, :open_alerts_path, :closed_alerts_path, :false_positive_alerts_path

      sig do
        params(metrics: T.nilable(SecretScanning::Models::TokenAlertMetrics),
               pattern_published: T::Boolean,
               open_alerts_path: String,
               closed_alerts_path: String,
               false_positive_alerts_path: String).void
      end
      def initialize(metrics:, pattern_published:, open_alerts_path:, closed_alerts_path:, false_positive_alerts_path:)
        @metrics = metrics
        @pattern_published = pattern_published
        @open_alerts_path = open_alerts_path
        @closed_alerts_path = closed_alerts_path
        @false_positive_alerts_path = false_positive_alerts_path
      end

      sig { returns(String) }
      def open_alert_count
        return "--" if @metrics.nil?
        @metrics.open_alert_count.to_s
      end

      sig { returns(String) }
      def closed_alert_count
        return "--" if @metrics.nil?
        @metrics.closed_alert_count.to_s
      end

      sig { returns(String) }
      def false_positive_count
        return "--" if @metrics.nil?
        @metrics.false_positive_count.to_s
      end
    end
  end
end
