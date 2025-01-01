# typed: true
# frozen_string_literal: true

module Notifyd
  class ParticipatingActivitySettings
    extend T::Sig
    # Routing Settings (RS) namespace
    RS = Notifyd::Proto::RoutingSettings

    CHANNEL_EMAIL = "EMAIL".freeze

    # Settings are initialized with an array of enabled channels. Any channel
    # not passed in is by default disabled
    sig { params(enabled_channels: T::Array[String]).void }
    def initialize(enabled_channels:)
      @email_enabled = enabled_channels.include?(CHANNEL_EMAIL)
    end

    sig { returns(T::Boolean) }
    def email_enabled?
      @email_enabled == true
    end

    sig { returns(RS::RoutingSetting) }
    def to_routing_setting
      RS::RoutingSetting.new.tap do |routing|
        routing.name = "notifyd_issue_participating_activity_email"

        routing.topics.push(RS::Topic.new(type: "any", value: "any"))
        routing.channels.push(RS::Channel.new(
          name: CHANNEL_EMAIL,
          enabled: @email_enabled,
        ))

        participating_activity = RS::Filter.new(
          subject_type: "any",
          trigger: "any",
          reason: "any",
        )

        participating_activity.match_rules.push(RS::MatchRule.new(
            attribute: "thread_participant_activity",
            value: "true",
            match_rule: "eq",
          ))

        participating_activity.match_rules.push(RS::MatchRule.new(
          value: "participant",
          match_rule: "in_reason_group",
        ))

        routing.filters.push(participating_activity)

        routing.custom_fields.push(RS::CustomField.new(name: "category", value: "user_setting_participant_activity"))
      end
    end
  end
end
