# typed: strict
# frozen_string_literal: true

# This controller is for the creating and updating of customer contact information
class BillingSettings::ContactsController < ApplicationController
  include Contacts::SharedControllerMethods

  before_action :ensure_billing_enabled
  before_action :login_required
  before_action :ensure_target
  before_action :ensure_reading_billing_contact_enabled
  before_action :ensure_not_standard_terms_org
  before_action :ensure_target_billing_contact_exists, only: [:update, :destroy]
  before_action do
    T.bind(self, BillingSettings::ContactsController)
    check_trade_compliance(target: target, sdn_redirect: true)
  end

  # Create a new contact information record from parameters
  # This would also include tos changes
  sig { void }
  def create
    errors = validate_billing_contact_params
    if errors.empty?
      errors = (setting_ctos? ? create_new_contact_with_tos : create_or_update_billing_contact)
    end

    if errors.empty?
      flash[:success] = "Contact information saved successfully"
    else
      flash[:error] = errors.to_sentence
    end

    redirect_back(fallback_location: billing_path(target))
  end

  sig { void }
  def update
    errors = validate_billing_contact_params

    if errors.empty?
      errors = create_or_update_billing_contact
    end

    if errors.empty?
      flash[:success] = "Contact information updated successfully"
    else
      flash[:error] = errors.to_sentence
    end

    redirect_back(fallback_location: billing_path(target))
  end

  sig { void }
  def destroy
    billing_contact = T.must(target).billing_contact
    if billing_contact.destroy
      flash[:success] = "Contact information deleted successfully"
    else
      flash[:error] = "Unable to delete contact information"
    end

    redirect_back(fallback_location: billing_path(target))
  end

  private

  sig { returns(T::Array[String]) }
  def create_new_contact_with_tos
    organization = T.cast(target, Organization)
    errors = T.let([], T::Array[String])
    existing_terms = organization.terms_of_service.name
    existing_company = organization.company_name

    unless organization.terms_of_service.update(
      type: Organization::TermsOfService::CORPORATE,
      actor: current_user,
      company_name: billing_contact_params[:entity_name],
    )
      errors << "An error occurred while saving business information."
    end

    errors = create_or_update_billing_contact if errors.empty?

    if !errors.empty?
      # If there are errors and setting CToS revert the ToS changes
      organization.terms_of_service.update(
        type: existing_terms,
        actor: current_user,
        company_name: existing_company,
      )
    end

    errors
  end

  sig { void }
  def ensure_target
    render_404 if target.nil?
  end

  sig { void }
  def ensure_not_standard_terms_org
    render_404 if self.org_stos? && !self.setting_ctos?
  end

  sig { void }
  def ensure_target_billing_contact_exists
    render_404 unless T.must(target).billing_contact.persisted?
  end
end
