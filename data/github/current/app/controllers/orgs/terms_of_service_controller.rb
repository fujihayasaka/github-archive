# typed: true
# frozen_string_literal: true

class Orgs::TermsOfServiceController < ApplicationController
  include OrganizationsHelper
  include TradeControlsControllerMethods
  include Contacts::SharedControllerMethods

  before_action :login_required
  before_action :org_members_only
  before_action :org_admins_only
  after_action :customer_category_instrumentation

  def update
    on_corporate_terms = current_organization && current_organization.terms_of_service.corporate?
    new_terms_value = params[:organization][:terms_of_service_type]
    company_name = params[:organization][:company_name]

    if on_corporate_terms && current_organization.company&.name.present? && new_terms_value == Organization::TermsOfService::CORPORATE
      return redirect_to :back, flash: { error: "The terms of service is already up-to-date for this organization" }
    end

    if params.key?("billing_info_submit_btn") && new_terms_value == Organization::TermsOfService::CORPORATE
      params[:is_business] = "true"
      if update_billing_contact(skip_redirect: true)
        return redirect_to :back, notice: "Terms of service updated!"
      end

      return redirect_to :back, flash: { error: "An error occurred while saving business information." }
    end

    if current_organization.terms_of_service.update(
      type: new_terms_value,
      actor: current_user,
      company_name: company_name,
    )
      redirect_to :back, notice: "Terms of service updated!"
    else
      redirect_to :back, flash: { error: current_organization.errors.full_messages.to_sentence }
    end
  end

  private

  memoize def target
    current_organization
  end
end
