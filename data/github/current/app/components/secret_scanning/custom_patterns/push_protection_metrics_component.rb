# typed: true
# frozen_string_literal: true

module SecretScanning
  module CustomPatterns
    class PushProtectionMetricsComponent < ApplicationComponent
      extend T::Sig

      attr_reader :push_protection_enabled

      # date at which we started collecting push protection metrics on Cloud
      METRICS_COLLECTION_START_DATE = Time.new(2023, 02, 12)

      sig do
        params(metrics: T.nilable(SecretScanning::Models::TokenPushProtectionMetrics),
               push_protection_enabled: T::Boolean,
               custom_pattern_created_at: Time).void
      end
      def initialize(metrics:, push_protection_enabled:, custom_pattern_created_at:)
        @metrics = metrics
        @push_protection_enabled = push_protection_enabled
        @custom_pattern_created_at = custom_pattern_created_at
      end

      sig { returns(String) }
      def total_block_count
        return "--" if @metrics.nil?
        @metrics.total_block_count.to_s
      end

      sig { returns(String) }
      def successful_block_count
        return "--" if @metrics.nil?
        @metrics.successful_block_count.to_s
      end

      sig { returns(String) }
      def bypassed_alert_count
        return "--" if @metrics.nil?
        @metrics.bypassed_alert_count.to_s
      end

      sig { returns(T::Boolean) }
      def show_old_pattern_disclaimer?
        @custom_pattern_created_at < METRICS_COLLECTION_START_DATE
      end
    end
  end
end
