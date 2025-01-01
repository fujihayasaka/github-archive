# typed: strict
# frozen_string_literal: true

class Billing::PlanSubscription::CreateBillingTransaction
  extend T::Sig

  sig do
    params(
      plan_subscription: ::Billing::PlanSubscription,
      service_ends_at: ::Billing::Types::Time,
      zuora_transaction: T.nilable(T.any(Billing::Zuora::Payment, Billing::Zuora::CreditBalanceAdjustment))
    ).returns(Billing::BillingTransaction)
  end
  def self.perform(plan_subscription, service_ends_at:, zuora_transaction: nil)
    new(plan_subscription, service_ends_at: service_ends_at, zuora_transaction: zuora_transaction).perform
  end

  delegate :seats_delta, :asset_packs_delta, :charge_type,
    to: :charge_type_resolver
  delegate :billable_entity, to: :plan_subscription

  # Initialize a new CreateBillingTransaction
  #
  # plan_subscription     - The user's Billing::PlanSubscription
  # service_ends_at       - The date when the user's current billing period ends
  # zuora_transaction     - The associated Billing::Zuora::Payment for the transaction
  sig do
    params(
      plan_subscription: ::Billing::PlanSubscription,
      service_ends_at: ::Billing::Types::Time,
      zuora_transaction: T.nilable(T.any(Billing::Zuora::Payment, Billing::Zuora::CreditBalanceAdjustment))
    ).void
  end
  def initialize(plan_subscription, service_ends_at:, zuora_transaction: nil)
    @plan_subscription      = plan_subscription
    @zuora_transaction      = zuora_transaction
    @service_ends_at        = T.let(service_ends_at.to_time, Time)
  end

  # Public: Create the BillingTransaction based on a Zuora payment transaction
  sig { returns(Billing::BillingTransaction) }
  def perform
    # TODO remove this (and callers) once the `invoice_items_resolver` experiment is complete. This is used to
    # avoid the performance penalty of the billable entity lookup from within a Billing::Zuora::Invoice, which
    # caused degraded daily payment processing.
    zuora_transaction = self.zuora_transaction
    if zuora_transaction && zuora_transaction.respond_to?(:billable_entity=)
      zuora_transaction.billable_entity = billable_entity
    end

    create_from_zuora_transaction
  end

  private

  # Internal: Create a BillingTransaction from a Zuora::Payment object
  #
  sig { returns(Billing::BillingTransaction) }
  def create_from_zuora_transaction
    Billing::BillingTransaction.retry_on_find_or_create_error do
      zuora_transaction = T.must(self.zuora_transaction)
      transaction_id = zuora_transaction.reference_id || zuora_transaction.number
      billing_transaction = if plan_subscription.billable_business?
        Billing::BillingTransaction.find_by(customer_id: billable_entity.customer_id, transaction_id: transaction_id) ||
        Billing::BillingTransaction.new(customer_id: billable_entity.customer_id, transaction_id: transaction_id)
      else
        Billing::BillingTransaction.find_by(user_id: billable_entity.id, transaction_id: transaction_id) ||
        Billing::BillingTransaction.new(
          user_id: billable_entity.id, customer_id: plan_subscription.customer_id, transaction_id: transaction_id
        )
      end

      billing_transaction.plan_subscription = plan_subscription
      billing_transaction.amount_in_cents = zuora_transaction.amount_in_cents
      billing_transaction.created_at = zuora_transaction.created_date.in_billing_timezone
      billing_transaction.service_ends_at = service_ends_at.in_billing_timezone
      billing_transaction.platform = :zuora
      billing_transaction.platform_transaction_id = zuora_transaction.id
      billing_transaction.seats_delta = seats_delta
      billing_transaction.asset_packs_delta = asset_packs_delta

      zuora_transaction.decorate_billing_transaction(billing_transaction)

      # PAIR NOTES: Logging starts here for recurring transactions
      # Saves billing_transaction
      billing_transaction.log_recurring_charge(
        billable_entity: billable_entity,
        invoiced_items: zuora_transaction.invoice_items,
        charge_type: charge_type,
      )

      GitHub.dogstats.count("cream", billing_transaction.amount_in_cents)

      billing_transaction
    end
  end

  sig { returns(ChargeTypeResolver) }
  def charge_type_resolver
    @charge_type_resolver ||= T.let(ChargeTypeResolver.new(
      payment: T.must(zuora_transaction),
      recurring_amount: plan_subscription.payment_amount,
    ), T.nilable(ChargeTypeResolver))
  end

  sig { returns(Billing::PlanSubscription) }
  attr_reader :plan_subscription
  sig { returns(Time) }
  attr_reader :service_ends_at
  sig { returns(T.nilable(T.any(Billing::Zuora::Payment, Billing::Zuora::CreditBalanceAdjustment))) }
  attr_reader :zuora_transaction
end
