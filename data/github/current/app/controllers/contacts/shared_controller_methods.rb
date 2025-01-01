# typed: strict
# frozen_string_literal: true

module Contacts::SharedControllerMethods
  include GitHub::Memoizer
  include BusinessesHelper
  include OrganizationsHelper

  extend T::Sig
  extend T::Helpers

  requires_ancestor { ApplicationController }
  abstract!

  sig { abstract.returns(User) }
  def current_user; end

  sig { abstract.returns(Billing::Types::Account) }
  def target; end

  private

  sig { void }
  def ensure_reading_billing_contact_enabled
    return render_404 unless current_user.feature_enabled?(:read_billing_information_from_contacts)
    render_404 unless target.feature_enabled?(:read_billing_information_from_contacts)
  end

  sig { returns(T::Array[String]) }
  def create_or_update_billing_contact
    customer = target.customer || ::Billing::CreateCustomer.perform(target, actor: current_user).customer
    return ["Sorry, something went wrong and we weren't able to save your billing information"] if customer.nil?

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
    end

    errors
  end

  sig { returns(T::Array[String]) }
  def update_vat_code
    errors = T.let([], T::Array[String])
    return errors unless vat_code_param.present?
    customer = T.must(target.customer)

    # TODO: this should be removed once vat code is moved to the customer record
    screening_profile = target.trade_screening_record
    return errors unless screening_profile.persisted?
    screening_profile.vat_code = vat_code_param
    unless screening_profile.save
      errors += screening_profile.errors.to_a
    end

    # Right now the screening profile is the source of truth for the vat code so we should not update
    #   the customer record with the vat code if the screening profile is not updated
    if errors.blank?
      # The vat code is currently stored on the screening record, but in future it will be on the customer record
      customer.vat_code = vat_code_param
      unless customer.save
        # We don't want to raise errors for this YET!
        # errors += customer.errors.to_a
      end
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

    errors
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
    return false if target.user? || org_stos?
    true
  end

  sig { returns(T::Boolean) }
  def org_stos?
    target.org_is_on_standard_tos?
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
    params.require(:billing_information).permit(
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
    )
  end
end
