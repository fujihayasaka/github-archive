# typed: true
# frozen_string_literal: true
class VerifiableDomains::NotificationBannerComponent < ApplicationComponent

  def initialize(deferred: false, organization:)
    @deferred = deferred
    @organization = organization
  end

  private

  def show_notification_restriction_banner?
    return false unless organization

    organization.show_notification_restriction_banner?(current_user)
  end

  attr_reader :deferred, :organization
  alias_method :deferred?, :deferred
end
