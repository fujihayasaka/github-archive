# typed: strict
# frozen_string_literal: true

class Stafftools::Billing::AddressValidationsController < StafftoolsController
  before_action :ensure_customer_exists
  before_action :ensure_contact_exists
  before_action :ensure_customer_requires_validation

  sig { void }
  def update
    address_validity_response = contact.validate_address
    address_is_valid = address_validity_response.valid
    address_validity_error = address_validity_response.error

    unless address_is_valid
      return redirect_to :back, flash: { address_validation_error: address_validity_error }
    end

    if contact.save
      redirect_to :back, notice: "Address validation completed successfully."
    else
      redirect_to :back, flash: { error: "Failed to save #{contact.address_type} contact: #{contact.errors.full_messages.to_sentence}" }
    end
  end

  private

  sig { returns(T.nilable(Customer)) }
  memoize def customer
    Customer.find_by(id: params[:customer_id])
  end

  sig { returns(Billing::Contact) }
  memoize def contact
    T.must(customer).contact_for_tax
  end

  sig { void }
  def ensure_customer_exists
    return if customer.present?
    redirect_to :back, flash: { error: "Customer not found" }
  end

  sig { void }
  def ensure_contact_exists
    return if contact.persisted?
    redirect_to :back, flash: { error: "No billing contact was found for address validation" }
  end

  sig { void }
  def ensure_customer_requires_validation
    return if !T.must(customer).has_valid_address_for_tax?
    redirect_to :back, flash: { error: "Billing contact does not need address validation" }
  end
end
