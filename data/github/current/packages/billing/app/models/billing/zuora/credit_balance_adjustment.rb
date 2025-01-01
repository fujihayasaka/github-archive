# typed: strict
# frozen_string_literal: true

class Billing::Zuora::CreditBalanceAdjustment
  extend T::Sig

  include GitHub::Memoizer

  sig { returns(T::Hash[String, T.untyped]) }
  attr_reader :zuora_credit_balance_adjustment

  sig { returns(T.nilable(Billing::Types::Account)) }
  attr_accessor :billable_entity

  sig { params(adjustment_id: T.nilable(String)).returns(Billing::Zuora::CreditBalanceAdjustment) }
  def self.find(adjustment_id)
    credit_balance_adjustment = GitHub.zuorest_client.get_credit_balance_adjustment(adjustment_id)
    new(credit_balance_adjustment)
  end

  sig { params(zuora_credit_balance_adjustment: T::Hash[String, T.untyped]).void }
  def initialize(zuora_credit_balance_adjustment)
    @zuora_credit_balance_adjustment = zuora_credit_balance_adjustment
  end

  sig { returns(String) }
  def id
    cba["Id"]
  end

  sig { returns(String) }
  def number
    cba["Number"]
  end

  sig { returns(Billing::Types::NonMoneyNumeric) }
  def amount
    money_amount.dollars
  end

  sig { returns(Integer) }
  def amount_in_cents
    money_amount.cents
  end

  sig { returns(Time) }
  def created_date
    Time.parse(cba["CreatedDate"])
  end

  sig { returns(T::Array[Billing::Zuora::Invoice]) }
  memoize def invoices
    [::Billing::Zuora::Invoice.new(cba["SourceTransactionId"])]
  end

  sig { returns(T::Array[Billing::Zuora::InvoiceItem]) }
  memoize def invoice_items
    invoices.flat_map(&:invoice_items)
  end

  # For the interface sake. Create Billing Transaction asks for a reference ID or a payment Number
  # We'll use reference ID but we'll transition these methods to be something more generic
  sig { returns(String) }
  def reference_id
    number
  end

  sig { returns(T::Boolean) }
  def stripe?
    false
  end

  sig { returns({ credit_balance_adjustment_number: String }) }
  def sponsors_metadata
    { credit_balance_adjustment_number: number }
  end

  sig { params(billing_transaction: Billing::BillingTransaction).void }
  def decorate_billing_transaction(billing_transaction)
    billing_transaction.transaction_id = reference_id
    billing_transaction.last_status = Billing::BillingTransactionStatuses::ALL[:credit_balance_adjusted]
  end

  private

  sig { returns(T::Hash[String, T.untyped]) }
  def cba
    zuora_credit_balance_adjustment
  end

  sig { returns(Billing::Money) }
  def money_amount
    ::Billing::Money.new(cba["Amount"] * 100)
  end
end
