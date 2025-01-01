# typed: true
# frozen_string_literal: true

class Organizations::Settings::TermsOfServiceComponent < ApplicationComponent
  include BillingSettingsHelper
  attr_reader :user, :organization

  def initialize(organization:, user:)
    @organization = organization
    @user = user
    @tos_type = organization.terms_of_service.name
  end

  def render?
    return false if GitHub.enterprise?
    return false if user.nil?
    return false if organization.nil?

    organization.adminable_by?(user) || organization.billing_manager?(user)
  end

  def standard_tos?
    @tos_type == "Standard"
  end

  def corporate_tos?
    @tos_type == "Corporate"
  end

  def can_sign_corporate_tos?
    return false if corporate_tos?
    return false if organization.archived?
    return false unless user.trade_screening_record.sdn_status_allowed?(feature_type: :terms_of_service_change)

    organization.trade_screening_record.sdn_status_allowed?(feature_type: :terms_of_service_change)
  end

  def collect_trade_screening_data?
    return true if organization.trade_screening_record.persisted?

    !organization.free_plan?
  end

  def warn_about_linked_billing_details_removal?
    organization.has_linked_trade_screening_record? && organization.has_valid_payment_method?(feature_type: :noncommercial)
  end

  def payment_method_update_path
    target_payment_method_path(organization)
  end

  private

  memoize def terms_of_service
    organization.terms_of_service
  end
end
