# typed: true
# frozen_string_literal: true

# Displays for owners who attempted to convert an Enterprise account trial, but were blocked by RBI restrictions.
class Businesses::RBIFailedPaymentTrialAccountBannerComponent < ApplicationComponent
  attr_reader :business, :current_user

  def initialize(business:, current_user:)
    @business = business
    @current_user = current_user
  end

  private

  def render?
    return false unless GitHub.billing_enabled?
    return false unless business.present?
    return false unless current_user.present?
    return false unless business.trial?
    return false unless business.adminable_by?(current_user)

    business.autopay_disabled_by_india_rbi?
  end
end
