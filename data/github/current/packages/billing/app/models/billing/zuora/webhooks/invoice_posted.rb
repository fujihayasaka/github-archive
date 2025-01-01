# typed: true
# frozen_string_literal: true

# Handler for InvoicePosted webhooks from Zuora
class Billing::Zuora::Webhooks::InvoicePosted < ::Billing::Zuora::Webhooks::WebhookHandler
  extend T::Sig

  include GitHub::Memoizer

  before_perform :ignore!, if: :ignore?
  before_perform :cancel_subscriptions, if: :account_suspended?
  before_perform :instrument_trade_controls_invoice, if: -> do
    T.bind(self, Billing::Zuora::Webhooks::InvoicePosted)

    account&.autopay_disabled_by_trade_controls?
  end

  # Public: Holding this lock will cause any invoice posted webhooks to be ignored for an account.
  #
  # This can be used when invoice manipulation is necessary and the webhook processing is undesirable. An
  # example is when restoring a sponsorship, where we need to ensure the generated invoice is zeroed out before
  # the invoice is processed (which may happen outside the lock due to webhook latency).
  sig { params(account: ::Billing::Types::Account, block: T.proc.void).void }
  def self.lock_processing(account:, &block)
    self._mutex(account: account).lock { yield }
  end

  # Internal: Are we currenlty locked from processing invoice posted webhooks for the given account?
  sig { params(account: ::Billing::Types::Account).returns(T::Boolean) }
  def self._processing_locked?(account:)
    self._mutex(account: account).locked?
  end

  # Internal: Mutex used to coordinate with other processes that want to lock invoice posted webhook processing.
  sig { params(account: ::Billing::Types::Account).returns(GitHub::Redis::Mutex) }
  def self._mutex(account:)
    GitHub::Redis::Mutex.new("lock-invoice-posted-processing-#{account.global_relay_id}")
  end

  def perform
    if should_add_sponsors_fees?
      GitHub.dogstats.increment("sponsors.fees.added_to_invoice")
      GitHub.logger.info("Adding sponsors fees", {
          "gh.user.id": account&.id,
          "gh.billing.zuora.invoice.id": invoice_id
        }
      )
      account&.sponsors_plan_subscription&.synchronize_later(collect: false)
    end

    if should_zero_out_paypal_sponsors_items?
      Sponsors::CancelSponsorshipsFromPaypalSponsors.call(account)
      zero_out_paypal_sponsors_items
    end

    Billing::Zuora::Invoice.record_metrics(
      balance_in_cents: zuora_invoice.balance * 100,
      calling_class: self.class.name.to_s.underscore,
    )
    if zuora_invoice.amount.zero?
      perform_with_zero_amount
    elsif zuora_invoice.balance.negative?
      ::Billing::Zuora::NegativeInvoiceJob.set(wait: 1.hour).perform_later(invoice_id: invoice_id)
    elsif zuora_invoice.balance.positive?
      offset = rand(1.hour..4.hours).seconds
      Billing::PositiveInvoiceCatchupDisableJob
        .set(wait: offset)
        .perform_later(zuora_account_id: account_id, invoice_amount: zuora_invoice.amount)

      if plan_subscription.sponsors_invoiced? && !account.is_a?(Business)
        SponsorsBillingCreditBalanceInvoiceCollectionJob.perform_later(
          T.cast(account, GitHubSponsors::Types::Sponsor), invoice_id: invoice_id,
        )
      end

      plan_subscription.update(balance_in_cents: (T.must(zuora_account)["metrics"]["balance"] * 100).to_i)

      if create_manual_dunning_period?
        account = T.must(self.account)
        attrs =
          if account.business?
            { customer: account.customer }
          else
            { user: account }
          end
        ::Billing::ManualDunningPeriod.create(attrs).run
      end
    end

    # Temporary: As an alternative to using a transition to synchronize all Zuora subscriptions, this snippet
    #            of code should allow us to synchronize all Zuora subscriptions over the course of a month.
    if T.must(self.account).feature_enabled?(:billing_schedule_synchronization_after_invoice_posted)
      # The daily Zuora billing run happens at 1 AM PT and we receive the invoice posted webhooks
      # from that between 4 AM and 5 AM PT. Our total Zuora request count generally bottoms out
      # between 5 PM PT until midnight PT. So we schedule our synchronizations between this time
      # to ensure minimal impact to other billing processes.
      offset = rand(11.hours..19.hours).seconds
      plan_subscription.synchronize_later(wait: offset)
    end
  end

  private

  sig { returns(T::Boolean) }
  def should_add_sponsors_fees?
    account = T.must(self.account)

    return false if account.business?
    account = T.cast(account, User)
    return false unless account.should_pay_fees_at_sponsorship_payment_time?

    subscribable_invoice_items.any?(&:zero_dollar_sponsors_fee_charge?)
  end

  sig { returns(T::Boolean) }
  def create_manual_dunning_period?
    account = T.must(self.account)

    account.autopay_disabled_by_india_rbi? && !account.manual_dunning_period &&
      plan_subscription.balance_in_cents.positive?
  end

  # Process a posted invoice with a zero dollar amount
  sig { void }
  def perform_with_zero_amount
    # cover scenario for apple in app purchases
    if plan_subscription.apple_iap_subscription?
      # Reset to move billing cycle forward
      # Note: The zuora subscription will be nil when the user cancels their subscription
      #       and SynchronizeAppleIapSubscriptionJob has not been run yet
      unless zuora_subscription.nil?
        plan_subscription.update_from_zuora_subscription(
          zuora_subscription_object: zuora_subscription
        )
        reset_billing_status
      end

      return
    end

    # Do nothing if we already have a zero-dollar BillingTransaction for this invoice date
    return if T.must(account).billing_transactions.where(amount_in_cents: 0).where("DATE(created_at) = ?", invoice_date.to_date).any?

    begin
      synchronize_plan_subscription unless plan_subscription_available?

      if plan_subscription_available?
        plan_subscription.update_from_zuora_subscription(
          zuora_subscription_object: zuora_subscription
        )

        if account&.dunning? && zuora_balance.positive?
          plan_subscription.update(balance_in_cents: zuora_balance.cents)
        elsif !account&.disabled?
          reset_billing_status
        end

        create_no_charge_billing_transaction
      elsif plan_subscription.present?
        create_no_charge_billing_transaction
      end
    rescue Billing::Zuora::MissingPaymentMethodError
      create_no_charge_billing_transaction
    end
  end

  sig { returns(::Billing::PlanSubscription) }
  def synchronize_plan_subscription
    plan_subscription.synchronize_with_lock
    plan_subscription.reload
  rescue GitHub::Restraint::UnableToLock
    raise ::Billing::ZuoraWebhook::RetryableError
  end

  sig { returns(T::Boolean) }
  def plan_subscription_available?
    plan_subscription.reload.zuora_subscription_number.present?
  end

  # Internal: Reset the user's billing for a new cycle
  sig { void }
  def reset_billing_status
    ::Billing::ResetBillingStatus.perform(
      customer,
      balance_in_cents: zuora_balance.cents,
      next_billing_date: zuora_subscription&.charged_through_date.to_s,
    )
  end

  # Internal: Create or update a BillingTransaction for this $0 charge
  sig { void }
  def create_no_charge_billing_transaction
    account = T.must(self.account)
    billing_transaction = account.billing_transactions.new(
      amount_in_cents: 0,
      plan_subscription: plan_subscription,
      created_at: invoice_date,
      platform: :zuora,
      payment_type: :no_charge,
      service_ends_at: zuora_subscription&.charged_through_date || GitHub::Billing.today,
    )
    billing_transaction.log_zero_charge(billable_entity: account)
  end

  # Internal: The Zuora invoice date in the GitHub Billing timezone
  sig { returns(::Billing::Types::Time) }
  def invoice_date
    GitHub::Billing.timezone.parse(zuora_invoice.invoice_date)
  end

  sig { returns(::Billing::Money) }
  memoize def zuora_balance
    ::Billing::Money.new(T.must(zuora_account)["metrics"]["balance"] * 100)
  end

  sig { void }
  def instrument_trade_controls_invoice
    GitHub.dogstats.increment "trade_controls.invoice_posted",
      tags: ["positive:#{zuora_invoice.balance.positive?}"]
  end

  sig { returns(T::Boolean) }
  def should_zero_out_paypal_sponsors_items?
    return false unless GitHub.sponsors_enabled?
    return false unless zuora_invoice.balance.positive?

    account = T.must(self.account)

    # Businesses can't have sponsorships, so nothing to do for them:
    return false unless account.user? || account.organization?

    # Nothing to do if the account doesn't use PayPal, or it does but PayPal deprecation isn't yet in effect:
    return false if account.has_valid_payment_method_for_sponsorships?

    # If they have an invalid payment method that isn't PayPal, that's not a problem we want to handle
    # here, but rather in our usual dunning process:
    return false unless account.has_paypal_account_for_sponsors?

    # Avoid calling #sponsors_invoice_items_to_zero_out till the end since it will make multiple requests to
    # Zuora.
    !sponsors_invoice_items_to_zero_out.empty? # check if there are any sponsors items to zero out
  end

  sig { returns(T::Array[Billing::Zuora::SubscribableInvoiceItem]) }
  memoize def sponsors_invoice_items_to_zero_out
    # #invoice_items makes a ZOQL query request to Zuora, as well as calling #rpc_tracking_data which makes
    # one or more ZOQL query requests to Zuora.
    subscribable_invoice_items.select do |item|
      item.sponsors_item? && item.charge_amount.positive?
    end
  end

  sig { returns(T::Array[Billing::Zuora::SubscribableInvoiceItem]) }
  memoize def subscribable_invoice_items
    T.cast(zuora_invoice.invoice_items.select(&:subscribable?), T::Array[Billing::Zuora::SubscribableInvoiceItem])
  end

  sig { void }
  def zero_out_paypal_sponsors_items
    return if sponsors_invoice_item_adjustments.empty?

    Billing::Zuora::InvoiceItemAdjustmentBuilder.instrument_invoice_item_adjustments(
      sponsors_invoice_item_adjustments,
      class_tag: dogstats_class_tag,
      product: "sponsors",
    )

    response = GitHub.zuorest_client.create_action(objects: sponsors_invoice_item_adjustments,
                                                   type: "InvoiceItemAdjustment")
    results = response.map { |r| GitHub::Billing::Result.from_zuora(r) }

    log_failures_to_zero_out_paypal_sponsors_items(results)
    instrument_zeroing_out_invoice_items(results, sponsors_invoice_item_adjustments: sponsors_invoice_item_adjustments)
  end

  sig { params(results: T::Array[GitHub::Billing::Result]).void }
  def log_failures_to_zero_out_paypal_sponsors_items(results)
    error_results = results.reject(&:success?)
    return if error_results.empty?

    account = T.must(self.account)
    success_count = results.count(&:success?)
    failure_count = error_results.size
    user_type_key = account.user? ? "user" : "org"
    total_dollars = sponsors_invoice_item_adjustments.sum { |a| a.fetch(:Amount, 0) }

    GitHub.logger.warn(
      "Failed to zero out all PayPal Sponsors invoice items",
      "code.namespace" => self.class.name,
      "code.function" => __method__,
      "catalog_service" => "github/github_sponsors",
      "gh.#{user_type_key}.id" => account.id,
      "gh.#{user_type_key}" => account.display_login,
      "gh.billing.zero_out_paypal_sponsors_items" => sponsors_invoice_items_to_zero_out.map(&:id).join(","),
      "gh.billing.zero_out_paypal_sponsors_items.success_count" => success_count,
      "gh.billing.zero_out_paypal_sponsors_items.failure_count" => failure_count,
      "gh.billing.zero_out_paypal_sponsors_items.zuora_invoice_id" => zuora_invoice.id,
      "gh.billing.zero_out_paypal_sponsors_items.total_adjustment_amount_in_dollars" => total_dollars,
      "exception.message" => error_results.map(&:error_message).to_sentence,
    )
  end

  sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  memoize def sponsors_invoice_item_adjustments
    adjustments = []
    remaining_balance = T.let(zuora_invoice.balance, ::Billing::Types::Numeric)

    sponsors_invoice_items_to_zero_out.each do |item|
      # Zuora doesn't allow negative balance invoice to go positive, so we break
      break if remaining_balance == 0

      amount_to_zero_out = item_adjustment_amount_to_zero_out(item, remaining_balance: remaining_balance, zuora_invoice_id: zuora_invoice.id)
      # Negative amount because we want to credit it to the sponsor:
      item_adjustment_amount = 0.to_d - amount_to_zero_out.to_d

      # Add a negative to reduce the remaining balance:
      remaining_balance += item_adjustment_amount

      adjustments << Billing::Zuora::InvoiceItemAdjustmentBuilder.adjustment_for(amount: item_adjustment_amount,
                                                                                 invoice_id: zuora_invoice.id, item_id: item.id)
    end

    adjustments
  end

  sig { returns(String) }
  memoize def dogstats_class_tag
    self.class.name.to_s.underscore
  end

  sig { returns(T::Boolean) }
  def ignore?
    return true if account_deleted?

    self.class._processing_locked?(account: T.must(account))
  end

  sig do
    params(
      results: T::Array[GitHub::Billing::Result],
      sponsors_invoice_item_adjustments: T::Array[T.untyped],
    ).void
  end
  def instrument_zeroing_out_invoice_items(results, sponsors_invoice_item_adjustments: [])
    success = results.all?(&:success?)

    GitHub.logger.info(
      "code.namespace" => self.class.name,
      "code.function" => "zero_out_eligible_invoice_items",
      "gh.catalog_service" => "github/payment_processing",
      "gh.billing.sponsors_invoice_item_adjustments" => sponsors_invoice_item_adjustments.to_s,
      "gh.billing.zuora.response_results" => results.map(&:to_s).to_s,
    )

    tags = ["success:#{success}", "class:#{dogstats_class_tag}"]
    tags << "includes_sponsors:true" if sponsors_invoice_item_adjustments.any?
    GitHub.dogstats.increment("zuora.invoices.zero_out_invoice_items", tags: tags)
  end

  # Get the dollar amount we can adjust for an invoice item.
  #
  # item - a Billing::Zuora::InvoiceItem
  # remaining_balance - Numeric value for how much is available to debit, e.g., Billing::Zuora::Invoice#balance
  # zuora_invoice_id - String ID of the Zuora invoice with the item to adjust
  sig do
    params(
      item: Billing::Zuora::InvoiceItem,
      remaining_balance: ::Billing::Types::Numeric,
      zuora_invoice_id: String,
    ).returns(::Billing::Types::Numeric)
  end
  def item_adjustment_amount_to_zero_out(item, remaining_balance:, zuora_invoice_id:)
    charge_amount = item.charge_amount.dollars.abs
    max_adjustment_amount = remaining_balance.abs

    if charge_amount > max_adjustment_amount
      # If we hit this state, it means that this really should have been a
      # positive balance invoice to start with!
      GitHub::Logger.log(
        at: "negative_invoices.missed_positive_balance_invoice",
        catalog_service: "github/payment_processing",
        zuora_invoice_id: zuora_invoice_id,
      )
      GitHub.dogstats.increment("zuora.invoices.missed_positive_balance_invoice",
        tags: ["class:#{dogstats_class_tag}"],
      )
      max_adjustment_amount
    else
      charge_amount
    end
  end

  sig { void }
  def cancel_subscriptions
    account&.cancel_billing
    ignore!
  end
end
