# typed: strict
# frozen_string_literal: true

class Organizations::NewTermsOfServiceRequiredComponent < ApplicationComponent
  extend T::Sig

  sig { returns(Organization) }
  attr_reader :organization

  sig { params(organization: Organization).void }
  def initialize(organization:)
    @organization = organization
  end

  sig { returns(T::Boolean) }
  def render?
    return false unless GitHub.billing_enabled?
    return false unless logged_in?
    return false unless current_user.present?
    return false unless organization.present?
    return false unless organization.feature_enabled?(:display_terms_of_service_update_banner)
    return false unless organization.adminable_by?(current_user)
    return false if organization.invoiced?
    return false unless organization.eligible_for_upgrade_to_enterprise?
    organization.terms_of_service&.standard?
  end
end
