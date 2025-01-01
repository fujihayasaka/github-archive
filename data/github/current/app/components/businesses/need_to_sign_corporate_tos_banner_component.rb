# typed: true
# frozen_string_literal: true

# Renders a persistent banner on all pages of a business that has not
# signed the corporate terms of service
class Businesses::NeedToSignCorporateTosBannerComponent < ApplicationComponent
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
    return false if !business.adminable_by?(current_user) && !business.billing_manager?(current_user)
    return false unless @business.feature_flag_enabled?(:business_on_standard_tos, default: false)

    @business.terms_of_service_type == "Standard"
  end
end
