# typed: strict
# frozen_string_literal: true

# Reconciles all non-zero balance invoices for a customer. Specifically, for each invoice it will:
#
#   - Zero out positive invoice items that we no longer want to charge the customer for (e.g. cancelled items)
#   - Zero out negative invoice items that are not eligible for credit (e.g. customer didn't actually pay)
#
# Once invoice reconciliation is complete and if applicable, all remaining negative balance
# invoices are transferred to the customer's credit balance and applied to open invoices.
class Billing::Zuora::ReconcileInvoicesJob < ApplicationJob
  include GitHub::Billing::ZuoraRateLimitHandler
  include GitHub::Memoizer

  queue_as :billing

  retry_on_dirty_exit

  # We need many retries because back-to-back plan subscription changes (for sponsors and general purpose)
  # can enqueue this job in quick succession, causing lock contention.
  retry_on GitHub::Restraint::UnableToLock,
    attempts: 8,
    wait: :polynomially_longer

  Billing::Zuora::RETRYABLE_ERRORS.each do |error|
    retry_on(error, wait: :polynomially_longer) do |_job, error|
      Failbot.report(error)
    end
  end

  rescue_from(Zuorest::TooManyRequestsError) do |error|
    T.bind(self, Billing::Zuora::ReconcileInvoicesJob)

    zuora_rate_limit_handler(self, error)
  end

  sig { params(invoice_ids: T::Array[String]).void }
  def self.mark_invoices_pending(invoice_ids)
    invoice_ids.each do |invoice_id|
      Billing::Kv.store.set(reconcile_pending_key(invoice_id), "1", expires: 2.hours.from_now)
    end
  end

  sig { params(invoice_id: String).returns(T::Boolean) }
  def self.invoice_pending?(invoice_id)
    Billing::Kv.store.exists(reconcile_pending_key(invoice_id)).value { false }
  end

  sig { params(invoice_ids: T::Array[String]).void }
  def self.clear_invoices_pending(invoice_ids)
    invoice_ids.each { |invoice_id| Billing::Kv.store.del(reconcile_pending_key(invoice_id)) }
  end

  sig { params(invoice_id: String).returns(String) }
  def self.reconcile_pending_key(invoice_id)
    "billing.reconcile_invoices.pending.#{invoice_id}"
  end
  private_class_method :reconcile_pending_key

  sig { params(customer_id: Integer, create_credit_balance: T::Boolean).void }
  def perform(customer_id:, create_credit_balance: true)
    @customer = T.let(::Customer.find(customer_id), T.nilable(::Customer))
    @create_credit_balance = T.let(create_credit_balance, T.nilable(T::Boolean))

    return if customer.zuora_account_id.blank?
    return if customer.billable_owner.nil?
    return if non_zero_invoices.empty?

    locks = T.let([], T::Array[GitHub::Restraint::Lock])
    begin
      non_zero_invoices.each { |invoice| locks << lock_invoice(invoice.id) }

      non_zero_invoices.each do |invoice|
        record_metrics(invoice)
        adjust_invoice(invoice)
      end

      if @create_credit_balance
        transfer_remaining_negative_balances
        apply_credit_balance_to_open_invoices if should_apply_credit_balance?
      end
      update_account

      with_write { self.class.clear_invoices_pending(non_zero_invoices.map(&:id)) }
    ensure
      locks.each(&:release!)
    end
  end

  private

  sig { returns(::Customer) }
  def customer
    T.must(@customer)
  end

  sig { returns(Billing::Types::Account) }
  memoize def billable_entity
    T.must(customer.billable_owner)
  end

  sig { returns(T::Array[Billing::Zuora::Invoice]) }
  memoize def non_zero_invoices
    ::Billing::Zuora::Invoice.non_zero_invoices_for_account(
      customer.zuora_account_id,
      prefetch_fields: ["Balance"],
    )
  end

  sig { params(invoice_id: String).returns(GitHub::Restraint::Lock) }
  def lock_invoice(invoice_id)
    lock = restraint.obtain_lock(::Billing::Zuora::Invoice.lock_key(invoice_id), _n = 1, _ttl = 3.minutes)
    raise GitHub::Restraint::UnableToLock, "Unable to obtain lock" unless lock
    lock
  end

  sig { returns(GitHub::Restraint) }
  memoize def restraint
    GitHub::Restraint.new
  end

  sig { returns(String) }
  memoize def dogstats_class_tag
    self.class.name.to_s.underscore
  end

  sig { params(invoice: ::Billing::Zuora::Invoice).void }
  def record_metrics(invoice)
    ::Billing::Zuora::Invoice.record_metrics(
      balance_in_cents: invoice.balance * 100,
      calling_class: dogstats_class_tag,
    )
    GitHub.logger.info(
      "code.namespace" => self.class.name,
      "code.function" => "record_metrics",
      "gh.billing.zuora.invoice.amount" => invoice.amount,
      "gh.billing.zuora.invoice.balance" => invoice.balance,
      "gh.billing.zuora.invoice.id" => invoice.id,
      "gh.billing.zuora.invoice.number" => invoice.number,
      "gh.billing.billable_entity.id" => billable_entity.id,
      "gh.billing.billable_entity.type" => billable_entity.class.name,
      "gh.user.dunning" => billable_entity.dunning?,
    )
  end

  # Iterates through all invoice items on the provided invoice and
  # zeroes out items according to should_zero_out_invoice_item?
  sig { params(invoice: ::Billing::Zuora::Invoice).void }
  def adjust_invoice(invoice)
    items_to_zero_out = invoice.invoice_items.select { |item| should_zero_out_invoice_item?(item, is_negative_invoice: invoice.balance.negative?) }
    return if items_to_zero_out.empty?

    adjustments = build_invoice_item_adjustments_for(invoice, items: items_to_zero_out)
    return if adjustments.empty?

    result = ::Billing::Zuora::Invoice.create_invoice_item_adjustments(adjustments)
    instrument_adjust_invoice(invoice, adjustments, result)
  end

  # Whether or not the provided invoice item should be zeroed out in order of priority:
  #  1. Skip usage and zero-amount items.
  #  2. Items already paid via an advance payment always zero out.
  #  3. Negative items on a negative invoice: preserve only if a paid service
  #     period overlaps. Otherwise zero out so stale leftovers don't become credit.
  #  4. Otherwise: zero out when the rate plan charge is no longer active.
  sig { params(item: ::Billing::Zuora::InvoiceItem, is_negative_invoice: T::Boolean).returns(T::Boolean) }
  def should_zero_out_invoice_item?(item, is_negative_invoice: false)
    return false if item.charge_amount.zero? || item.charge_type == "Usage"
    return true if has_advance_payment?(item)

    if is_negative_invoice && item.charge_amount.negative?
      return !eligible_for_credit?(item)
    end

    zuora_rate_plan_charges[item.product_rate_plan_charge_id].blank?
  end

  sig { params(item: ::Billing::Zuora::InvoiceItem).returns(T::Boolean) }
  def has_advance_payment?(item)
    advance_payment_service_periods = advance_payment_service_periods_by_product_rate_plan_charge_id[item.product_rate_plan_charge_id]
    return false if advance_payment_service_periods.blank?

    item_service_period = service_period_for_invoice_item(item)
    return false unless item_service_period

    advance_payment_service_periods.any? { |period| period.overlap?(item_service_period) }
  end

  sig { returns(T::Hash[String, T::Array[T::Range[Date]]]) }
  memoize def advance_payment_service_periods_by_product_rate_plan_charge_id
    service_periods = T.let({}, T::Hash[String, T::Array[T::Range[Date]]])
    ::Billing::AdvancePayment.collected_payments(customer: customer).each do |collected_payment|
      collected_payment.invoice_items.each do |item|
        next if item.product_rate_plan_charge_id.blank?

        service_period = service_period_for_invoice_item(item)
        (service_periods[item.product_rate_plan_charge_id] ||= []) << service_period if service_period
      end
    end
    service_periods
  end

  sig { params(item: ::Billing::Zuora::InvoiceItem).returns(T.nilable(T::Range[Date])) }
  def service_period_for_invoice_item(item)
    start_str = item.service_start_date
    end_str = item.service_end_date
    return nil if start_str.blank? || end_str.blank?

    Date.iso8601(start_str)..Date.iso8601(end_str)
  rescue ArgumentError
    nil
  end

  sig { params(item: ::Billing::Zuora::InvoiceItem).returns(T::Boolean) }
  def eligible_for_credit?(item)
    paid_periods = paid_service_periods_by_product_rate_plan_charge_id[item.product_rate_plan_charge_id]
    return false if paid_periods.blank?

    item_service_period = service_period_for_invoice_item(item)
    return false unless item_service_period

    paid_periods.any? { |paid_period| paid_period.overlap?(item_service_period) }
  end

  sig { returns(T::Hash[String, T::Array[T::Range[Date]]]) }
  memoize def paid_service_periods_by_product_rate_plan_charge_id
    # Fetch all billing transactions in the past year to ensure payments for annual subscriptions are included.
    # The `service_ends_at` field is not used here because at the time of writing, it is populated using
    # Billing::Zuora::Subscription.charged_through_date which is not always accurate or representative
    # of the actual dates for individual line items.
    billing_transaction_ids = ::Billing::BillingTransaction.successful_payment_collection(billable_entity)
      .where(created_at: 1.year.ago..)
      .pluck(:id)
    return {} if billing_transaction_ids.empty?

    # Get all the product rate plan charge IDs and service dates for things that are considered paid up today.
    paid_periods_by_prpc_id = T.let({}, T::Hash[String, T::Array[T::Range[Date]]])
    ::Billing::BillingTransaction::LineItem
      .where(billing_transaction_id: billing_transaction_ids)
      .where("amount_in_cents > 0")
      .pluck(:zuora_product_rate_plan_charge_id, :service_start_date, :service_end_date)
      .each do |prpc_id, start_date, end_date|
        next if prpc_id.blank? || start_date.blank? || end_date.blank?
        (paid_periods_by_prpc_id[prpc_id] ||= []) << (start_date.to_date..end_date.to_date)
      end

    # Exclude any product rate plan charge IDs that are part of open invoices.
    #
    # This is needed because the product rate plan charge ids resolved from our billing transactions
    # are not guaranteed to be paid up and eligible for a credit balance transfer.
    #
    # For example, if a product is paid for but forcefully removed before the service end date,
    # then subsequently added again before the same service end date, then the product is not
    # considered paid up and therefore should not be eligible for a credit balance transfer.
    excluded = paid_periods_by_prpc_id.keys.to_set & product_rate_plan_charge_ids_for_open_invoices
    if excluded.any?
      GitHub.dogstats.increment("billing.reconcile_invoices_job.paid_service_periods_excluded_by_open_invoices")
      GitHub.logger.info(
        logger_fields.merge({
          "code.function" => __method__,
          "gh.billing.billing_transactions.product_rate_plan_charge_ids" => paid_periods_by_prpc_id.keys.join(", "),
          "gh.billing.zuora.open_invoices.product_rate_plan_charge_ids" => product_rate_plan_charge_ids_for_open_invoices.to_a.join(", "),
          "gh.billing.excluded_product_rate_plan_charge_ids" => excluded.to_a.join(", "),
        })
      )
      excluded.each { |prpc_id| paid_periods_by_prpc_id.delete(prpc_id) }
    end

    paid_periods_by_prpc_id
  end

  sig { returns(T::Set[String]) }
  memoize def product_rate_plan_charge_ids_for_open_invoices
    open_invoices = non_zero_invoices.select { |invoice| invoice.balance.positive? }
    invoice_items = open_invoices.flat_map(&:invoice_items)
    invoice_items.filter_map { |item| item.product_rate_plan_charge_id if item.charge_amount.positive? }.to_set
  end

  # Returns the active rate plan charges for all of the billable entity's plan subscriptions.
  # This is used to determine whether or not a rate plan charge is cancelled.
  sig { returns(T::Hash[String, ::Billing::Zuora::RatePlanCharge]) }
  memoize def zuora_rate_plan_charges
    customer.plan_subscriptions.each_with_object({}) { |ps, h| h.merge!(ps.zuora_rate_plan_charges) }
  end

  sig do
    params(
      invoice: ::Billing::Zuora::Invoice,
      items: T::Array[::Billing::Zuora::InvoiceItem],
    ).returns(T::Array[T::Hash[Symbol, T.untyped]])
  end
  def build_invoice_item_adjustments_for(invoice, items:)
    remaining_balance = ::Billing::Money.parse(invoice.balance)
    invoice_item_adjustments = []
    existing_adjustments_by_item = ::Billing::Zuora::InvoiceItemAdjustmentBuilder.existing_adjustments_by_item(invoice)

    sorted_items = if remaining_balance.negative?
      items.sort_by(&:amount)
    else
      items.sort_by { |item| -item.amount }
    end

    sorted_items.each do |invoice_item|
      break if remaining_balance.zero?

      items_to_zero_out = [invoice_item] + invoice_item.taxation_items.select { |item| !item.tax_amount.zero? }
      items_to_zero_out.each do |item|
        break if remaining_balance.zero?

        # Reduce the item's adjustable amount by any existing adjustments.
        # Existing adjustments have the opposite sign of the item amount they were applied to.
        max_item_adjustment = item.amount + existing_adjustments_by_item.fetch(item.id, ::Billing::Money.new(0))
        next if max_item_adjustment.zero?

        adjustment_amount = [max_item_adjustment.abs, remaining_balance.abs].min
        adjustment_amount *= -1 if max_item_adjustment.negative?
        remaining_balance -= adjustment_amount

        invoice_item_adjustments << ::Billing::Zuora::InvoiceItemAdjustmentBuilder.adjustment_for(
          amount: -adjustment_amount.dollars,
          invoice_id: invoice.id,
          item_id: item.id,
          is_tax_item: item.is_a?(::Billing::Zuora::TaxationItem),
        )
      end
    end

    invoice_item_adjustments
  end

  sig do
    params(
      invoice: ::Billing::Zuora::Invoice,
      adjustments: T::Array[T::Hash[Symbol, T.untyped]],
      result: GitHub::Billing::Result,
    ).void
  end
  def instrument_adjust_invoice(invoice, adjustments, result)
    GitHub.dogstats.increment("billing.reconcile_invoices_job.adjust_invoice",
      tags: ["success:#{result.success?}"])

    GitHub.logger.info(
      logger_fields(result).merge({
        "code.function" => "adjust_invoice",
        "gh.billing.zuora.invoice.id" => invoice.id,
        "gh.billing.zuora.invoice.balance" => invoice.balance,
        "gh.billing.zuora.invoice_item_adjustments.inspect" => adjustments.inspect,
      })
    )
  end

  sig { void }
  def transfer_remaining_negative_balances
    negative_invoices = ::Billing::Zuora::Invoice.non_zero_invoices_for_account(
      customer.zuora_account_id,
      balance: :negative,
      prefetch_fields: ["Balance"],
    )
    negative_invoices.each do |invoice|
      next unless should_create_credit_balance?(invoice)
      create_credit_balance(invoice)
    end
  end

  sig { params(invoice: ::Billing::Zuora::Invoice).returns(T::Boolean) }
  def should_create_credit_balance?(invoice)
    return false unless invoice.balance.negative?

    # Skip credit balance creation if there is a recent refund on the account
    # Most refunds are created manually by GitHub staff members and they will manually adjust invoice balances as needed.
    # Creating a credit balance in this case only adds friction to the process since they will need to undo it.
    if ::Billing::BillingTransaction.recent_refunded_transaction(billable_entity).present?
      GitHub.dogstats.increment("billing.reconcile_invoices_job.skip_create_credit_balance")
      GitHub.logger.info(logger_fields(nil).merge({ "code.function" => "should_create_credit_balance" }))
      return false
    end

    true
  end

  sig { params(invoice: ::Billing::Zuora::Invoice).returns(GitHub::Billing::Result) }
  def create_credit_balance(invoice)
    amount = invoice.balance.abs
    response = GitHub.zuorest_client.create_credit_balance_adjustment({
      Type: "Increase",
      Amount: amount,
      Comment: "GitHub - transfer #{amount} to account balance",
      SourceTransactionId: invoice.id,
    })
    result = GitHub::Billing::Result.from_zuora(response)
    instrument_create_credit_balance(invoice, to_cents(amount), result)
    result
  end

  sig do
    params(
      invoice: ::Billing::Zuora::Invoice,
      amount_in_cents: T.nilable(Integer),
      result: T.nilable(GitHub::Billing::Result),
    ).void
  end
  def instrument_create_credit_balance(invoice, amount_in_cents, result)
    GitHub.dogstats.count("billing.reconcile_invoices_job.create_credit_balance",
      amount_in_cents, tags: ["success:#{result&.success?}"])

    GitHub.logger.info(
      logger_fields(result).merge({
        "code.function" => "create_credit_balance",
        "gh.billing.credit_amount_in_cents" => amount_in_cents,
        "gh.billing.zuora.invoice.id" => invoice.id,
      })
    )
  end

  sig { returns(T::Boolean) }
  def should_apply_credit_balance?
    return true if billable_entity.feature_flag_enabled?(:billing_transfer_credit_balance_to_open_invoices_for_all_accounts, default: false)
    billable_entity.autopay_disabled_by_india_rbi?
  end

  sig { returns(GitHub::Billing::Result) }
  def apply_credit_balance_to_open_invoices
    initial_credit_balance = billable_entity.zuora_account[:metrics][:creditBalance]
    return GitHub::Billing::Result.success unless initial_credit_balance.positive?

    open_invoices = ::Billing::Zuora::Invoice.open_invoices_for_account(
      customer.zuora_account_id,
      posted_only: true,
      prefetch_fields: ["Balance"],
    )

    remaining_credit_balance = initial_credit_balance
    results = T.let([], T::Array[GitHub::Billing::Result])
    open_invoices.each do |invoice|
      break if remaining_credit_balance <= 0

      amount = remaining_credit_balance >= invoice.balance ? invoice.balance : remaining_credit_balance
      remaining_credit_balance -= amount
      response = GitHub.zuorest_client.create_credit_balance_adjustment({
        Type: "Decrease",
        Amount: amount,
        Comment: "GitHub - transfer #{amount} to invoice balance",
        SourceTransactionId: invoice.id,
      })
      results << GitHub::Billing::Result.from_zuora(response)
    end

    result = GitHub::Billing::Result.from_results(results)
    instrument_apply_credit_balance(open_invoices, to_cents(initial_credit_balance), to_cents(remaining_credit_balance), result)
    result
  end

  sig do
    params(
      open_invoices: T::Array[::Billing::Zuora::Invoice],
      initial_credit_balance_in_cents: Integer,
      remaining_credit_balance_in_cents: Integer,
      result: T.nilable(GitHub::Billing::Result),
    ).void
  end
  def instrument_apply_credit_balance(open_invoices, initial_credit_balance_in_cents, remaining_credit_balance_in_cents, result)
    applied_credit_balance_in_cents = initial_credit_balance_in_cents - remaining_credit_balance_in_cents
    GitHub.dogstats.count("billing.reconcile_invoices_job.apply_credit_balance",
      applied_credit_balance_in_cents, tags: ["success:#{result&.success?}"])

    GitHub.logger.info(
      logger_fields(result).merge({
        "code.function" => "apply_credit_balance",
        "gh.billing.zuora.open_invoices.balances" => open_invoices.map(&:balance),
        "gh.billing.zuora.open_invoices.ids" => open_invoices.map(&:id),
        "gh.billing.zuora.initial_credit_balance_in_cents" => initial_credit_balance_in_cents,
        "gh.billing.zuora.applied_credit_balance_in_cents" => applied_credit_balance_in_cents,
        "gh.billing.zuora.remaining_credit_balance_in_cents" => remaining_credit_balance_in_cents,
      })
    )
  end

  sig { void }
  def update_account
    plan_subscription = billable_entity.plan_subscription
    return unless plan_subscription.present?

    with_write { plan_subscription.update_balance_from_zuora(origin: T.must(self.class.name)) }

    # For users and organizations that have reached the end of dunning and do not owe us anything, we reset billing on
    # their account to ensure they can continue to use all features included with the free plan without intervention.
    # Businesses are excluded because they do not have a valid free plan.
    if billable_entity.is_a?(User) && T.cast(billable_entity, User).can_reset_billing?(has_balance: plan_subscription.balance_in_cents.positive?)
      with_write { T.cast(billable_entity, User).reset_billing }
    end
  end

  sig { params(result: T.nilable(GitHub::Billing::Result)).returns(T::Hash[String, T.untyped]) }
  def logger_fields(result = nil)
    fields = T.let({
      "code.namespace" => self.class.name,
      "gh.catalog_service" => "github/payment_processing",
      "gh.billing.billable_entity.billed_on" => billable_entity.billed_on,
      "gh.billing.billable_entity.billing_attempts" => billable_entity.billing_attempts,
      "gh.billing.billable_entity.external_subscription" => billable_entity.external_subscription?,
      "gh.billing.billable_entity.disabled" => billable_entity.disabled?,
      "gh.billing.billable_entity.id" => billable_entity.id,
      "gh.billing.billable_entity.login" => billable_entity.display_login,
      "gh.billing.billable_entity.type" => billable_entity.class.name,
      "gh.billing.customer.id" => customer.id,
      "gh.billing.customer.disabled_reasons" => customer.disabled_reasons&.join(","),
      "gh.billing.customer.requires_manual_transactions" => customer.requires_manual_transactions?,
      "gh.billing.customer.zuora_account_id" => customer.zuora_account_id,
      "gh.billing.result.inspect" => result.inspect,
      "gh.billing.result.success" => result&.success?,
    }, T::Hash[String, T.untyped])

    fields
  end

  sig { params(amount: Float).returns(Integer) }
  def to_cents(amount)
    (amount * 100).round
  end
end
