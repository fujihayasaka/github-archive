# typed: strict
# frozen_string_literal: true

module Contacts::SharedControllerMethods
  include GitHub::Memoizer
  include BusinessesHelper
  include OrganizationsHelper
  include TradeControlsControllerMethods

  extend T::Helpers

  requires_ancestor { ApplicationController }
  abstract!

  sig { abstract.returns(User) }
  def current_user; end

  sig { params(skip_redirect: T::Boolean).returns(T::Boolean) }
  def update_billing_contact(skip_redirect: false)
    return update_trade_screening_record(skip_redirect:) unless target_billable_owner.feature_flag_enabled?(:read_billing_information_from_contacts, default: false)

    validate_trade_restrictions
    validate_billing_contact_params
    validate_address
    update_vat_code
    setting_ctos? ? create_new_contact_with_tos : create_or_update_billing_contact
    link_billing_contact if linking_contact?
    update_billing_email
    instrument_copilot

    finalize_billing_contact(skip_redirect)
  end

  private

  sig { returns(T::Boolean) }
  def validate_trade_restrictions
    return false if errors?
    return true unless current_user.has_update_trade_restrictions? || T.must(target).has_update_trade_restrictions?

    errors_array << "An error occurred while saving contact information."
    log_contact_error(action: T.must(__method__))
    false
  end

  # If the billing contact parameters is not valid, we cannot proceed
  sig { returns(T::Boolean) }
  def validate_billing_contact_params
    return false if errors?
    target_billing_contact.assign_attributes(billing_contact_params)
    T.must(target_billing_contact.customer).vat_code = vat_code_param

    return true if target_billing_contact.valid_for_trade_screening?(owner_type: account_type)
    errors_array << "An error occurred while saving billing information."
    log_contact_error(action: T.must(__method__))
    false
  end

  sig { returns(T::Boolean) }
  def validate_address
    return false if errors?
    response = target_billing_contact.validate_address
    return true if response.valid

    errors_array << response.error
    flash[:address_validation_error] = response.error
    log_contact_error(action: T.must(__method__))
    false
  end

  sig { returns(T::Boolean) }
  def create_or_update_billing_contact
    return false if errors?
    return true if target_billing_contact.save(context: validation_type)

    errors_array << "An error occurred while saving billing information."
    log_contact_error(action: T.must(__method__))
    false
  end

  sig { returns(T::Boolean) }
  def create_new_contact_with_tos
    return false if errors?
    existing_terms = org.terms_of_service.name
    existing_company = org.company_name

    return true if update_terms_of_service && create_or_update_billing_contact

    # If there are errors or the billing contact save failed revert the ToS changes
    org.terms_of_service.update(
      type: existing_terms,
      actor: current_user,
      company_name: existing_company,
    )

    errors_array << "An error occurred while saving business information."
    log_contact_error(action: T.must(__method__))
    false
  end

  sig { returns(T::Boolean) }
  def update_terms_of_service
    return false if errors?
    org.terms_of_service.update(
      type: Organization::TermsOfService::CORPORATE,
      actor: current_user,
      company_name: billing_contact_params[:entity_name])
  end

  sig { returns(T::Boolean) }
  def update_vat_code
    return false if errors?
    customer = target_billable_owner.find_or_create_customer

    customer.vat_code = vat_code_param
    return true if customer.save

    errors_array << "An error occurred while saving billing information."
    log_contact_error(action: T.must(__method__))
    false
  end

  sig { returns(T::Boolean) }
  def link_billing_contact
    return false if errors?
    return true if org.link_billing_contact(actor: current_user)

    errors_array << "An error occurred while linking billing information."
    log_contact_error(action: T.must(__method__))
    false
  end

  sig { returns(T::Boolean) }
  def update_billing_email
    return false if errors?
    return true unless billing_email = params.dig(:organization, :billing_email)

    target_billable_owner.billing_email = billing_email
    return true if target_billable_owner.save

    errors_array << "An error occurred while saving billing email."
    log_contact_error(action: T.must(__method__))
    false
  end

  sig { void }
  def instrument_copilot
    return false if errors?
    if params[:return_to].to_s.include?("copilot")
      # we need to instrument this as the address being saved for the CFI flow
      utm_query_params = params.to_unsafe_h.slice(*::Copilot::SignupController::UTM_PARAMS).symbolize_keys
      current_copilot_user = self.current_copilot_user
      if current_copilot_user
        Copilot::Instrumenter.instrument_signup_saved_address(current_copilot_user,
          utm_query_params: utm_query_params)
      end
    end
  end

  sig { params(skip_redirect: T::Boolean).returns(T::Boolean) }
  def finalize_billing_contact(skip_redirect)
    instrument_billing_form_submitted

    if errors?
      stash_errors
      flash[:error] = errors_array.to_sentence
    else
      delete_stashed_errors
      flash[:notice] = "Successfully updated billing information."
    end

    unless skip_redirect
      if params[:return_to].present? && !errors?
        safe_redirect_to params[:return_to]
      else
        redirect_back(fallback_location: billing_path)
      end
    end

    !errors?
  end

  sig { void }
  def stash_errors
    # The billing info form builders always use target.billing_contact to build the form,
    # however when the admin of an org tries to create their billing info to link to an org and
    # there are errors, the errors are stored in the admin billing info record, the link is not created
    # and target.billing_contact is empty. Updating the stash with the admin billing info errors
    # causes the form to retain the submitted values and errors scoped to the original target.
    Billing::ContactUpdateStash.stash_update_for(
      T.must(target),
      "billing",
      billing_contact_params.merge(vat_code: vat_code_param),
      target_billing_contact.errors
    )
  end

  sig { void }
  def delete_stashed_errors
    Billing::ContactUpdateStash.delete_stashed_update_for(T.must(target), "billing")
  end

  sig { params(action: Symbol, success: T::Boolean, errors: T::Array[String]).void }
  def report_status(action:, success:, errors: [])
    return increment_dogstats_metric(action:, success:) if success
    log_contact_error(action:, errors:)
  end

  sig { params(action: Symbol, success: T::Boolean).void }
  def increment_dogstats_metric(action:, success:)
    GitHub.dogstats.increment(self.class.name.demodulize.underscore, tags: ["action:#{action}", "success:#{success}"])
  end

  sig { params(action: Symbol, errors: T::Array[String]).void }
  def log_contact_error(action:, errors: [])
    errors = errors | errors_array | target_billing_contact_errors
    GitHub.logger.error(
      "#{self.class.name.demodulize.underscore}.#{action}.error",
      "gh.user.id": current_user.id,
      "gh.billing_contacts_controller.target_id": target&.id,
      errors: errors
    )

    increment_dogstats_metric(action:, success: false)
  end

  sig { returns(Symbol) }
  def account_type
    if is_entity?
      :entity_trade_screening
    else
      :individual_trade_screening
    end
  end

  sig { returns(Symbol) }
  def validation_type
    if is_entity?
      :entity_trade_screening
    else
      :individual_trade_screening
    end
  end

  sig { returns(T::Boolean) }
  def linking_contact?
    return false if setting_ctos?
    return false unless org_stos?
    return true if params["org_record_is_individual_owned"].present?
    return false unless params["tos_org_linkage_only"].present?

    true
  end

  sig { returns(T::Boolean) }
  def is_entity?
    return true if setting_ctos?
    return false if T.must(target).user? || org_stos?
    true
  end

  sig { returns(T::Boolean) }
  def org_stos?
    T.must(target).org_is_on_standard_tos?
  end

  sig { returns(T::Boolean) }
  def setting_ctos?
    return false unless params["is_business"] == "true"
    org_stos?
  end

  sig { returns(T.nilable(String)) }
  def vat_code_param
    params[:vat_code]
  end

  sig { returns(ActionController::Parameters) }
  def billing_contact_params
    params.require(:billing_contact).permit(
      :first_name,
      :last_name,
      :middle_name,
      :region,
      :city,
      :country_code,
      :postal_code,
      :address1,
      :address2,
      :entity_name
    )
  end

  sig { returns(ActionController::Parameters) }
  def shipping_contact_params
    params.require(:shipping_contact).permit(
      :first_name,
      :last_name,
      :middle_name,
      :region,
      :city,
      :country_code,
      :postal_code,
      :address1,
      :address2,
      :entity_name
    )
  end

  sig { returns(Organization) }
  memoize def org
    T.cast(target, Organization)
  end

  sig { returns(Billing::Types::Account) }
  memoize def target_billable_owner
    target = T.must_because(self.target) { "this action can only occur on a valid target" }
    setting_ctos? || !org_stos? ? target : current_user
  end

  sig { returns(Billing::Contact) }
  memoize def target_billing_contact
    customer = target_billable_owner.find_or_create_customer
    Billing::Contact.find_or_initialize_by(customer_id: customer.id, address_type: :billing)
  end

  sig { returns(T::Array[String]) }
  def target_billing_contact_errors
    target_billing_contact.errors.full_messages
  end

  sig { returns(T::Array[String]) }
  memoize def errors_array
    T.let([], T::Array[String])
  end

  sig { returns(T::Boolean) }
  def errors?
    errors_array.any?
  end

  sig { override.returns(T.nilable(Billing::Types::Account)) }
  memoize def target
    return business_target if params[:target] == "business"
    return organization_target if params[:target] == "organization"

    current_user
  end

  sig { returns(T.nilable(Organization)) }
  memoize def organization_target
    org = current_organization_for_member_or_billing
    return unless org

    if org.billing_manageable_by?(current_user)
      org
    end
  end

  sig { returns(T.nilable(Business)) }
  memoize def business_target
    business = current_business
    return unless business

    if current_user_can_manage_settings(business) || business.billing_manager?(current_user)
      business
    end
  end
end
