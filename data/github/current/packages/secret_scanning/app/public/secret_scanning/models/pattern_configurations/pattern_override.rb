# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Models::PatternConfigurations
    class PatternOverride < T::Struct
      const :token_type, String
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
        PatternOverride.new(
          token_type: proto.token_type,
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
      end

      sig { override.params(args: T.untyped).returns(T::Hash[String, T.untyped]) }
      def serialize(*args)
        payload = super(args)
        payload["id"] = payload["token_type"] # Need id for DataTable
        payload
      end
    end
  end
end
