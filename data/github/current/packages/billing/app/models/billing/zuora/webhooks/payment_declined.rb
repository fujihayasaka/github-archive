# typed: true
# frozen_string_literal: true

# Handler for PaymentDeclined webhooks from Zuora
class Billing::Zuora::Webhooks::PaymentDeclined < ::Billing::Zuora::Webhooks::WebhookHandler
  include ::Billing::Zuora::Webhooks::HydroInstrumentation

  # Cooldown period for dunning an account to ensure that multiple payment failures within a single payment run
  # only dun the account once.
  DUNNING_COOLDOWN_SECONDS = T.let(1.minute.to_i, Integer)

  before_perform :ignore!, if: -> do
    T.bind(self, Billing::Zuora::Webhooks::PaymentDeclined)

    account_deleted_or_suspended? || already_processed_transaction?
  end

  def perform
    account = T.must(self.account)

    create_billing_transaction

    if account.is_a?(Business)
      trial_completion_status_before_processing = account.trial_completion_status
      if account.trial_conversion_initiated?
        restore_business_trial_upgrade_state(account)
        restore_advanced_security_upgrade_state(account)
      elsif account.organization_upgrade_purchase_initiated?
        reset_upgrade_status(account)
      elsif account.creation_from_coupon_purchase_initiated?
        account.reset_coupon_purchase_status
      else
        update_account_status
      end
      trial_completion_status_after_processing = account.trial_completion_status
    else
      update_account_status
    end

    instrument_payment_decline(
      trial_completion_status_before_processing: trial_completion_status_before_processing,
      trial_completion_status_after_processing: trial_completion_status_after_processing,
    )
  end

  private

  # Internal: Create or update a BillingTransaction for this payment
  #
  sig { void }
  def create_billing_transaction
    ::Billing::PlanSubscription::CreateBillingTransaction.perform \
      plan_subscription,
      service_ends_at: zuora_subscription&.charged_through_date || GitHub::Billing.today,
      zuora_transaction: zuora_payment
  end

  # Internal: Moves the account into dunning
  #
  sig { void }
  def dun_subscription
    account = T.must(self.account)

    account.increment_billing_attempts
    account.reload
    ::Billing::DunSubscription.perform(account)
  end

  sig { returns(String) }
  def debounce_lock_key
    "billing-debounce-dunning-#{account&.global_relay_id}"
  end

  # Internal: Only dun an account if they haven't been dunned recently
  #
  # We configure Zuora to only retry payments after a cooldown period to allow users time
  # to update their payment method, but we observe there are times when multiple failed payments
  # using the same payment method can happen in quick succession, sidestepping that protection.
  # This exists as fallback protection to ensure we don't lock users out from services.
  #
  sig { returns(T::Boolean) }
  def should_dun?
    account = T.must(self.account)
    # This is subtle, but for Billing::BillingTransactions `created_at` is set
    # to the transaction timestamp from the external billing system, so even if
    # webhooks are delayed we are comparing the time these transactions happened
    # within that external system.
    earliest_created_at = zuora_payment.created_date - DUNNING_COOLDOWN_SECONDS.seconds
    latest_created_at = zuora_payment.created_date + DUNNING_COOLDOWN_SECONDS.seconds
    scope = Billing::BillingTransaction.processor_declined
      # Look for transactions in within the cooldown period. We require looking both
      # forward and behind since there's no guarantee that these will be processed
      # in order.
      .created_at_or_after(earliest_created_at)
      .created_before(latest_created_at)
      # TODO consider encapsulating how billing transactions generate transaction ids
      .where.not(transaction_id: zuora_payment.reference_id || zuora_payment.payment_number)

    recent_failure_exists = if business_account?
      scope.for_business(account).exists?
    else
      scope.for_user(account).exists?
    end

    !recent_failure_exists
  end

  sig { void }
  def update_account_status
    account = T.must(self.account)
    if customer.requires_manual_transactions?
      if account.is_a?(Business)
        account.disable_automatic_self_serve_payment(User.ghost, reason: :india_rbi)
      else
        account.disable_auto_pay!(:india_rbi)
      end
      create_manual_dunning_period(account)
    else
      dun_subscription if should_dun?
    end
  end

  # Private: Creates a manual dunning period for an RBI affected account.
  sig { params(account: T.any(User, Business)).void }
  def create_manual_dunning_period(account)
    return unless account.autopay_disabled_by_india_rbi?
    return if account.manual_dunning_period

    attrs =
      if account.business?
        { customer: account.customer }
      else
        { user: account }
      end
    ::Billing::ManualDunningPeriod.create(attrs).run
  end

  sig do
    params(
      trial_completion_status_before_processing: T.nilable(String),
      trial_completion_status_after_processing: T.nilable(String)
    ).void
  end
  def instrument_payment_decline(trial_completion_status_before_processing:, trial_completion_status_after_processing:)
    GitHub.dogstats.increment("zuora.payment.count", tags: datadog_tags)
    GitHub.dogstats.count("zuora.payment.amount_in_cents", zuora_payment.amount_in_cents, tags: datadog_tags)

    instrument_payment_transaction(
      success: false,
      trial_completion_status_before_processing: trial_completion_status_before_processing,
      trial_completion_status_after_processing: trial_completion_status_after_processing
    )
  end

  # Internal: The tags to use for Datadog metrics
  sig { returns(T::Array[String]) }
  def datadog_tags
    [
      "gateway:#{zuora_payment.gateway.parameterize}",
      "is_retry:#{zuora_payment.is_retry?}",
      "authorization:declined",
    ]
  end

  # Private: Restore business trial upgrade state, to enable it to be re-upgraded.
  sig { params(business: ::Business).void }
  def reset_upgrade_status(business)
    if business.organization_upgrade_purchase_initiated?
      business.initiate_organization_upgrade(business.owners.first)
      business.update! upgrade_purchase_initiated_at: nil
    end

    business.disable_automatic_self_serve_payment(User.ghost)

    business.owners.each do |owner|
      BusinessMailer.purchased_org_upgrade_payment_failure(owner, business).deliver_later
    end
  end

  # Private: Restore business trial upgrade state, to enable it to be re-upgraded.
  sig { params(business: ::Business).void }
  def restore_business_trial_upgrade_state(business)
    if business.trial_expired?
      business.transaction do
        business.downgrade_to_free_plan
        business.update! trial_completion_status: :trial_expired, trial_conversion_initiated_at: nil
        # if they initiated a trial conversion after expiration, we have
        # no way of knowing what their previous deletion date was,
        # resetting to 90 days away, because they made a genuine attempt to upgrade
        if business.eligible_for_expired_trial_deletion?
          business.update! trial_deleted_at: 90.days.from_now
        end
      end
    else
      business.convert_trial_failed
      business.update! trial_completion_status: :no_trial_or_active_trial, trial_conversion_initiated_at: nil
    end

    auto_pay_disable_reason = customer.requires_manual_transactions? ? :india_rbi : :customer_initiated
    business.disable_automatic_self_serve_payment(User.ghost, reason: auto_pay_disable_reason)

    business.owners.each do |owner|
      BusinessMailer.unsuccessful_enterprise_trial_upgrade(owner, business).deliver_later
    end

    business.instrument :restore_trial_state
  end

  sig { params(business: ::Business).void }
  def restore_advanced_security_upgrade_state(business)
    return unless business.has_active_advanced_security_subscription?
    return if business.has_active_advanced_security_trial?

    business.cancel_advanced_security_subscription(actor: User.ghost, force: true, skip_sync: !business.autopay_disabled_by_india_rbi?)
  end
end
