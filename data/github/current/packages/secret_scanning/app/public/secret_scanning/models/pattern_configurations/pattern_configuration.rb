# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Models::PatternConfigurations
    class PatternConfiguration < T::Struct
      const :number, Integer
      const :pattern_config_version, T.nilable(String)
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
          pattern_config_version: proto.row_version,
          total_alerts: proto.alert_total,
          provider_pattern_overrides: proto.provider_pattern_overrides.to_a.map do |pattern_override|
            PatternOverride.from_proto(pattern_override)
          end,
          custom_pattern_overrides: proto.custom_pattern_overrides.to_a.map do |pattern_override|
            PatternOverride.from_proto(pattern_override)
          end
        )
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def serialize_ui
        {
          # TODO: Check if we actually need number in the UI anymore
          number:,
          row_version: pattern_config_version,
          total_alerts:,
          provider_pattern_overrides: provider_pattern_overrides.map { |it| it.serialize_ui },
          custom_pattern_overrides: custom_pattern_overrides.map { |it| it.serialize_ui },
        }
      end

      sig { params(has_parent: T::Boolean).returns(T::Hash[Symbol, T.untyped]) }
      def serialize_api(has_parent:)
        {
          pattern_config_version:,
          provider_pattern_overrides: provider_pattern_overrides.map { |it| it.serialize_api(has_parent:, total_alerts:) },
          custom_pattern_overrides: custom_pattern_overrides.map { |it| it.serialize_api(has_parent:, total_alerts:, is_custom_pattern: true) },
        }
      end
    end
  end
end
