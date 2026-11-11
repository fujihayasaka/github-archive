# typed: strict
# frozen_string_literal: true

class Billing::Settings::AddressNeedsValidationComponent < ApplicationComponent
  include ResilienceHelper

  class AddressType < T::Enum
    enums do
      Billing = new("billing")
      Shipping = new("shipping")
    end
  end

  sig { params(account: Billing::Types::Account, link_to_user_billing_information: T::Boolean, address_type: AddressType, system_arguments: T::Hash[T.untyped, T.untyped]).void }
  def initialize(account:, link_to_user_billing_information: false, address_type: AddressType::Billing, system_arguments: {})
    @account = account
    @link_to_user_billing_information = link_to_user_billing_information
    @address_type = T.let(address_type.serialize, String)
    @system_arguments = system_arguments
  end

  sig { returns(Billing::Types::Account) }
  attr_reader :account

  sig { returns(T::Boolean) }
  attr_reader :link_to_user_billing_information

  sig { returns(T::Hash[T.untyped, T.untyped]) }
  attr_reader :system_arguments

  sig { returns(String) }
  attr_reader :address_type

  sig { returns(String) }
  def path_to_billing_information
    if account.organization? && account.org_is_on_business_tos?
      settings_org_billing_tab_path(account, tab: "payment_information", return_to: request&.fullpath)
    else
      settings_user_billing_tab_path(tab: "payment_information", return_to: request&.fullpath)
    end
  end

  private

  sig { returns(T::Boolean) }
  def render?
    customer = account.customer
    return false if customer.nil?
    return false if customer.has_valid_address_for_tax?
    return false if address_type != customer.contact_for_tax.address_type

    true
  end
end
