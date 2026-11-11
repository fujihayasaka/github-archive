# typed: strict
# frozen_string_literal: true

class Billing::Zuora::TaxationItem

  sig { params(raw_zuora_response: T::Hash[String, T.untyped]).void }
  def initialize(raw_zuora_response)
    @taxation_item_response = raw_zuora_response
  end

  sig { returns(String) }
  def id
    taxation_item_response["id"]
  end

  sig { returns(Billing::Money) }
  def tax_amount
    Billing::Money.new(taxation_item_response["taxAmount"] * 100)
  end
  alias_method :amount, :tax_amount

  sig { returns(Billing::Money) }
  def exempt_amount
    Billing::Money.new(taxation_item_response["exemptAmount"] * 100)
  end

  sig { returns(String) }
  def jurisdiction
    taxation_item_response["jurisdiction"]
  end

  sig { returns(T.nilable(String)) }
  def country
    taxation_item_response["country"]
  end

  sig { returns(Billing::Money) }
  def applicable_tax_unrounded
    Billing::Money.new(taxation_item_response["applicableTaxUnRounded"] * 100)
  end

  sig { returns(String) }
  def name
    taxation_item_response["name"]
  end

  sig { returns(String) }
  def location_code
    taxation_item_response["locationCode"]
  end

  sig { returns(String) }
  def tax_code
    taxation_item_response["taxCode"]
  end

  sig { returns(String) }
  def tax_code_description
    taxation_item_response["taxCodeDescription"]
  end

  sig { returns(Date) }
  def tax_date
    Date.parse(taxation_item_response["taxDate"])
  end

  sig { returns(Float) }
  def tax_rate
    taxation_item_response["taxRate"]
  end

  sig { returns(String) }
  def tax_rate_description
    taxation_item_response["taxRateDescription"]
  end

  sig { returns(String) }
  def tax_rate_type
    taxation_item_response["taxRateType"]
  end

  sig { returns(String) }
  def source_name
    "zuora"
  end

  private

  sig { returns(T::Hash[String, T.untyped]) }
  attr_reader :taxation_item_response
end
