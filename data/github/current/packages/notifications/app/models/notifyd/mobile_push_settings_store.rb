# typed: true
# frozen_string_literal: true

module Notifyd
  # Encapsulates the queries to the routing setting service for
  # MobilePushSettings
  class MobilePushSettingsStore
    extend T::Sig
    RS = Notifyd::Proto::RoutingSettings

    sig { params(user: ::User).void }
    def initialize(user:)
      @user = user
      @flags = Flags.new(user)
    end

    sig { params(settings: MobilePushSettings).returns(T::Boolean) }
    def save(settings:)
      return true unless settings.dirty?

      result = RoutingSettingsService
        .new(user)
        .save(settings.to_routing_settings(user))

      settings.clean! if result

      result
    end

    # Queries the routing setting service and returns the right mobile push
    # settings for the given user.
    sig { returns(MobilePushSettings) }
    def get
      ci_resp = if flags.push_ci_activity?
        RoutingSettingsService.new(user).get([MobilePushSettings::CI_ACTIVITY_CUSTOM_FIELD])
      else
        nil
      end

      releases_resp = if flags.push_releases?
        RoutingSettingsService.new(user).get(MobilePushSettings::RELEASES_CUSTOM_FIELDS)
      else
        nil
      end

      ci_routing_settings = ci_resp&.routing_setting&.find_all { |r| r.channels.any? { |c| c.name.downcase == "push" } } || []
      releases_push_setting = releases_resp&.routing_setting&.find_all { |r| r.channels.any? { |c| c.name.downcase == "push" } } || []
      all_routing_settings = ci_routing_settings + releases_push_setting

      return MobilePushSettings.default unless !all_routing_settings.empty?
      MobilePushSettings.new_from_routing_setting(all_routing_settings)
    end

    private

    sig { returns(::User) }
    attr_reader :user
    sig { returns(Flags) }
    attr_reader :flags
  end
end
