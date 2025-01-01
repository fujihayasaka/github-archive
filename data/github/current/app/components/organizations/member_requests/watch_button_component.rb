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

  def subscription_type
    return :watching if watching?
    return :ignoring if current_settings.features.empty?
    :custom
  end

  def notification_enabled
    subscription_type == :watching || subscription_type == :custom
  end

  def notification_disabled
    subscription_type == :ignoring
  end

  private

  def watching?
    subscribable_features & current_settings.features == subscribable_features
  end

  memoize def current_settings
    Notifications::Settings.member_feature_requests(user, organization.id)
  end
end
