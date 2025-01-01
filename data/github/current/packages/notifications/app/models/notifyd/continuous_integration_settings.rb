# typed: true
# frozen_string_literal: true

module Notifyd
  class ContinuousIntegrationSettings
    # Routing Settings (RS) namespace
    RS = Notifyd::Proto::RoutingSettings

    CHANNEL_EMAIL = "EMAIL".freeze
    CHANNEL_WEB = "WEB".freeze

    attr_reader :continuous_integration_email, :continuous_integration_web, :continuous_integration_failures_only

    # Settings are initialized with an array of enabled channels. Any channel
    # not passed in is by default disabled
    sig { params(continuous_integration_email: T::Boolean, continuous_integration_web: T::Boolean, continuous_integration_failures_only: T::Boolean).void }
    def initialize(continuous_integration_email:, continuous_integration_web:, continuous_integration_failures_only:)
      @continuous_integration_email = continuous_integration_email
      @continuous_integration_web = continuous_integration_web
      @continuous_integration_failures_only = continuous_integration_failures_only
    end


    sig { returns(RS::RoutingSetting) }
    def to_routing_setting
      RS::RoutingSetting.new.tap do |routing|
        routing.name = "CI Activity"

        routing.topics.push(RS::Topic.new(type: "any", value: "any"))
        routing.channels.push(RS::Channel.new(
          name: CHANNEL_EMAIL,
          enabled: continuous_integration_email
        ))

        routing.channels.push(RS::Channel.new(
          name: CHANNEL_WEB,
          enabled: continuous_integration_web
        ))

        # Check Suite
        ci_activity = RS::Filter.new(
          subject_type: "any",
          trigger: "any",
          reason: "ci_activity",
        )
        if continuous_integration_failures_only
          ci_activity.match_rules.push(RS::MatchRule.new(
            attribute: "failed",
            value: "true",
            match_rule: "eq",
          ))
        end
        routing.filters.push(ci_activity)

        # WorkflowRun
        routing.filters.push(RS::Filter.new(
          subject_type: "any",
          trigger: "any",
          reason: "approval_requested",
        ))

        routing.custom_fields.push(RS::CustomField.new(
          name: "delivery_group",
          value: "ci_activity"
        ))
      end
    end
  end
end
