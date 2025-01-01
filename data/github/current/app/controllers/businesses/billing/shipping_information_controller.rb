# typed: strict
# frozen_string_literal: true

class Businesses::Billing::ShippingInformationController < Businesses::BillingsController
  include TradeControlsControllerMethods

  before_action :business_access_required
  before_action :shipping_information_required
  before_action do
    T.bind(self, Businesses::Billing::ShippingInformationController)
    check_trade_compliance(target: target, sdn_redirect: true)
  end

  sig { void }
  def create
    shipping_contact_params = if shipping_contact_same_as_billing
      billing_information_for_shipping
    else
      shipping_information_params
    end

    shipping_contact = this_business.shipping_contact
    shipping_contact.assign_attributes shipping_contact_params
    address_is_valid = true
    address_validity_error = nil
    if shipping_contact.address_validated_at.blank?
      address_validity_response = shipping_contact.validate_address
      address_is_valid = address_validity_response.valid
      address_validity_error = address_validity_response.error
    end

    if address_is_valid
      if shipping_contact.save(context: :entity_trade_screening)
        flash[:notice] = "Your shipping information has been added successfully."
      else
        flash[:error] = shipping_contact.errors.full_messages.to_sentence
      end
    else
      if shipping_contact_same_as_billing
        flash[:address_validation_error] = address_validity_error
      else
        flash[:shipping_address_validation_error] = address_validity_error
      end
    end

    redirect_back fallback_location: enterprise_billing_payment_information_path(this_business)
  end

  sig { void }
  def update
    shipping_contact_params = if shipping_contact_same_as_billing
      billing_information_for_shipping
    else
      shipping_information_params
    end

    shipping_contact = this_business.shipping_contact
    shipping_contact.assign_attributes shipping_contact_params
    address_is_valid = true
    address_validity_error = nil
    if shipping_contact.address_validated_at.blank?
      address_validity_response = shipping_contact.validate_address
      address_is_valid = address_validity_response.valid
      address_validity_error = address_validity_response.error
    end

    if !address_is_valid
      if shipping_contact_same_as_billing
        flash[:address_validation_error] = address_validity_error
      else
        flash[:shipping_address_validation_error] = address_validity_error
      end
    else
      if shipping_contact.save(context: :entity_trade_screening)
        flash[:notice] = "Your shipping information has been updated successfully."
      else
        flash[:error] = shipping_contact.errors.full_messages.to_sentence
      end
    end

    redirect_back fallback_location: enterprise_billing_payment_information_path(this_business)
  end

  private

  sig { returns(T::Boolean) }
  def shipping_contact_same_as_billing
    params[:same_as_billing] == "1"
  end

  sig { returns(ActionController::Parameters) }
  def shipping_information_params
    params.require(:billing_contact).permit(
      :entity_name,
      :address1,
      :address2,
      :city,
      :postal_code,
      :country_code,
      :region
    )
  end

  sig { void }
  def shipping_information_required
    render_404 unless this_business.shipping_information_required?
  end

  sig { returns(T.any(AccountScreeningProfile, Billing::Contact)) }
  memoize def billing_contact
    this_business.billing_contact
  end

  sig { returns(T::Hash[String, T.untyped]) }
  def billing_information_for_shipping
    {
      entity_name: billing_contact.entity_name,
      address1: billing_contact.address1,
      address2: billing_contact.address2,
      city: billing_contact.city,
      postal_code: billing_contact.postal_code,
      country_code: billing_contact.country_code,
      region: billing_contact.region,
      address_validated_at: billing_contact.address_validated_at
    }
  end

  sig { override.returns(Business) }
  memoize def target
    this_business
  end
end
