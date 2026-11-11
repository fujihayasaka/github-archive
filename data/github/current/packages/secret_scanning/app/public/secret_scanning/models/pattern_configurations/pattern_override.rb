# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Models::PatternConfigurations
    class PatternOverride < T::Struct
      const :token_type, String
      const :custom_pattern_version, T.nilable(String)
      const :slug, String
      const :display_name, String
      const :alert_total, Integer
      const :false_positives, Integer
      const :blocks, Integer
      const :bypasses, Integer
      const :default_setting, ::SecretScanning::Models::Settings::BoolSetting
      const :inherited_setting, ::SecretScanning::Models::Settings::BoolSetting
      const :setting, ::SecretScanning::Models::Settings::BoolSetting

      sig { params(proto: GitHub::Proto::SecretScanning::Api::V1::PatternOverride).returns(PatternOverride) }
      def self.from_proto(proto)
        out = PatternOverride.new(
          token_type: proto.token_type,
          custom_pattern_version: proto.row_version.presence,
          slug: proto.slug,
          display_name: proto.display_name,
          alert_total: proto.alert_total,
          false_positives: proto.false_positives,
          blocks: proto.blocks,
          bypasses: proto.bypasses,
          default_setting: Models::Settings::BoolSetting.from_proto(proto.push_protection&.default_setting || 0),
          inherited_setting: Models::Settings::BoolSetting.from_proto(proto.push_protection&.parent_setting || 0),
          setting: Models::Settings::BoolSetting.from_proto(proto.push_protection&.setting || 0),
        )
        out
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def serialize_ui
        {
          id: token_type, # Need id for DataTable
          token_type:,
          row_version: custom_pattern_version,
          slug:,
          display_name:,
          alert_total:,
          false_positives:,
          blocks:,
          bypasses:,
          default_setting: default_setting.serialize,
          inherited_setting: inherited_setting.serialize,
          setting: setting.serialize,
        }
      end

      sig do params(
        has_parent: T::Boolean,
        total_alerts: Integer,
        is_custom_pattern: T::Boolean,
      ).returns(T::Hash[Symbol, T.untyped])
      end
      def serialize_api(has_parent:, total_alerts:, is_custom_pattern: false)
        out = {
          token_type:,
          slug:,
          display_name:,
          alert_total:,
          alert_total_percentage: Util::Math.to_percent_int(alert_total, total_alerts, floor: true),
          false_positives:,
          false_positive_rate: Util::Math.to_percent_int(false_positives, alert_total, floor: true),
          bypass_rate: Util::Math.to_percent_int(bypasses, blocks, floor: true),
          default_setting: default_setting.serialize,
          setting: setting.serialize,
        }
        out[:custom_pattern_version] = custom_pattern_version if is_custom_pattern
        out[:enterprise_setting] = inherited_setting.serialize if has_parent && !is_custom_pattern
        out
      end
    end
  end
end
