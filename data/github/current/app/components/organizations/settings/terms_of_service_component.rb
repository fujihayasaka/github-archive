# typed: strict
# frozen_string_literal: true

class Organizations::Settings::TermsOfServiceComponent < ApplicationComponent
  include BillingSettingsHelper
  sig { returns(User) }
  attr_reader :user

  sig { returns(Organization) }
  attr_reader :organization

  sig { params(organization: Organization, user: User).void }
  def initialize(organization:, user:)
    @organization = organization
    @user = user
    @tos_type = T.let(organization.terms_of_service.name, String)
  end

  sig { returns(T::Boolean) }
  def render?
    return false if GitHub.enterprise?
    return false if user.nil?
    return false if organization.nil?

    organization.adminable_by?(user) || organization.billing_manager?(user)
  end

  sig { returns(T::Boolean) }
  def standard_tos?
    @tos_type == "Standard"
  end

  sig { returns(T::Boolean) }
  def corporate_tos?
    @tos_type == "Corporate"
  end

  sig { returns(T::Boolean) }
  def can_sign_corporate_tos?
    return false if corporate_tos?
    return false if organization.archived?
    return false if user.has_commercial_interaction_restriction?(feature_type: :terms_of_service_change)

    !organization.has_commercial_interaction_restriction?(feature_type: :terms_of_service_change)
  end

  sig { returns(T::Boolean) }
  def collect_trade_screening_data?
    return true if organization.billing_contact.persisted?

    !organization.free_plan?
  end

  sig { returns(T::Boolean) }
  def warn_about_linked_billing_details_removal?
    organization.has_linked_billing_contact? && organization.has_valid_payment_method?(feature_type: :noncommercial)
  end

  sig { returns(String) }
  def payment_method_update_path
    target_payment_method_path(organization)
  end

  private

  sig { returns(Organization::TermsOfService) }
  memoize def terms_of_service
    organization.terms_of_service
  end
end
