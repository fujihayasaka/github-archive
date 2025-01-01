# typed: true
# frozen_string_literal: true

# Renders a persistent banner on all pages of a business that has been downgraded to
# the free plan after coupon expiration because it doesn't have a valid payment
# method on file
class Businesses::DowngradedFromCouponExpirationBannerComponent < ApplicationComponent
  attr_reader :business, :current_user

  def initialize(business:, current_user:)
    @business = business
    @current_user = current_user
  end

  private

  def render?
    return false unless GitHub.billing_enabled?
    return false unless @business.present?
    return false unless @current_user.present?
    return false if @business.dunning?
    return false if @business.trial_expired?
    return false if @business.has_valid_payment_method?
    return false unless @business.downgraded_to_free_plan?

    business.adminable_by?(current_user) || business.billing_manager?(current_user)
  end
end
