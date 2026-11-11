# typed: strict
# frozen_string_literal: true

class Billing::PaymentAuthorization
  include GitHub::Memoizer

  class Metadata < T::Struct
    const :origin, String, default: "somewhere"
  end

  class EligibilityOptions < T::Struct
    const :check_payment_method, T::Boolean, default: true
    const :check_trust_tier, T::Boolean, default: true

    sig { returns(T.attached_class) }
    def self.only_trust_tier_check
      new(check_payment_method: false)
    end
  end

  class PostAuthorizationOptions < T::Struct
    const :unlock_billing_on_success, T::Boolean, default: false
    const :reset_billing_attempts_when_unlocked, T::Boolean, default: false
    const :cancel_free_trials_on_failure, T::Boolean, default: false
  end

  sig { params(customer: Customer).void }
  def initialize(customer:)
    @customer = customer
  end

  sig do
    params(
      async: T::Boolean,
      delay: Integer,
      post_authorization_options: PostAuthorizationOptions,
      metadata: Metadata,
      amount_in_cents: T.nilable(Integer),
      eligibility_options: T.nilable(EligibilityOptions),
      include_gross_usage: T::Boolean,
    ).returns(Billing::CreatePaymentAuthorizationResult)
  end
  def create(async: true, delay: 0, post_authorization_options: PostAuthorizationOptions.new, metadata: Metadata.new, amount_in_cents: nil, eligibility_options: nil, include_gross_usage: false)
    raise ArgumentError, "async cannot be false if delay is greater than 0" if !async && delay.positive?

    unless can_be_authorized?
      return Billing::CreatePaymentAuthorizationResult.skipped(reason: Billing::CreatePaymentAuthorizationResult::Reason::CannotBeAuthorized)
    end

    if eligibility_options && !should_be_authorized?(eligibility_options: eligibility_options)
      return Billing::CreatePaymentAuthorizationResult.skipped(reason: Billing::CreatePaymentAuthorizationResult::Reason::Ineligible)
    end

    auth_amount_in_cents = authorization_amount_in_cents(custom_amount_in_cents: amount_in_cents, include_gross_usage: include_gross_usage)

    args = {
      entity_id: account.id,
      is_business: account.is_a?(Business),
      amount_in_cents: auth_amount_in_cents,
      origin: metadata.origin,
      unlock_billing_on_success: post_authorization_options.unlock_billing_on_success,
      reset_billing_attempts_when_unlocked: post_authorization_options.reset_billing_attempts_when_unlocked,
      cancel_free_trials_on_failure: post_authorization_options.cancel_free_trials_on_failure,
    }
    job_klass = Billing::CreateAuthorizationBillingTransactionJob
    if async
      enqueue_result = if delay.positive?
        job_klass.set(wait: delay)
      else
        job_klass
      end.perform_later(**args)

      if enqueue_result
        Billing::CreatePaymentAuthorizationResult.success(amount_authorized_in_cents: auth_amount_in_cents)
      else
        Billing::CreatePaymentAuthorizationResult.failed(reason: Billing::CreatePaymentAuthorizationResult::Reason::EnqueueFailure, amount_authorized_in_cents: auth_amount_in_cents)
      end
    else
      # Calling new.perform instead of perform_now to avoid background retries on exceptions
      if job_klass.new.perform(**args)
        Billing::CreatePaymentAuthorizationResult.success(amount_authorized_in_cents: auth_amount_in_cents)
      else
        Billing::CreatePaymentAuthorizationResult.failed(reason: Billing::CreatePaymentAuthorizationResult::Reason::AuthorizationFailure, amount_authorized_in_cents: auth_amount_in_cents)
      end
    end
  end

  sig { returns(T::Boolean) }
  def can_be_authorized?
    return false if account.invoiced?
    return true unless account.metered_via_azure?

    # There are accounts that have metered services billed to Azure but are on volume GHE, meaning Azure isn't used to pay for GHE
    # Thus, their payment method still needs to be authorized for their GHE volume usage.
    # For businesses on metered GHE: all charges go through Azure, so skip authorization
    return false if account.is_a?(Business) && customer.metered_plan?
    return true unless account.feature_flag_enabled?(:billing_skip_org_authorization_if_only_billed_via_azure, default: false)

    # For organizations or businesses without metered GHE: check if they have any non-Azure charges
    # that would require a payment method authorization
    !account.payment_amount(include_metered_usage: false).zero?
  end

  sig { params(eligibility_options: EligibilityOptions).returns(T::Boolean) }
  def should_be_authorized?(eligibility_options: EligibilityOptions.new)
    return false unless can_be_authorized?

    if eligibility_options.check_payment_method
      return false unless payment_method&.supports_authorization?
    end

    if eligibility_options.check_trust_tier
      # TODO: can we stick trust tier check in the user model? Does health depend on billing or does billing depend on health?
      # Right now is a dependency violation
      trust_tier = TrustTiers::Tier.for_billable_owner(account).tier
      return false if trust_tier == TrustTiers::Tier::TRUSTED

      # Skip accounts in dunning that have a paid plan and a long history of successful payments.
      #
      # This avoids a poor customer experience where a single failed payment can result in their
      # account being prematurely billing locked due to their trust tier status being downgraded.
      return false if trust_tier == TrustTiers::Tier::NEUTRAL && account.dunning? && account.plan.cost > 0 && account.successful_paid_payments?(
        start_date: GitHub::Billing.today - 4.months,
        minimum_payment_count: 3,
        minimum_payment_amount_in_cents: 40_000
      )
    end

    true
  end

  sig { params(custom_amount_in_cents: T.nilable(Integer), include_gross_usage: T::Boolean).returns(Integer) }
  def authorization_amount_in_cents(custom_amount_in_cents: nil, include_gross_usage: false)
    # Default authorization amount is $1.00
    authorization_amount_options = [100, custom_amount_in_cents]

    # If the account has previous authorization(s) in the past hour, authorize the maximum amount again
    authorization_amount_options.push(
      account.billing_transactions.authorizations.in_the_past_hour.pluck(:amount_in_cents).max
    )

    # For Copilot organizations, authorize an amount proportional to the # of seats, up to $190
    # Note: We need this since the UsageChecker does not take into account Copilot usage
    if account.organization?
      authorization_amount_options.push(::Copilot::Organization.new(T.cast(account, Organization)).auth_and_capture_amount_in_cents)
    end

    # Authorize an amount based on the metered net usage incurred
    #  - Over $500.00 of net usage: $100 should be authorized
    #  - Over $0.00 of net usage: $20 should be authorized
    if total_metered_usage_amount_in_cents >= 50_000
      authorization_amount_options.push(10_000)
    elsif total_metered_usage_amount_in_cents > 0
      authorization_amount_options.push(2_000)
    end

    if include_gross_usage
      # Authorize an amount based on the metered gross usage incurred, matching gross thresholds
      #  - Over $200.00 of gross usage: $200 should be authorized
      #  - Over $100.00 of gross usage: $100 should be authorized
      #  - Over $50.00 of gross usage: $50 should be authorized
      if total_metered_gross_usage_amount_in_cents >= 20_000
        authorization_amount_options.push(20_000)
      elsif total_metered_gross_usage_amount_in_cents >= 10_000
        authorization_amount_options.push(10_000)
      elsif total_metered_gross_usage_amount_in_cents >= 5_000
        authorization_amount_options.push(5_000)
      end
    end

    authorization_amount_options.compact.max.to_i
  end


  private

  sig { returns(Billing::UsageChecker::UsageResult) }
  memoize def metered_usage_result
    Billing::UsageChecker.new(account: account).usage_result
  rescue Billing::Platform::Api::Error => e
    # TODO: logger_fields
    Failbot.report(e)

    Billing::UsageChecker::UsageResult.new(net_amount_in_cents: 0, gross_amount_in_cents: 0)
  end

  sig { returns(Integer) }
  def total_metered_usage_amount_in_cents
    metered_usage_result.net_amount_in_cents
  end

  sig { returns(Integer) }
  def total_metered_gross_usage_amount_in_cents
    metered_usage_result.gross_amount_in_cents
  end

  sig { returns(Customer) }
  attr_reader :customer

  sig { returns(T.nilable(PaymentMethod)) }
  def payment_method
    customer.payment_method
  end

  sig { returns(Billing::Types::Account) }
  def account
    T.must(customer.billable_owner)
  end
end
