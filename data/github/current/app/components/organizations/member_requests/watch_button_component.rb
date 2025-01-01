# typed: true
# frozen_string_literal: true

require "notifyd-client"

class Organizations::MemberRequests::WatchButtonComponent < ApplicationComponent
  attr_reader :user, :organization

  def initialize(user:, organization:)
    @user = user
    @organization = organization
  end

  def subscribable_features
    MemberFeatureRequest::Feature.values
  end

  def opt_out_feature?(feature)
    return true if routing_setting.nil?

    routing_setting_filters.include?(feature)
  end

  def subscription_type
    return :watching if routing_setting.nil? || watching?
    return :custom if custom?

    :ignoring
  end

  def notification_enabled
    subscription_type == :watching || subscription_type == :custom
  end

  def notification_disabled
    subscription_type == :ignoring
  end

  private

  def watching?
    routing_setting.channels.first.enabled
  end

  def custom?
    subscribable_features.any? do |feature|
      opt_out_feature?(feature.to_s)
    end
  end

  memoize def current_settings
    subscription = MemberFeatureRequest::Notification::Setting.new

    Notifyd::MemberFeatureRequestSettings.new(
      user: user,
      organization_id: organization.id,
      subscription: subscription
    ).get
  end

  memoize def routing_setting_filters
    routing_setting.filters.map(&:trigger)
  end

  memoize def routing_setting
    current_settings.routing_setting.first
  end
end
