# typed: strict
# frozen_string_literal: true

module Contacts::SharedControllerMethods
  include GitHub::Memoizer
  include BusinessesHelper
  include OrganizationsHelper

  extend T::Helpers

  requires_ancestor { ApplicationController }
  abstract!

  sig { abstract.returns(User) }
  def current_user; end

  private

  sig { void }
  def ensure_reading_billing_contact_enabled
    return render_404 unless current_user.feature_enabled?(:read_billing_information_from_contacts)
    render_404 unless T.must(target).feature_enabled?(:read_billing_information_from_contacts)
  end

  sig { returns(T::Array[String]) }
  def create_or_update_billing_contact
    customer = T.must(target).customer || ::Billing::CreateCustomer.perform(T.must(target), actor: current_user).customer
    if customer.nil?
      log_error(action: T.must(__method__), errors: ["Could not get or create customer, customer was nil"])

      return ["Sorry, something went wrong and we weren't able to save your billing information"]
    end

    billing_contact = Billing::Contact.find_or_initialize_by(customer_id: customer.id, address_type: :billing)

    errors = save_contact_with_params(billing_contact, billing_contact_params)
    errors.blank? ? update_vat_code : errors
  end

  sig { params(contact: Billing::Contact, params: ActionController::Parameters).returns(T::Array[String]) }
  def save_contact_with_params(contact, params)
    errors = T.let([], T::Array[String])

    contact.assign_attributes(params)
    unless contact.save(context: validation_type)
      errors += contact.errors.to_a
      log_error(action: T.must(__method__), errors: errors)
    end

    errors
  end

  sig { returns(T::Array[String]) }
  def update_vat_code
    errors = T.let([], T::Array[String])
    return errors unless vat_code_param.present?
    customer = T.must(T.must(target).customer)

    customer.vat_code = vat_code_param
    unless customer.save
      errors += customer.errors.to_a
      log_error(action: T.must(__method__), errors: errors)
    end

    errors
  end

  sig { returns(T::Array[String]) }
  def validate_billing_contact_params
    customer_details_params = billing_contact_params.to_h.symbolize_keys
    # Validation needs a request id, maybe find a way to remove this need!!!
    customer_details_params[:id] = SecureRandom.uuid
    customer_details = TradeCompliance::TradeScreening::CustomerDetails.new(**customer_details_params)
    errors = customer_details.validate(account_type: account_type)

    # validate for tax here too and merge and return any errors
    response = Billing::Contact.new(billing_contact_params).validate_address
    errors << response.error unless response.valid

    log_error(action: T.must(__method__), errors: errors) if errors.any?
    errors
  end

  sig { params(action: Symbol, success: T::Boolean).void }
  def increment_dogstats_metric(action:, success:)
    GitHub.dogstats.increment(self.class.name.demodulize.underscore, tags: ["action:#{action}", "success:#{success}"])
  end

  sig { params(action: Symbol, errors: T.nilable(T::Array[String])).void }
  def log_error(action:, errors: nil)
    GitHub.logger.error(
      "#{self.class.name.demodulize.underscore}.#{action}.error",
      "gh.user.id": current_user.id,
      "gh.billing_contacts_controller.target_id": target&.id,
      errors: errors
    )

    increment_dogstats_metric(action:, success: false)
  end

  sig { returns(TradeCompliance::TradeScreening::AccountType) }
  def account_type
    if is_entity?
      TradeCompliance::TradeScreening::AccountType::Business
    else
      TradeCompliance::TradeScreening::AccountType::Individual
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
      :entity_name,
      :vat_code
    )
  end

  sig { returns(T.nilable(Billing::Types::Account)) }
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
