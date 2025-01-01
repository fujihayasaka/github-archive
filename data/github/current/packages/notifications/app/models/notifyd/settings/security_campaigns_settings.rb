# typed: strict
# frozen_string_literal: true

module Notifyd
  module Settings
    class SecurityCampaignsSettings
      RS = Notifyd::Proto::RoutingSettingsV2

      sig { params(settings: Notifications::Settings::SecurityCampaignsSettings).returns(RS::Setting) }
      def self.to_routing_setting(settings)
        RS::Setting.new(
          name: "security_campaigns_settings",
          topics: [RS::Topic.new(type: "any", value: "any")],
          channels: [RS::Channel.new(name: "EMAIL", enabled: settings.email)],
          filters: [
            RS::Filter.new(
              subject_type: "SecurityCampaigns::SecurityCampaignUser",
              trigger: "any",
              reason: "any",
            ),
          ],
          custom_fields: custom_fields,
        )
      end

      sig { returns(T::Array[RS::CustomField]) }
      def self.custom_fields
        [
          RS::CustomField.new(
            name: "category",
            value: "security_campaigns"
          )
        ]
      end

      sig { returns(RS::CustomFieldGroup) }
      def self.custom_field_group
        RS::CustomFieldGroup.new(fields: custom_fields)
      end
    end
  end
end
