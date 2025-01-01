# typed: strict
# frozen_string_literal: true

class Billing::Domain::PaymentAuthorizations < GH::Domain::Base
  # Triggers a payment authorization for a customer.
  #
  # Depending on the customer's current authorization status,
  # it may perform a new authorization or skip if recent authorizations exist.
  sig do
    params(
      customer_id: Integer,
      origin: String,
      amount_in_cents: T.nilable(Integer),
      check_payment_method: T::Boolean,
      check_overage: T::Boolean,
      check_trust_tier: T::Boolean,
      unlock_billing_on_success: T::Boolean,
      reset_billing_attempts_when_unlocked: T::Boolean,
      cancel_free_trials_on_failure: T::Boolean,
      skip_if_last_authorized_at: T.nilable(Time),
      async: T::Boolean,
      delay: Integer,
    ).returns(GH::Result[::Billing::CreatePaymentAuthorizationResult]).checked(:always).on_failure(:raise)
  end
  def create( # rubocop:todo Metrics::MethodLength
    customer_id:,
    origin:,
    amount_in_cents: nil,
    check_payment_method: true,
    check_overage: true,
    check_trust_tier: true,
    unlock_billing_on_success: false,
    reset_billing_attempts_when_unlocked: false,
    cancel_free_trials_on_failure: false,
    skip_if_last_authorized_at: nil,
    async: true,
    delay: 0
  )
    return GH::Result::Error::Argument.new("synchronous authorizations cannot be delayed") if !async && delay.positive?
    return GH::Result::Error::NotFound.new("customer required for payment authorizations") unless customer = Customer.find_by(id: customer_id)
    return GH::Result::Error::NotFound.new("billable owner not found for customer") unless account = customer.billable_owner

    logger_fields = {
      "code.namespace": self.class.name,
      "code.function": "create",
      "gh.billing.payment_authorizations.create.origin": origin,
      "gh.billing.billable_entity.id": account.id,
      "gh.billing.billable_entity.type": account.class.name,
      "gh.billing.customer.id": customer.id,
    }
    dogstats_tags = ["origin:#{origin}", "account_type:#{account.class.name.to_s.downcase}"]
    GitHub.logger.with_named_tags(logger_fields) do
      payment_authorization = Billing::PaymentAuthorization.new(customer: customer)
      eligibility_options = Billing::PaymentAuthorization::EligibilityOptions.new(
        check_payment_method: check_payment_method,
        check_overage: check_overage,
        check_trust_tier: check_trust_tier
      )

      unless payment_authorization.should_be_authorized?(eligibility_options: eligibility_options)
        log_skipped_authorization(
          reason: "ineligible",
          dogstats_tags: dogstats_tags,
          logger_tags: { "gh.billing.payment_authorizations.create.eligibility_options": eligibility_options.serialize }
        )
        return GH::Result::Error::Forbidden.new("account cannot be authorized at this time")
      end

      authorizations_query = account
        .billing_transactions
        .authorizations

      authorizations_query = authorizations_query
        .successful
        .where("amount_in_cents >= ?", payment_authorization.authorization_amount_in_cents(custom_amount_in_cents: amount_in_cents))

      existing_authorization = if skip_if_last_authorized_at
        authorizations_query.created_at_or_after(skip_if_last_authorized_at).first
      else
        authorizations_query.in_the_past_hour.first
      end

      if existing_authorization
        log_skipped_authorization(
          reason: "recent_authorization_exists",
          dogstats_tags: dogstats_tags,
          logger_tags:  { "gh.billing.payment_authorizations.create.existing_auth_timeframe_check": skip_if_last_authorized_at&.iso8601 || 1.hour.ago.iso8601 }
        )
        return GH::Result::Ok.new(::Billing::CreatePaymentAuthorizationResult.skipped(reason: Billing::CreatePaymentAuthorizationResult::Reason::RecentAuthorizationExists))
      end

      result = payment_authorization.create(
        async: async,
        amount_in_cents: amount_in_cents,
        metadata: Billing::PaymentAuthorization::Metadata.new(origin:),
        eligibility_options: eligibility_options,
        post_authorization_options: Billing::PaymentAuthorization::PostAuthorizationOptions.new(
          unlock_billing_on_success:,
          reset_billing_attempts_when_unlocked:,
          cancel_free_trials_on_failure:
        )
      )

      GH::Result::Ok.new(result)
    end
  end

  private

  sig { params(reason: String, dogstats_tags: T::Array[String], logger_tags: T::Hash[String, T.untyped]).void }
  def log_skipped_authorization(reason:, dogstats_tags: [], logger_tags: {})
    GitHub.dogstats.increment("billing.payment_authorizations.create", tags: ["status:skipped", "reason:#{reason}"] + dogstats_tags)
    GitHub.logger.info(
      "skipping payment authorization",
      { "gh.billing.payment_authorizations.create.skip_reason": reason }.merge!(logger_tags)
    )
  end
end
