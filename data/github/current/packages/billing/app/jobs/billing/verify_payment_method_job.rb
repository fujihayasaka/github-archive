# typed: strict
# frozen_string_literal: true

module Billing
  class VerifyPaymentMethodJob < BillingJob
    include GitHub::Billing::ZuoraRateLimitHandler

    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    queue_as :billing

    (Billing::Zuora::RETRYABLE_ERRORS + Billing::Braintree::RETRYABLE_ERRORS).each do |error|
      retry_on(error, wait: :polynomially_longer) do |_job, error|
        Failbot.report(error)
      end
    end

    rescue_from(Zuorest::TooManyRequestsError) do |error|
      T.bind(self, VerifyPaymentMethodJob)

      zuora_rate_limit_handler(self, error)
    end

    sig { params(billable_entity: Billing::Types::Account, payment_token: String).void }
    def perform(billable_entity, payment_token)
      # Guard against payment method changes that may have happened since the job was enqueued.
      return unless customer = billable_entity.customer
      return unless customer.payment_method&.payment_token == payment_token

      # If the billable entity has a Zuora account, verify the payment method by
      # attempting to invoice and collect on any outstanding charges.
      success = if zuora_account_id = customer.zuora_account_id
        invoice_and_collect(billable_entity, zuora_account_id)
      end

      # In all other scenarios, we perform an authorization hold as needed to verify the payment method.
      if success.nil? && should_perform_authorization?(billable_entity, payment_token)
        success = perform_authorization(billable_entity)
      end

      # Do nothing if payment method verification failed
      return if success == false

      with_write do
        # If the account is billing locked, reinstate the account.
        # Note: we need to reload the entity before enabling the account to avoid writing unrelated changes
        if billable_entity.disabled?
          billable_entity.reload.enable!
          billable_entity.reset_billing_attempts
        end

        # Ensure the account has an external subscription so we can bill for metered usage.
        GitHub::Billing.transition_to_external_subscription(billable_entity)
      end
    end

    private

    sig { params(billable_entity: Billing::Types::Account, zuora_account_id: String).returns(T.nilable(T::Boolean)) }
    def invoice_and_collect(billable_entity, zuora_account_id)
      outstanding_balance = billable_entity.balance
      response = GitHub.zuorest_client.create_invoice_collect({ accountKey: zuora_account_id })
      result = GitHub::Billing::Result.from_zuora(response)
      amount_collected = response["amountCollected"] || 0

      dogstats_tags = ["disabled:#{billable_entity.disabled?}", "billing_attempts:#{billable_entity.billing_attempts}"]
      GitHub.dogstats.increment("billing.verify_payment_method.invoice_and_collect",
        tags: dogstats_tags + ["success:#{result.success?}", "declined:#{result.declined?}"])

      GitHub.logger.info(
        logger_fields(billable_entity).merge(
          "code.function" => "invoice_and_collect",
          "gh.billing.billable_entity.balance" => outstanding_balance,
          "gh.billing.result.success" => result.success?,
          "gh.billing.result.declined" => result.declined?,
          "gh.billing.zuora.amount_collected" => amount_collected,
          "gh.billing.zuora.account.id" => zuora_account_id,
          "gh.billing.zuora.response" => response,
          "gh.billing.zuora.response.success" => result.success?,
        )
      )

      if result.success?
        # A success response indicates that we were able to collect payment for one or more outstanding invoices.
        GitHub.dogstats.count("billing.verify_payment_method.invoice_and_collect.amount_collected", amount_collected, tags: dogstats_tags)
        true
      elsif result.declined?
        # A declined response indicates that the payment method on file was declined and has therefore failed verification.
        GitHub.dogstats.count("billing.verify_payment_method.invoice_and_collect.amount_outstanding", outstanding_balance, tags: dogstats_tags)
        false
      else
        # Return nil for any other non-success response which will ensure we verify the payment method via other methods.
        nil
      end
    end

    sig { params(billable_entity: Billing::Types::Account, payment_token: String).returns(T::Boolean) }
    def should_perform_authorization?(billable_entity, payment_token)
      # If we have successful payments then the payment method is already verified
      return false if has_successful_payments?(billable_entity, payment_token)
      # Billing locked accounts need an authorization to trigger an unlock
      return true if billable_entity.disabled?
      # Perform authorizations for all non-trusted accounts
      TrustTiers::Tier.for_billable_owner(billable_entity).tier != TrustTiers::Tier::TRUSTED
    end

    sig { params(billable_entity: Billing::Types::Account, payment_token: String).returns(T::Boolean) }
    def has_successful_payments?(billable_entity, payment_token)
      query = "select Id from Payment where PaymentMethodId = '#{payment_token}' and Status = 'Processed'"
      response = GitHub.zuorest_client.query_action queryString: query
      found = response["records"].any?

      GitHub.dogstats.increment("billing.verify_payment_method.has_successful_payments", tags: ["found:#{found}"])

      GitHub.logger.info(
        logger_fields(billable_entity).merge(
          "code.function" => "has_successful_payments?",
          "gh.billing.zuora.query" => query,
          "gh.billing.zuora.response" => response,
          "gh.billing.has_successful_payments" => found,
        )
      )

      found
    end

    sig { params(billable_entity: Billing::Types::Account).returns(T::Boolean) }
    def perform_authorization(billable_entity)
      # Call the perform method directly to obtain the result and to prevent background retries.
      # We do not unlock billing or reset billing attempts here, we instead do that later for consistency.
      authorization_amount_in_cents = authorization_amount_in_cents(billable_entity)
      success = Billing::CreateAuthorizationBillingTransactionJob.new.perform(
        entity_id: T.cast(billable_entity.id, Integer),
        amount_in_cents: authorization_amount_in_cents,
        unlock_billing_on_success: false,
        reset_billing_attempts_when_unlocked: false,
        is_business: billable_entity.is_a?(Business),
        skip_account_age_check: true,
        origin: self.class.name
      )

      GitHub.dogstats.increment("billing.verify_payment_method.perform_authorization",
        tags: ["success:#{success}", "disabled:#{billable_entity.disabled?}", "billing_attempts:#{billable_entity.billing_attempts}"])

      GitHub.logger.info(
        logger_fields(billable_entity).merge(
          "code.function" => "perform_authorization",
          "gh.billing.authorization.amount_in_cents" => authorization_amount_in_cents,
          "gh.billing.authorization.success" => success,
        )
      )

      success
    end

    sig { params(billable_entity: Billing::Types::Account).returns(Integer) }
    def authorization_amount_in_cents(billable_entity)
      authorization_amount_options = []

      # The base authorization amount is $1 in order to verify a payment method
      authorization_amount_options.push(100)

      # If the account has previous authorization(s) in the past hour, authorize the maximum amount again
      authorization_amount_options.push(
        billable_entity.billing_transactions.authorizations.in_the_past_hour.pluck(:amount_in_cents).max
      )

      # For Copilot organizations, authorize an amount proportional to the # of seats, up to $190
      # Note: We need this since the UsageChecker does not take into account Copilot usage
      if billable_entity.organization?
        copilot_organization = ::Copilot::Organization.new(T.cast(billable_entity, Organization))
        authorization_amount_options.push(copilot_organization.auth_and_capture_amount_in_cents)
      end

      # Authorize an amount based on the metered usage incurred
      #  - Over $500.00 of usage: $100 should be authorized
      #  - Over $0.00 of usage: $20 should be authorized
      total_metered_usage_amount_in_cents =
        begin
          Billing::UsageChecker.new(account: billable_entity).total_usage_in_cents
        rescue Billing::Platform::Api::Error => e
          Failbot.report(e, logger_fields(billable_entity))
          0
        end

      if total_metered_usage_amount_in_cents >= 50000
        authorization_amount_options.push(10000)
      elsif total_metered_usage_amount_in_cents > 0
        authorization_amount_options.push(2000)
      end

      authorization_amount_options.compact.max
    end

    sig { params(billable_entity: Billing::Types::Account).returns(T::Hash[String, T.untyped]) }
    def logger_fields(billable_entity)
      data = {
        "code.namespace" => self.class.name,
        "gh.billing.billable_entity.billed_on" => billable_entity.billed_on,
        "gh.billing.billable_entity.billing_attempts" => billable_entity.billing_attempts,
        "gh.billing.billable_entity.disabled" => billable_entity.disabled?,
        "gh.billing.billable_entity.id" => billable_entity.id,
        "gh.billing.billable_entity.login" => billable_entity.display_login,
        "gh.billing.billable_entity.type" => billable_entity.class.name,
      }

      if customer = billable_entity.customer
        data.merge!({
          "gh.billing.customer.disabled_reasons" => customer.disabled_reasons.join(","),
          "gh.billing.customer.id" => customer.id,
          "gh.billing.customer.locked_at" => customer.locked_at,
          "gh.billing.customer.requires_manual_transactions" => customer.requires_manual_transactions?,
        })
      end

      if billable_entity.is_a?(Business)
        data.merge!({
          "gh.account.type" => "business",
          "gh.business.id" => billable_entity.id,
          "gh.business.slug" => billable_entity.slug,
        })
      else
        data.merge!({
          "gh.account.type" => "user",
          "gh.user.id" => billable_entity.id,
          "gh.user.login" => billable_entity.display_login,
        })
      end

      data
    end
  end
end
