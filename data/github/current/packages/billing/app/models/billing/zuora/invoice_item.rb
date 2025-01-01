# typed: strict
# frozen_string_literal: true

class Billing::Zuora::InvoiceItem
  extend T::Sig

  sig do
    params(
      invoice_key: String,
      page: Integer,
      page_size: Integer
    ).returns(T::Array[Billing::Zuora::InvoiceItem])
  end
  def self.all(invoice_key:, page: 1, page_size: 40)
    response = GitHub.zuorest_client.get_invoice_invoice_items(invoice_key, page: page, page_size: page_size)
    return [] unless response["success"]

    invoice_items = response["invoiceItems"].map { |raw_invoice_item| new(raw_invoice_item) }
    next_page = response["nextPage"]
    while next_page
      page += 1
      response = GitHub.zuorest_client.get_invoice_invoice_items(invoice_key, page: page, page_size: page_size)
      next_page = response["nextPage"]
      if response["success"]
        invoice_items += response["invoiceItems"].map { |raw_invoice_item| new(raw_invoice_item) }
      end
    end

    invoice_items
  end

  sig { params(raw_zuora_response: T::Hash[String, T.untyped]).void }
  def initialize(raw_zuora_response)
    @invoice_item_response = raw_zuora_response
  end

  sig { params(attr: String).returns(T.untyped) }
  def [](attr)
    invoice_item_response[attr]
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
    self.class == other.class && invoice_item_response == other.send(:invoice_item_response)
  end

  sig { returns(String) }
  def id
    invoice_item_response["id"] || ""
  end

  sig { returns(String) }
  def charge_name
    invoice_item_response["chargeName"] || ""
  end

  sig { returns(String) }
  def unit
    invoice_item_response["unitOfMeasure"] || ""
  end

  sig { returns(Billing::Types::NonMoneyNumeric) }
  def quantity
    invoice_item_response["quantity"]
  end

  sig { returns(String) }
  def subscription_number
    invoice_item_response["subscriptionName"] || ""
  end

  sig { returns(String) }
  def subscription_id
    invoice_item_response["subscriptionId"] || ""
  end

  sig { returns(String) }
  def rate_plan_charge_id
    invoice_item_response["chargeId"] || ""
  end

  sig { returns(String) }
  def product_rate_plan_charge_id
    invoice_item_response["productRatePlanChargeId"] || ""
  end

  sig { returns(String) }
  def service_start_date
    invoice_item_response["serviceStartDate"] || ""
  end

  sig { returns(String) }
  def service_end_date
    invoice_item_response["serviceEndDate"] || ""
  end

  sig { returns(String) }
  def applied_to_item_id
    invoice_item_response["appliedToItemId"] || ""
  end

  sig { returns(Billing::Money) }
  def charge_amount
    amount = invoice_item_response["chargeAmount"]
    @charge_amount ||= T.let(::Billing::Money.new(amount * 100), T.nilable(Billing::Money))
  end

  # Public: The unit price for the invoice item. This will be the
  # unprorated, overridden version of charge_amount.
  sig { returns(Billing::Money) }
  def unit_price
    amount = invoice_item_response["unitPrice"]
    ::Billing::Money.new(amount * 100)
  end

  sig { returns(T::Array[Billing::Zuora::TaxationItem]) }
  def taxation_items
    taxation_items_response = invoice_item_response["taxationItems"]
    return [] unless taxation_items_response.present?

    taxation_items = taxation_items_response["data"].map do |taxation_item_response|
      Billing::Zuora::TaxationItem.new(taxation_item_response)
    end

    if taxation_items_response["nextPage"]
      GitHub.logger.warn(
        "Zuora tax items pagination is not supported yet.",
        "code.namespace": "Billing::Zuora::InvoiceItem",
        "code.function": "taxation_items",
        "gh.billing.zuora.invoice_item.id": id,
      )
      GitHub.dogstats.increment("billing.zuora.taxation_items.multiple_pages")
    end

    taxation_items
  end

  sig { params(name: String).returns(T::Boolean) }
  def charge_name_include?(name)
    charge_name.downcase.include?(name.downcase)
  end

  # Public: whether this invoice item references a subscribable such as a sponsors tier. so
  # consumers of can determine whether they'll need to do their own subscribable lookup.
  #
  # Subclasses should override this if instances may contain a subscribable.
  sig { returns(T::Boolean) }
  def subscribable?
    false
  end

  sig do
    params(
      subscribable: T.any(Billing::Types::Subscribable, Billing::ProductUUID),
      subscription_item: T.nilable(Billing::SubscriptionItem)
    ).returns(Billing::Zuora::SubscribableInvoiceItem)
  end
  def as_subscribable_invoice_item(subscribable:, subscription_item: nil)
    Billing::Zuora::SubscribableInvoiceItem.new(invoice_item_response,
      subscribable: subscribable,
      subscription_item: subscription_item,
    )
  end

  sig { returns(T::Hash[String, T.untyped]) }
  def science_attributes
    {
      id: id,
      class: self.class.name,
      charge_name: charge_name,
      quantity: quantity.to_f,
      subscription_id: subscription_id,
      subscription_number: subscription_number,
      unit: unit,
      rate_plan_charge_id: rate_plan_charge_id,
      service_start_date: service_start_date,
      service_end_date: service_end_date,
      subscribable_id: self.is_a?(Billing::Zuora::SubscribableInvoiceItem) ? subscribable.id : nil,
      subscription_item_id: self.is_a?(Billing::Zuora::SubscribableInvoiceItem) ? subscription_item&.id : nil,
    }
  end

  private

  sig { returns(T::Hash[String, T.untyped]) }
  attr_reader :invoice_item_response
end
