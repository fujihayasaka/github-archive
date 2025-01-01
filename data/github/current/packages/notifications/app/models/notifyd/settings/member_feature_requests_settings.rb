# typed: strict
# frozen_string_literal: true

module Notifyd
  module Settings
    class MemberFeatureRequestsSettings
      RS = Notifyd::Proto::RoutingSettingsV2

      sig do
        params(
          settings: Notifications::Settings::MemberFeatureRequestsSettings,
          user_id: Integer,
          organization_id: Integer,
        ).returns(RS::Setting)
      end
      def self.to_routing_setting(settings, user_id:, organization_id:)
        # Member feature requests subscription and settings behaviour diverge
        # from the standard subscriptions and settings behaviour.
        # Member feature requests supports several features that the users may
        # be interested in, but instead of mapping these interests to feature
        # subscriptions, they are mapped to settings: users are subscribed
        # to all the settings by default and the simply mute features partially
        # or completely.
        # Additionally, contrary to the standard settings behaviour which relies
        # on the implicit, default value of a setting only when the user
        # hasn't explicitly changed the setting (even if it's been reverted to
        # its default value), the way member feature request settings work
        # is that only mute settings are stored: when the user unmutes them
        # (going back to the default of being subscribed to them all) then the
        # setting (the mute) is deleted.
        # This works because there are no actual settings in which the users
        # could define the channels they are interested in, it's not possible
        # to add such support with the current behaviour in a simple way.
        # Ideally, this should be addressed and by moving the selection of
        # features to the subscription system and leaving the settings system
        # in charge only of the channel selection and (possibly) muting support.

        # We need to consider the features to disable, but settings have the
        # enabled features. This method should not be called when all the
        # features are enabled.
        features = MemberFeatureRequest::Feature.values - settings.features
        return RS::Setting.new if features.empty?

        filters = []
        if features.length == MemberFeatureRequest::Feature.values.length
          filters << RS::Filter.new(
            subject_type: "MemberFeatureRequest::Notification",
            trigger: "any",
            reason: "any",
          )
        else
          features.each do |feature|
            filters << RS::Filter.new(
              subject_type: "MemberFeatureRequest::Notification",
              trigger: feature.to_s,
              reason: "any",
            )
          end
        end

        RS::Setting.new(
          name: "member_feature_requests_settings",
          topics: [RS::Topic.new(type: "organization", value: organization_id.to_s)],
          channels: [RS::Channel.new(name: "ALL", enabled: false)],
          filters: filters,
          custom_fields: custom_fields(user_id:, organization_id:)
        )
      end

      sig { params(user_id: Integer, organization_id: Integer).returns(T::Array[RS::CustomField]) }
      def self.custom_fields(user_id:, organization_id:)
        [
          RS::CustomField.new(
            name: "delivery_group",
            value: "member_feature_request"
          ),
          RS::CustomField.new(
            name: "owner_id",
            value: user_id.to_s
          ),
          RS::CustomField.new(
            name: "organization_id",
            value: organization_id.to_s
          ),
          RS::CustomField.new(
            name: "owner_type",
            value: "organization"
          )
        ]
      end

      sig { params(user_id: Integer, organization_id: Integer).returns(RS::CustomFieldGroup) }
      def self.custom_field_group(user_id:, organization_id:)
        RS::CustomFieldGroup.new(fields: custom_fields(user_id:, organization_id:))
      end
    end
  end
end
