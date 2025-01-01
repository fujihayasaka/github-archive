# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Models
    class BypassReasonCountMetric
      extend T::Sig

      sig { returns(Integer) }
      attr_reader :count

      sig { returns(Integer) }
      attr_accessor :percent

      sig { returns(T.any(Symbol, Integer)) }
      attr_reader :bypass_reason

      sig do
        params(count: Integer,
               percent: Integer,
               bypass_reason: T.any(Symbol, Integer)).void
      end
      def initialize(count: 0, percent: 0, bypass_reason: 0)
        @count = count
        @percent = percent
        @bypass_reason = bypass_reason
      end

      sig do
        params(proto: GitHub::Proto::SecretScanning::Metrics::V1::BypassReasonCount).returns(BypassReasonCountMetric)
      end
      def self.from_proto(proto)

        BypassReasonCountMetric.new(
          count: proto.count,
          bypass_reason: proto.bypass_reason,
        )
      end
    end
  end
end
