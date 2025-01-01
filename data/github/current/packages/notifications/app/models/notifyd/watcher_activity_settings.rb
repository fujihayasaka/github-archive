# typed: true
# frozen_string_literal: true

module Notifyd
  class WatcherActivitySettings
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
        routing.name = "notifyd_watcher_activity_setting"

        routing.topics.push(RS::Topic.new(type: "any", value: "any"))
        routing.channels.push(RS::Channel.new(
          name: CHANNEL_EMAIL,
          enabled: @email_enabled,
        ))

        watcher_activity = RS::Filter.new(
          subject_type: "any",
          trigger: "any",
          reason: "any",
        )

        watcher_activity.match_rules.push(RS::MatchRule.new(
          attribute: "watch_activity",
          value: "true",
          match_rule: "eq",
        ))

        watcher_activity.match_rules.push(RS::MatchRule.new(
          value: "participant",
          match_rule: "not_in_reason_group",
        ))

        routing.filters.push(watcher_activity)

        routing.custom_fields.push(RS::CustomField.new(name: "category", value: "user_setting_watcher_activity"))
      end
    end
  end
end
