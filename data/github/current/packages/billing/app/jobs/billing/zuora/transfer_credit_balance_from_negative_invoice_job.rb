# typed: strict
# frozen_string_literal: true

class Billing::Zuora::TransferCreditBalanceFromNegativeInvoiceJob < ApplicationJob
  include GitHub::Billing::ZuoraRateLimitHandler
  include GitHub::Memoizer

  queue_as :billing

  retry_on_dirty_exit
  retry_on GitHub::Restraint::UnableToLock,
    attempts: 3,
    wait: :polynomially_longer

  T.unsafe(self).retry_on(*::Billing::Zuora::RETRYABLE_ERRORS)

  rescue_from(Zuorest::TooManyRequestsError) do |error|
    T.bind(self, Billing::Zuora::TransferCreditBalanceFromNegativeInvoiceJob)

    zuora_rate_limit_handler(self, error)
  end

  # Public: Transfer a refundable invoice's items from a negative balance invoice to the Zuora account's credit balance.
  #
  # invoice_id - The Zuora ID of the invoice (e.g. 8ad09b7d83132604018314a3f44660d5)
  # billable_entity - User/Org/Business the invoice belongs to
  # product_rate_plan_charge_ids - Additional product rate plan charge ids that are eligible for a credit balance transfer.
  #                                Used to mark cancelled products as eligible for a credit.
  # force - When true, the job will run even if the invoice balance is not negative.
  sig do
    params(
      invoice_id: String,
      billable_entity: Billing::Types::Account,
      product_rate_plan_charge_ids: T::Array[String],
      force: T::Boolean,
    ).void
  end
  def perform(invoice_id:, billable_entity:, product_rate_plan_charge_ids: [], force: false)
    @invoice_id = T.let(invoice_id, T.nilable(String))
    @billable_entity = T.let(billable_entity, T.nilable(Billing::Types::Account))
    @product_rate_plan_charge_ids = T.let(product_rate_plan_charge_ids, T.nilable(T::Array[String]))
    @_zuora_invoice = T.let(nil, T.nilable(Billing::Zuora::Invoice))
    @_open_invoices = T.let(nil, T.nilable(T::Array[Billing::Zuora::Invoice]))

    record_metrics

    if zuora_invoice.balance.negative? || force
      transfer_credit_balance
    end
  end

  private

  sig { params(refresh: T::Boolean).returns(Billing::Zuora::Invoice) }
  def zuora_invoice(refresh: false)
    return @_zuora_invoice if @_zuora_invoice.present? && !refresh
    @_zuora_invoice = ::Billing::Zuora::Invoice.new(T.must(@invoice_id))
  end

  sig { returns(String) }
  memoize def dogstats_class_tag
    self.class.name.to_s.underscore
  end

  sig { void }
  def record_metrics
    Billing::Zuora::Invoice.record_metrics(
      balance_in_cents: zuora_invoice.balance * 100,
      calling_class: dogstats_class_tag,
    )
    if zuora_invoice.balance.negative?
      GitHub.logger.info(
        "Negative invoice metrics recorded",
        "code.namespace" => self.class.name,
        "code.function" => "record_metrics",
        "gh.billing.zuora.invoice.amount" => zuora_invoice.amount,
        "gh.billing.zuora.invoice.balance" => zuora_invoice.balance,
        "gh.billing.zuora.invoice.id" => zuora_invoice.id,
        "gh.billing.zuora.invoice.number" => zuora_invoice.number,
        "gh.billing.billable_entity.id" => @billable_entity&.id,
        "gh.billing.billable_entity.type" => @billable_entity.class.name,
        "gh.user.dunning" => @billable_entity&.dunning?,
      )
    end
  end

  sig { void }
  def transfer_credit_balance
    locks = open_invoices.map { |invoice| lock_invoice(invoice.id) }.push(lock_invoice(zuora_invoice.id))
    zero_out_eligible_invoice_items_on_open_invoices
    zero_out_eligible_invoice_items_on_negative_invoice
    if should_create_credit_balance?
      create_credit_balance
      apply_credit_balance_to_open_invoices if should_apply_credit_balance?
    end
    update_account
  ensure
    locks&.each(&:release!)
  end

  sig { params(invoice_id: String).returns(GitHub::Restraint::Lock) }
  def lock_invoice(invoice_id)
    lock = restraint.obtain_lock(Billing::Zuora::Invoice.lock_key(invoice_id), _n = 1, _ttl = 1.minute)
    raise GitHub::Restraint::UnableToLock, "Unable to obtain lock" unless lock
    lock
  end

  sig { returns(GitHub::Restraint) }
  memoize def restraint
    GitHub::Restraint.new
  end

  sig { returns(GitHub::Billing::Result) }
  def zero_out_eligible_invoice_items_on_open_invoices
    adjustments = open_invoices.flat_map { |invoice| build_invoice_item_adjustments_for(invoice) }
    return GitHub::Billing::Result.success if adjustments.empty?
    result = create_invoice_item_adjustments(adjustments)
    instrument_zero_out_invoice_items(__method__, open_invoices, adjustments, result)
    result
  end

  sig { returns(GitHub::Billing::Result) }
  def zero_out_eligible_invoice_items_on_negative_invoice
    adjustments = build_invoice_item_adjustments_for(zuora_invoice)
    return GitHub::Billing::Result.success if adjustments.empty?
    result = create_invoice_item_adjustments(adjustments)
    instrument_zero_out_invoice_items(__method__, [zuora_invoice], adjustments, result)
    result
  end

  sig { params(invoice: Billing::Zuora::Invoice).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def build_invoice_item_adjustments_for(invoice)
    remaining_balance = Billing::Money.parse(invoice.balance)
    is_negative_invoice = remaining_balance.negative?
    invoice_item_adjustments = []

    invoice.invoice_items.each do |invoice_item|
      break if remaining_balance.zero?
      next unless should_zero_out_invoice_item?(invoice_item, is_negative_invoice: is_negative_invoice)

      items_to_zero_out = [invoice_item] + invoice_item.taxation_items.select { |item| !item.tax_amount.zero? }
      items_to_zero_out.each do |item|
        adjustment_amount = [item.amount.abs, remaining_balance.abs].min
        adjustment_amount *= -1 if item.amount.negative?
        remaining_balance -= adjustment_amount

        invoice_item_adjustments << Billing::Zuora::InvoiceItemAdjustmentBuilder.adjustment_for(
          amount: -adjustment_amount.dollars,
          invoice_id: invoice.id,
          item_id: item.id,
          is_tax_item: item.is_a?(Billing::Zuora::TaxationItem),
        )
      end
    end

    invoice_item_adjustments
  end

  # Whether or not the provided invoice item should be zeroed out.
  #
  # The key considerations (in order of priority) are:
  #  1. We should not zero out negative invoice items that the customer has paid for
  #  2. We should not zero out usage charges
  #  3. We should zero out invoice items that are cancelled
  #
  sig { params(item: Billing::Zuora::InvoiceItem, is_negative_invoice: T::Boolean).returns(T::Boolean) }
  def should_zero_out_invoice_item?(item, is_negative_invoice: false)
    return false if item.charge_amount.zero? || item.charge_type == "Usage"
    is_eligible_for_credit = is_negative_invoice && item.charge_amount.negative? &&
      @product_rate_plan_charge_ids&.include?(item.product_rate_plan_charge_id) &&
      !product_rate_plan_charge_ids_for_open_invoices.include?(item.product_rate_plan_charge_id)
    is_cancelled = zuora_rate_plan_charges[item.product_rate_plan_charge_id].blank?
    is_eligible_for_credit ? false : is_cancelled
  end

  # Returns the active rate plan charges for all of the billable entity's plan subscriptions.
  # This is used to determine whether or not a rate plan charge is cancelled.
  sig { returns(T::Hash[String, Billing::Zuora::RatePlanCharge]) }
  memoize def zuora_rate_plan_charges
    return {} unless @billable_entity.present?
    @billable_entity.plan_subscriptions.each_with_object({}) { |ps, h| h.merge!(ps.zuora_rate_plan_charges) }
  end

  # Returns a list of product rate plan charge ids for positive charges on all open invoices.
  # This is needed because the product rate plan charge ids provided in @product_rate_plan_charge_ids
  # are not guaranteed to be paid up and eligible for a credit balance transfer.
  sig { returns(T::Set[String]) }
  memoize def product_rate_plan_charge_ids_for_open_invoices
    open_invoices.flat_map do |invoice|
      invoice.invoice_items.map do |item|
        item.product_rate_plan_charge_id if item.charge_amount.positive?
      end
    end.compact.to_set
  end

  # Creates the invoice item adjustments in Zuora
  sig { params(adjustments: T::Array[T.untyped]).returns(GitHub::Billing::Result) }
  def create_invoice_item_adjustments(adjustments)
    response = GitHub.zuorest_client.create_action(objects: adjustments, type: "InvoiceItemAdjustment")
    results = response.map { |r| GitHub::Billing::Result.from_zuora(r) }
    result = GitHub::Billing::Result.from_results(results)
    result.batch_zuora_results = response
    result
  end

  sig do
    params(
      code_function: T::nilable(Symbol),
      invoices: T::Array[Billing::Zuora::Invoice],
      adjustments: T::nilable(T::Array[T::Hash[Symbol, T.untyped]]),
      result: T::nilable(GitHub::Billing::Result),
    ).void
  end
  def instrument_zero_out_invoice_items(code_function, invoices, adjustments, result)
    GitHub.dogstats.increment("billing.transfer_credit_balance_from_negative_invoice_job.zero_out_eligible_invoice_items",
      tags: ["success:#{result&.success?}"])

    GitHub.logger.info(
      logger_fields(result).merge({
        "code.function" => code_function,
        "gh.billing.zuora.invoices.balances" => invoices.map(&:balance),
        "gh.billing.zuora.invoices.ids" => invoices.map(&:id),
        "gh.billing.zuora.invoice_item_adjustments.inspect" => adjustments.inspect,
      })
    )
  end

  sig { returns(T::Boolean) }
  def should_create_credit_balance?
    return false unless zuora_invoice(refresh: true).balance.negative?

    # Skip credit balance creation if there is a recent refund on the account
    # Most refunds are created manually by GitHub staff members and they will manually adjust invoice balances as needed.
    # Creating a credit balance in this case only adds friction to the process since they will need to undo it.
    if @billable_entity.present? && Billing::BillingTransaction.recent_refunded_transaction(@billable_entity).present?
      GitHub.dogstats.increment("billing.transfer_credit_balance_from_negative_invoice_job.skip_create_credit_balance")
      GitHub.logger.info(logger_fields(nil).merge({ "code.function" => "should_create_credit_balance" }))
      return false
    end

    true
  end

  # Transfers the remaining negative invoice balance to the account's credit balance
  sig { returns(GitHub::Billing::Result) }
  def create_credit_balance
    amount = zuora_invoice.balance.abs
    response = GitHub.zuorest_client.create_credit_balance_adjustment({
      Type: "Increase",
      Amount: amount,
      Comment: "GitHub - transfer #{amount} to account balance",
      SourceTransactionId: zuora_invoice.id,
    })
    result = GitHub::Billing::Result.from_zuora(response)
    instrument_create_credit_balance(to_cents(amount), result)
    result
  end

  sig { params(amount_in_cents: T::nilable(Integer), result: T::nilable(GitHub::Billing::Result)).void }
  def instrument_create_credit_balance(amount_in_cents, result)
    GitHub.dogstats.count("billing.transfer_credit_balance_from_negative_invoice_job.create_credit_balance",
      amount_in_cents, tags: ["success:#{result&.success?}"])

    GitHub.logger.info(
      logger_fields(result).merge({
        "code.function" => "create_credit_balance",
        "gh.billing.credit_amount_in_cents" => amount_in_cents,
        "gh.billing.zuora.invoice.id" => zuora_invoice.id,
      })
    )
  end

  # Whether or not we should apply credit balance on the account to open invoices
  sig { returns(T::Boolean) }
  def should_apply_credit_balance?
    return false unless @billable_entity.present?
    return @billable_entity.autopay_disabled_by_india_rbi? if @billable_entity.feature_flag_enabled?(:billing_transfer_credit_balance_to_open_invoices_for_all_rbi_accounts, default: false)
    return true if @billable_entity.feature_flag_enabled?(:billing_transfer_credit_balance_to_open_invoices_for_all_accounts, default: false)
    return false unless @billable_entity.is_a?(Business)
    return false unless @billable_entity.trial?
    @billable_entity.autopay_disabled_by_india_rbi?
  end

  # Applies the entire credit balance on the account to all open invoices
  sig { returns(GitHub::Billing::Result) }
  def apply_credit_balance_to_open_invoices
    initial_credit_balance = @billable_entity&.zuora_account[:metrics][:creditBalance]
    return GitHub::Billing::Result.success unless initial_credit_balance.positive?

    remaining_credit_balance = initial_credit_balance
    results = open_invoices(refresh: true).map do |invoice|
      break if remaining_credit_balance <= 0

      amount = remaining_credit_balance >= invoice.balance ? invoice.balance : remaining_credit_balance
      remaining_credit_balance -= amount
      response = GitHub.zuorest_client.create_credit_balance_adjustment({
        Type: "Decrease",
        Amount: amount,
        Comment: "GitHub - transfer #{amount} to invoice balance",
        SourceTransactionId: invoice.id,
      })
      GitHub::Billing::Result.from_zuora(response)
    end || []

    result = GitHub::Billing::Result.from_results(results)
    instrument_apply_credit_balance(to_cents(initial_credit_balance), to_cents(remaining_credit_balance), result)
    result
  end

  # Returns an array of open invoices for the account
  sig { params(refresh: T::Boolean).returns(T::Array[Billing::Zuora::Invoice]) }
  def open_invoices(refresh: false)
    return @_open_invoices if !@_open_invoices.nil? && !refresh

    zuora_account_id = @billable_entity&.customer&.zuora_account_id
    return @_open_invoices = [] unless zuora_account_id

    @_open_invoices = Billing::Zuora::Invoice.open_invoices_for_account(zuora_account_id, posted_only: true, prefetch_fields: ["Balance"])
  end

  sig do
    params(
      initial_credit_balance_in_cents: Integer,
      remaining_credit_balance_in_cents: Integer,
      result: T::nilable(GitHub::Billing::Result),
    ).void
  end
  def instrument_apply_credit_balance(initial_credit_balance_in_cents, remaining_credit_balance_in_cents, result)
    applied_credit_balance_in_cents = initial_credit_balance_in_cents - remaining_credit_balance_in_cents
    GitHub.dogstats.count("billing.transfer_credit_balance_from_negative_invoice_job.apply_credit_balance",
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
    return unless @billable_entity.present?

    plan_subscription = @billable_entity.plan_subscription
    return unless plan_subscription.present?

    with_write { plan_subscription.update_balance_from_zuora(origin: self.class.name) }

    # For users and organizations that have reached the end of dunning and do not owe us anything, we reset billing on
    # their account to ensure they can continue to use all features included with the free plan without intervention.
    # Businesses are excluded because they do not have a valid free plan.
    if @billable_entity.is_a?(User) && @billable_entity.can_reset_billing?(has_balance: plan_subscription.balance_in_cents.positive?)
      with_write { @billable_entity.reset_billing }
    end
  end

  sig { params(result: T::nilable(GitHub::Billing::Result)).returns(T::Hash[String, T.untyped]) }
  def logger_fields(result = nil)
    fields = {
      "code.namespace" => self.class.name,
      "gh.catalog_service" => "github/payment_processing",
      "gh.billing.billable_entity.billed_on" => @billable_entity&.billed_on,
      "gh.billing.billable_entity.billing_attempts" => @billable_entity&.billing_attempts,
      "gh.billing.billable_entity.external_subscription" => @billable_entity&.external_subscription?,
      "gh.billing.billable_entity.disabled" => @billable_entity&.disabled?,
      "gh.billing.billable_entity.id" => @billable_entity&.id,
      "gh.billing.billable_entity.login" => @billable_entity&.display_login,
      "gh.billing.billable_entity.type" => @billable_entity.class.name,
      "gh.billing.result.inspect" => result.inspect,
      "gh.billing.result.success" => result&.success?,
    }

    if customer = @billable_entity&.customer
      fields.merge!({
        "gh.billing.customer.disabled_reasons": customer.disabled_reasons&.join(","),
        "gh.billing.customer.id": customer.id,
        "gh.billing.customer.requires_manual_transactions": customer.requires_manual_transactions?,
        "gh.billing.customer.zuora_account_id": customer.zuora_account_id,
      })
    end

    fields
  end

  sig { params(amount: Float).returns(Integer) }
  def to_cents(amount)
    (amount * 100).round
  end
end
