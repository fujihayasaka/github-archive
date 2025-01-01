# typed: true
# frozen_string_literal: true

# Handler for PaymentProcessed webhooks from Zuora
class Billing::Zuora::Webhooks::PaymentProcessed < ::Billing::Zuora::Webhooks::WebhookHandler
  extend T::Sig

  include ::Billing::Zuora::Webhooks::HydroInstrumentation
  include GitHub::Memoizer

  before_perform :ignore!, if: :already_processed_transaction?
  before_perform :log_restricted_user_transactions, if: -> do
    T.bind(self, Billing::Zuora::Webhooks::PaymentProcessed)
    account&.has_any_trade_restrictions? && !zuora_payment.is_retry?
  end
  before_perform :close_invoices_and_refund, if: :account_should_be_refunded?
  before_perform :ensure_zuora_subscription_exists

  def perform
    if zuora_subscription
      T.must(plan_subscription).update_from_zuora_subscription(zuora_subscription_object: zuora_subscription)
    end

    Billing::Zuora::Webhooks::ProcessPaidInvoice.perform(
      plan_subscription: plan_subscription,
      zuora_account: zuora_account,
      zuora_subscription: zuora_subscription_with_fallback,
      zuora_transaction: zuora_payment
    )

    account = T.must(self.account)

    if business_account?
      account = T.cast(account, ::Business)
      trial_completion_status_before_processing = account.trial_completion_status
      account.convert_trial if account.trial_conversion_initiated? || (account.trial? && account.autopay_disabled_by_india_rbi?)
      account.upgrade_from_organization if account.organization_upgrade_purchase_initiated?
      account.complete_creation_from_coupon(payment_required: true) if account.creation_from_coupon_purchase_initiated?
      trial_completion_status_after_processing = account.trial_completion_status
    end
    account.manual_dunning_period&.process_payment!

    instrument_processed_payment(
      trial_completion_status_before_processing: trial_completion_status_before_processing,
      trial_completion_status_after_processing: trial_completion_status_after_processing,
    )
  end

  private

  # Internal: Get the plan subscription specific to this payment
  #
  # See https://github.com/github/sponsors/issues/4709
  #
  # This is a workaround to provide the correct plan subscription for billing transactions
  # while we migrate from being subscription-centric to customer-centric.
  sig { returns(T.nilable(Billing::PlanSubscription)) }
  memoize def plan_subscription
    purpose = zuora_payment.sponsors_gateway? ? :sponsors : :general

    # When the customer record has been deleted, we need to use a different method to find the plan subscription
    # This can happen when the cleanup for a deleted account is incomplete
    if customer.nil?
      return nil if account_id.blank?
      response = GitHub.zuorest_client.query_action queryString: "select Id from Subscription where AccountId = '#{account_id}' and Status = 'Active'"
      zuora_subscription_ids = response["records"].flat_map { |record| record.values }
      return Billing::PlanSubscription.find_by(zuora_subscription_id: zuora_subscription_ids, purpose: purpose)
    end

    if purpose == :sponsors
      customer.sponsors_plan_subscription
    else
      super
    end
  end

  # Internal: Logs restricted user transaction to datadog
  sig { void }
  def log_restricted_user_transactions
    GitHub.dogstats.increment(
      "billing.trade_controls_restriction.billing_transaction.successful_transaction_for_restricted_user",
      tags: ["user:#{account}", "actor:#{account}"],
    )
  end

  sig { returns(T::Boolean) }
  def account_should_be_refunded?
    # In local development, we can receive webhooks from other GitHub instances and it will appear
    # as if an account was deleted in our own instance. This results in our instance issuing a refund
    # for someone else's GitHub instance. This line ensures we don't refund these payments, but can be
    # safely commented out if you actually need to test this behaviour in local development.
    return false if Rails.env.development?

    account_deleted? || account_charged_for_plan_after_downgrade_to_free?
  end

  # Internal: Checks if the user has downgraded to the free plan but still has
  # active Zuora subscription GitHub plan
  sig { returns(T::Boolean) }
  def account_charged_for_plan_after_downgrade_to_free?
    result = account&.plan&.free? && !zuora_subscription&.plan.nil?
    GitHub.dogstats.increment("billing.payment_processed.zuora_plan_mismatch") if result
    !!result
  end

  sig { void }
  def close_invoices_and_refund
    if account_deleted?
      customer&.destroy
      plan_subscription&.destroy
    end

    refund_payment
    close_invoices
    ignore!
  end

  # Internal: Refunds the payment that was processed
  #
  # This occurs when we've processed a payment that we shouldn't have;
  # for example, if the user has downgraded to the free plan
  # Raises StandardError if both refunding is unsuccessful
  sig { void }
  def refund_payment
    transaction = Billing::BillingTransaction.new(
      plan_subscription: plan_subscription,
      customer_id: plan_subscription&.customer_id,
      amount_in_cents: zuora_payment.amount_in_cents,
      platform: :zuora,
      platform_transaction_id: payment_id,
      transaction_id: zuora_payment.reference_id || zuora_payment.payment_number
    )

    refund_result = GitHub::Billing::Refund.new(transaction).
      process(zuora_payment.amount_in_cents)

    GitHub.dogstats.increment("billing.payment_processed.refund_payment",
      tags: datadog_tags.append("success:#{refund_result.success?}"))
    GitHub.logger.info(
      "Refund processed for payment",
      logger_fields.merge("code.function" => __method__.to_s)
    )

    return if refund_result.success?

    # Report and ignore the webhook if the refund fails
    Failbot.report!(StandardError.new("Unable to refund payment for free user"))
    ignore!
  end

  # Internal: Closes the balance on all invoices that the payment was
  # applied to so that the user is not billed again
  sig { void }
  def close_invoices
    Billing::Zuora::ZeroOutInvoices.for_transaction(payment_id)
  end

  sig do
    params(
      trial_completion_status_before_processing: T.nilable(String),
      trial_completion_status_after_processing: T.nilable(String)
    ).void
  end
  def instrument_processed_payment(trial_completion_status_before_processing:, trial_completion_status_after_processing:)
    GitHub.dogstats.increment("zuora.payment.count", tags: datadog_tags)
    GitHub.dogstats.count("zuora.payment.amount_in_cents", zuora_payment.amount_in_cents,
      tags: datadog_tags)

    unless payment_method&.valid_payment_token?
      GitHub.dogstats.increment("billing.payment_processed.missing_payment_method", tags: datadog_tags)
      GitHub.logger.info(
        "Payment processed for account missing payment method",
        logger_fields.merge("code.function" => __method__.to_s)
      )
    end

    instrument_payment_transaction(
      success: true,
      trial_completion_status_before_processing: trial_completion_status_before_processing,
      trial_completion_status_after_processing: trial_completion_status_after_processing
    )
    zuora_payment.instrument
  end

  sig { returns(T::Array[String]) }
  memoize def datadog_tags
    [
      "gateway:#{zuora_payment.gateway.parameterize}",
      "is_retry:#{zuora_payment.is_retry?}",
      "authorization:approved",
    ]
  end

  sig { returns(T::Hash[String, T.untyped]) }
  memoize def logger_fields
    {
      "code.namespace" => self.class.name,
      "gh.billing.zuora.account.id" => account_id,
      "gh.billing.zuora.payment.id" => payment_id,
      "gh.billing.billable_entity.id" => account&.id,
      "gh.billing.billable_entity.type" => account.class.name,
      "gh.billing.customer.id" => plan_subscription&.customer_id,
    }
  end
end
