# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module SecretScanning
  module Models
    class TokenPushProtectionMetrics
      extend T::Sig

      attr_reader :total_block_count, :successful_block_count, :bypassed_alert_count

      sig do
        params(total_block_count: Integer,
               successful_block_count: Integer,
               bypassed_alert_count: Integer).void
      end
      def initialize(total_block_count: 0, successful_block_count: 0, bypassed_alert_count: 0)
        @total_block_count = total_block_count
        @successful_block_count = successful_block_count
        @bypassed_alert_count = bypassed_alert_count
      end
    end
  end
end
