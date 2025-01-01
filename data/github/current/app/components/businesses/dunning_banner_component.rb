# typed: true
# frozen_string_literal: true

# Renders a persistent banner on all pages of a business in a dunning state.
class Businesses::DunningBannerComponent < ApplicationComponent
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
    return false if @business.downgraded_to_free_plan?
    return false if @business.unable_to_bill?
    return false unless @business.dunning?
    return false if @business.customer&.auto_pay_reasons&.any?

    business.adminable_by?(current_user) || business.billing_manager?(current_user)
  end
end
