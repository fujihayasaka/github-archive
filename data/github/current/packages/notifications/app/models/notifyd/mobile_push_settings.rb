# typed: true
# frozen_string_literal: true

module Notifyd
  class MobilePushSettings
    extend T::Sig

    RS = Notifyd::Proto::RoutingSettings
    CI_ACTIVITY_CUSTOM_FIELD = T.let(
      RS::CustomField.new(name: "mobile_delivery_group", value: "ci_activity"),
      RS::CustomField
    )

    RELEASES_CUSTOM_FIELDS =
      [
        T.let(
          RS::CustomField.new(name: "category", value: "user_setting_watcher_activity"),
          RS::CustomField
        ),
        T.let(
          RS::CustomField.new(name: "scenario", value: "user_settings"),
          RS::CustomField
        ),
      ]

    sig { returns(T::Boolean) }
    attr_reader :ci_activity
    sig { returns(T::Boolean) }
    attr_reader :ci_failed_only
    sig { returns(T::Boolean) }
    attr_reader :releases

    sig { params(ci_activity: T::Boolean, ci_failed_only: T::Boolean, releases: T::Boolean).void }
    def initialize(ci_activity: false, ci_failed_only: false, releases: false)
      @dirty = false
      @ci_activity = ci_activity
      @ci_failed_only = ci_failed_only
      @releases = releases
    end

    sig { returns(MobilePushSettings) }
    def self.default
      new(ci_activity: false, ci_failed_only: false, releases: false)
    end

    # Parses a an array of RoutingSettings and transforms it into a `MobilePushSettings`
    # struct.
    sig { params(settings: T::Array[RS::RoutingSetting]).returns(MobilePushSettings) }
    def self.new_from_routing_setting(settings)
      ci_activity_in_settings = settings.find do |setting|
        setting.custom_fields.any? { |cf| cf.name == CI_ACTIVITY_CUSTOM_FIELD.name && cf.value == CI_ACTIVITY_CUSTOM_FIELD.value }
      end

      releases_in_settings = settings.find do |setting|
        setting.custom_fields.any? { |cf| cf.name == RELEASES_CUSTOM_FIELDS[0].name && cf.value == RELEASES_CUSTOM_FIELDS[0].value }
      end

      MobilePushSettings.new(
        ci_activity: ci_activity_in_settings&.channels&.any? { |channel| channel.enabled } || false,
        ci_failed_only: Parser.failed_only?(settings),
        releases: releases_in_settings&.channels&.any? { |channel| channel.enabled } || false,
      )
    end

    sig { params(val: T::Boolean).returns(T::Boolean) }
    def ci_activity=(val)
      self.ci_failed_only = false unless val

      dirty! if ci_activity != val
      @ci_activity = val
    end

    sig { params(val: T::Boolean).returns(T::Boolean) }
    def ci_failed_only=(val)
      # noop if we want to enable failed only and ci activity is disabled
      return false if !ci_activity && val
      dirty! if ci_failed_only != val

      @ci_failed_only = val
    end

    sig { params(val: T::Boolean).returns(T::Boolean) }
    def releases=(val)
      dirty! if releases != val
      @releases = val
    end

    # Builds a RoutingSetting from a `MobilePushSettings`
    sig { params(user: ::User).returns(T::Array[RS::RoutingSetting]) }
    def to_routing_settings(user)
      flags = Flags.new(user)
      routing_settings = []

      if flags.push_ci_activity?
        routing_settings << to_ci_activity_routing_setting
      end

      if flags.push_releases?
        routing_settings << to_releases_routing_setting
      end
      routing_settings
    end

    # Builds a RoutingSetting from a `MobilePushSettings` for CI Activity
    sig { returns(RS::RoutingSetting) }
    def to_ci_activity_routing_setting
      RS::RoutingSetting.new.tap do |routing|
        routing = T.cast(routing, RS::RoutingSetting)
        routing.name = "CI Activity for Mobile"
        routing.topics << RS::Topic.new(type: "any", value: "any")
        routing.channels << RS::Channel.new(name: "PUSH", enabled: ci_activity)

        filter = RS::Filter.new(subject_type: "any", trigger: "any", reason: "ci_activity")

        if ci_failed_only
          filter.match_rules << RS::MatchRule.new(attribute: "failed", value: "true", match_rule: "eq")
        end

        routing.filters << filter

        routing.custom_fields << CI_ACTIVITY_CUSTOM_FIELD
      end
    end

    # Builds a RoutingSetting from a `MobilePushSettings` for watched activty
    sig { returns(RS::RoutingSetting) }
    def to_releases_routing_setting
      RS::RoutingSetting.new.tap do |routing|
        routing = T.cast(routing, RS::RoutingSetting)
        routing.name = "Release Activity for Mobile"
        routing.topics << RS::Topic.new(type: "any", value: "any")
        routing.channels << RS::Channel.new(name: "PUSH", enabled: releases)

        filter = RS::Filter.new(subject_type: "any", trigger: "any", reason: "any")

        filter.match_rules << RS::MatchRule.new(attribute: "thread_type", value: "release", match_rule: "eq")
        filter.match_rules << RS::MatchRule.new(attribute: "", value: "participant", match_rule: "not_in_reason_group")
        routing.filters << filter

        routing.custom_fields << RELEASES_CUSTOM_FIELDS[0]
        routing.custom_fields << RELEASES_CUSTOM_FIELDS[1]
      end
    end

    sig { returns(T::Boolean) }
    def dirty?
      @dirty
    end

    sig { void }
    def clean!
      @dirty = false
    end

    private

    sig { void }
    def dirty!
      @dirty = true
    end

    # Encapsulates the parsing of a routing setting into a MobilePushSettings
    # object.
    #
    # NOTE: (@franciscoj 23/11/2022) this looks to me as if we were missing a
    # read model of some sorts for our routing settings.
    #
    # Something that, once the settings are written, transforms them into
    # something that is readable by an integrator without the burden of having
    # to navigate the message/response structure of the Twirp services.
    class Parser
      extend T::Sig
      # Returns whether a given RoutingSetting enables CI activity only for
      # failed runs or not.
      sig { params(routing_settings: T::Array[RS::RoutingSetting]).returns(T::Boolean) }
      def self.failed_only?(routing_settings)
        ci_setting = routing_settings.find do |setting|
          setting.custom_fields.find { |cf| cf.name == CI_ACTIVITY_CUSTOM_FIELD.name && cf.value == CI_ACTIVITY_CUSTOM_FIELD.value }
        end

        failed_only_on = ci_setting&.filters&.any? do |f|
          f.match_rules.any? { |m| m.match_rule == "eq" && m.attribute == "failed" && m.value == "true" }
        end || false
        ci_push_enabled = ci_setting&.channels&.any? { |c| c.name.downcase == "push" && c.enabled } || false

        failed_only_on && ci_push_enabled
      end
    end
    private_constant :Parser
  end
end
