# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Models::PatternConfigurations
    class PatternConfiguration < T::Struct
      const :number, Integer
      const :row_version, T.nilable(String)
      const :total_alerts, Integer
      const :provider_pattern_overrides, T::Array[PatternOverride]
      const :custom_pattern_overrides, T::Array[PatternOverride]

      sig do
        params(
          proto: GitHub::Proto::SecretScanning::Api::V1::PatternConfiguration
        ).returns(PatternConfiguration)
      end
      def self.from_proto(proto)
        PatternConfiguration.new(
          number: proto.number,
          row_version: proto.row_version,
          total_alerts: proto.alert_total,
          provider_pattern_overrides: proto.provider_pattern_overrides.to_a.map do |pattern_override|
            PatternOverride.from_proto(pattern_override)
          end,
          custom_pattern_overrides: proto.custom_pattern_overrides.to_a.map do |pattern_override|
            PatternOverride.from_proto(pattern_override)
          end
        )
      end
    end
  end
end
