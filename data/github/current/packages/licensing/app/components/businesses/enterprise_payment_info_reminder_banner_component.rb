# typed: true
# frozen_string_literal: true

# This component renders a persistent header on all business's page.
# This will display a reminder to setup payment information for the business.
class Businesses::EnterprisePaymentInfoReminderBannerComponent < ApplicationComponent
  include BusinessesHelper

  attr_reader :business

  def initialize(business)
    @business = business
  end

  sig { returns(T::Boolean) }
  def render?
    return false unless GitHub.billing_enabled?
    return false unless business.present?
    return false unless current_user.present?
    return false if business.metered_ghec_trial?
    return false if business.sales_managed? && !business.billed_through_azure_subscription?
    return false if metered_ghe_with_valid_payment_method?
    return false if business.linked_azure_subscription?
    return false if !business.metered_ghe?

    business.adminable_by?(current_user) || business.billing_manager?(current_user)
  end

  private

  sig { returns(T::Boolean) }
  def metered_ghe_with_valid_payment_method?
    business.metered_ghe? && business.has_valid_payment_method?
  end
end
