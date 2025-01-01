# typed: true
# frozen_string_literal: true

module Notifyd
  class MemberFeatureRequestSettings
    include GitHub::Memoizer

    # Routing Settings (RS) namespace
    RS = Notifyd::Proto::RoutingSettings

    attr_reader :user, :organization_id, :subscription

    sig { params(user: User, organization_id: Integer, subscription: MemberFeatureRequest::Notification::Setting).void }
    def initialize(user:, organization_id:, subscription:)
      @user = user
      @organization_id = organization_id
      @subscription = subscription
    end


    sig { returns(RS::RoutingSetting) }
    def to_routing_setting
      RS::RoutingSetting.new.tap do |routing|
        routing.name = "MemberFeatureRequest"

        routing.topics.push(
          RS::Topic.new(
            type: "organization",
            value: organization_id.to_s
          )
        )

        filters.each do |filter|
          routing.filters.push(filter)
        end

        routing.channels.push(
          RS::Channel.new(
            name: "ALL",
            enabled: subscription.user_enabled,
          )
        )

        custom_fields.each do |custom_field|
          routing.custom_fields.push(custom_field)
        end
      end
    end

    sig { returns(T::Boolean) }
    def save
      return Notifyd::RoutingSettingsService.new(user).delete(custom_fields) if subscription.all?

      Notifyd::RoutingSettingsService.new(user).save([to_routing_setting])
    end

    sig { returns(RS::GetResponse) }
    def get
      Notifyd::RoutingSettingsService.new(user).get(custom_fields)
    end

    sig { returns(T::Boolean) }
    def unsubscribe
      return true if disabled?

      if unsubscribe_features.empty?
        subscription.ignore!
      else
        subscription.custom!(features: unsubscribe_features)
      end

      save
    end

    private

    def filters
      if subscription.custom?
        opt_out_features.map do |feature|
          RS::Filter.new(
            subject_type: "MemberFeatureRequest::Notification",
            trigger: feature,
            reason: "any"
          )
        end
      else
        [
          RS::Filter.new(
            subject_type: "MemberFeatureRequest::Notification",
            trigger: "any",
            reason: "any"
          )
        ]
      end
    end

    def custom_fields
      [
        RS::CustomField.new(
          name: "delivery_group",
          value: "member_feature_request"
        ),
        RS::CustomField.new(
          name: "owner_id",
          value: user.id.to_s
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

    def opt_out_features
      MemberFeatureRequest::Feature.values.map(&:to_s) - subscription.features
    end

    def unsubscribe_features
      MemberFeatureRequest::Feature.values.map(&:to_s) - (current_filters + subscription.features).uniq
    end

    def current_filters
      return [] unless current_settings
      return [] unless current_settings.filters.any?

      current_settings.filters.map(&:trigger)
    end

    def current_channel
      current_settings.channels.first
    end

    def enabled?
      !current_settings
    end

    def custom?
      !enabled? && (current_filters - ["any"])&.any?
    end

    def disabled?
      !enabled? && !current_channel.enabled && !custom?
    end

    memoize def current_settings
      get.routing_setting.first
    end
  end
end
