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

    # Create a job status to track the progress of the job when it is enqueued.
    before_enqueue do |job|
      payment_token = job.arguments.second
      Billing::JobStatus.create(id: self.class.job_id(payment_token))
    end

    # Track the job status as it is performed
    # The job status will not exist if the job is called with perform_now
    around_perform do |job, block|
      payment_token = job.arguments.second
      if job_status = Billing::JobStatus.find(self.class.job_id(payment_token))
        job_status.track { block.call }
      else
        block.call
      end
    end

    sig { returns(String) }
    def self.prefix
      "verify-payment-method"
    end

    sig { params(payment_token: String).returns(String) }
    def self.job_id(payment_token)
      "#{prefix}-#{payment_token}"
    end

    sig { params(payment_token: String).returns(T.nilable(JobStatus)) }
    def self.status(payment_token)
      Billing::JobStatus.find(self.job_id(payment_token))
    end

    sig { params(billable_entity: Billing::Types::Account, payment_token: String).void }
    def perform(billable_entity, payment_token)
      # Guard against payment method changes that may have happened since the job was enqueued.
      return unless customer = billable_entity.customer
      return unless customer.payment_method&.payment_token == payment_token

      GitHub.dogstats.increment("billing.verify_payment_method.perform",
        tags: ["disabled:#{billable_entity.disabled?}", "billing_attempts:#{billable_entity.billing_attempts}"])

      # If the billable entity has a Zuora account, verify the payment method by
      # attempting to invoice and collect on any outstanding charges.
      success = if zuora_account_id = customer.zuora_account_id
        collect_invoices(billable_entity, zuora_account_id, payment_token)
      end

      payment_auth = Billing::PaymentAuthorization.new(customer: customer)

      # In all other scenarios, we perform an authorization hold as needed to verify the payment method.
      if success.nil? && should_perform_authorization?(billable_entity, payment_token, payment_authorization: payment_auth)
        success = perform_authorization(billable_entity, payment_authorization: payment_auth)
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

    sig { params(billable_entity: Billing::Types::Account, zuora_account_id: String, payment_token: String).returns(T.nilable(T::Boolean)) }
    def collect_invoices(billable_entity, zuora_account_id, payment_token)
      outstanding_balance = billable_entity.balance
      amount_collected = 0
      results = []
      open_invoices_by_payment_gateway(billable_entity, zuora_account_id).each do |payment_gateway, invoices|
        result = create_payment(billable_entity, zuora_account_id, payment_token, invoices, payment_gateway)
        results << result
        # If the payment failed, we don't attempt any more payments to try and avoid partial success scenarios.
        break if result.failed?
        amount_collected += T.unsafe(invoices.sum(&:balance))
      end

      # If no payments were created, we return nil to verify the payment method via other methods.
      return if results.empty?

      amount_outstanding = outstanding_balance - amount_collected
      declined = results.any?(&:declined?)
      failed = results.any?(&:failed?)
      success = results.any?(&:success?)
      dogstats_tags = ["disabled:#{billable_entity.disabled?}", "billing_attempts:#{billable_entity.billing_attempts}"]

      GitHub.dogstats.increment("billing.verify_payment_method.collect_invoices",
        tags: dogstats_tags + ["success:#{success}", "failed:#{failed}", "declined:#{declined}"])
      GitHub.dogstats.count("billing.verify_payment_method.collect_invoices.amount_collected",
        amount_collected, tags: dogstats_tags) if amount_collected > 0
      GitHub.dogstats.count("billing.verify_payment_method.collect_invoices.amount_outstanding",
        amount_outstanding, tags: dogstats_tags) if amount_outstanding > 0
      GitHub.logger.info(
        logger_fields(billable_entity).merge(
          "code.function" => "collect_invoices",
          "gh.billing.billable_entity.balance" => outstanding_balance,
          "gh.billing.result.success" => success,
          "gh.billing.result.failed" => failed,
          "gh.billing.result.declined" => declined,
          "gh.billing.result.error" => results.select(&:failed?).map(&:error_message).join(";"),
          "gh.billing.zuora.amount_collected" => amount_collected,
          "gh.billing.zuora.amount_outstanding" => amount_outstanding,
          "gh.billing.zuora.account.id" => zuora_account_id,
        )
      )

      if success
        # If at least one invoice is successfully charged, we treat the payment method as valid.
        # We do not require all invoices to be collected to avoid confusing users; for example,
        # they might see a successful charge while their GitHub account remains billing locked.
        # Also, any successful payment triggers a webhook that will ultimately reinstate the account.
        # In the future, if we can clearly communicate partial success scenarios to our customers
        # and update our webhook logic, we may require all invoices to be collected.
        #
        # Related note: When a payment method is associated with at least one successful payment,
        # `should_perform_authorization?` returns false
        true
      elsif declined
        # If no invoice was successfully charged and any one of the reasons is due
        # to a payment method decline, we consider the payment method as invalid.
        false
      else
        # In all other cases, we return nil to verify the payment method via other methods.
        nil
      end
    end

    sig { params(billable_entity: Billing::Types::Account, zuora_account_id: String).returns(T::Hash[T.nilable(String), T::Array[Billing::Zuora::Invoice]]) }
    def open_invoices_by_payment_gateway(billable_entity, zuora_account_id)
      open_invoices = Billing::Zuora::Invoice.open_invoices_for_account(zuora_account_id, posted_only: true, prefetch_fields: ["Balance"])

      # Invoices with Sponsors line items need to be processed using a different payment gateway since the money
      # goes into a separate Stripe account. Everything else can be processed using the default payment gateway.
      invoices_by_payment_gateway =
        if open_invoices.empty?
          {}
        elsif sponsors_plan_subscription = billable_entity.sponsors_plan_subscription
          sponsors_subscription_number = sponsors_plan_subscription.zuora_subscription_number
          open_invoices.group_by do |invoice|
            if invoice.subscription_number_from_billable_line_items == sponsors_subscription_number
              Billing::Zuora::PaymentGateway::SPONSORS_STRIPE_V2
            else
              nil
            end
          end
        else
          { nil => open_invoices }
        end

      # Sort the invoices by payment gateway to ensure we always collect the non-Sponsors invoices first.
      # This prevents billing locked customers from reinstating their account by paying only their Sponsors invoices.
      # Leaving Sponsors invoices unpaid is not an issue since nothing will get transferred to the maintainers.
      invoices_by_payment_gateway = invoices_by_payment_gateway.sort_by { |k, _| k.to_s }.to_h

      open_invoices_for_sponsors_payment_gateway = invoices_by_payment_gateway[Billing::Zuora::PaymentGateway::SPONSORS_STRIPE_V2] || []
      open_invoices_for_default_payment_gateway = invoices_by_payment_gateway[nil] || []

      GitHub.dogstats.count("billing.verify_payment_method.open_invoices_by_payment_gateway", open_invoices_for_sponsors_payment_gateway.size,
         tags: ["payment_gateway:#{Billing::Zuora::PaymentGateway::SPONSORS_STRIPE_V2}"])
      GitHub.dogstats.count("billing.verify_payment_method.open_invoices_by_payment_gateway", open_invoices_for_default_payment_gateway.size,
         tags: ["payment_gateway:default"])
      GitHub.logger.info(
        logger_fields(billable_entity).merge(
          "code.function" => "open_invoices_by_payment_gateway",
          "gh.billing.zuora.account.id" => zuora_account_id,
          "gh.billing.zuora.open_invoices_for_sponsors_payment_gateway.count" => open_invoices_for_sponsors_payment_gateway.size,
          "gh.billing.zuora.open_invoices_for_sponsors_payment_gateway.ids" => open_invoices_for_sponsors_payment_gateway.map(&:id),
          "gh.billing.zuora.open_invoices_for_default_payment_gateway.count" => open_invoices_for_default_payment_gateway.size,
          "gh.billing.zuora.open_invoices_for_default_payment_gateway.ids" => open_invoices_for_default_payment_gateway.map(&:id),
        )
      )

      invoices_by_payment_gateway
    end

    sig do
      params(
        billable_entity: Billing::Types::Account,
        zuora_account_id: String,
        payment_token: String,
        invoices: T::Array[Billing::Zuora::Invoice],
        payment_gateway: T.nilable(String),
      ).returns(GitHub::Billing::Result)
    end
    def create_payment(billable_entity, zuora_account_id, payment_token, invoices, payment_gateway = nil)
      effective_date = GitHub::Billing.today.to_s
      params = {
        AccountId: zuora_account_id,
        Comment: "Created by VerifyPaymentMethodJob",
        EffectiveDate: effective_date,
        InvoicePaymentData: {
          InvoicePayment: invoices.map { |invoice| { InvoiceId: invoice.id, Amount: invoice.balance } },
        },
        PaymentMethodId: payment_token,
        Status: "Processed",
        Type: "Electronic"
      }
      params[:Gateway] = payment_gateway if payment_gateway

      response = GitHub.zuorest_client.create_payment(params)
      result = GitHub::Billing::Result.from_zuora(response)

      # The create_payment response only tells us if the payment was created successfully and returns a payment ID.
      # We need to retrieve the payment itself to determine if the payment was successfully processed or not.
      payment_id = response["Id"]
      payment = result.success? ? GitHub.zuorest_client.get_payment(payment_id) : {}
      result = GitHub::Billing::Result.failure(payment["GatewayResponse"]) if payment["Status"] != "Processed"

      payment_gateway_name = payment_gateway || "Default"
      GitHub.dogstats.increment("billing.verify_payment_method.create_payment",
        tags: ["disabled:#{billable_entity.disabled?}", "billing_attempts:#{billable_entity.billing_attempts}",
        "payment_gateway:#{payment_gateway_name}", "success:#{result.success?}", "declined:#{result.declined?}"])

      GitHub.logger.info(
        logger_fields(billable_entity).merge(
          "code.function" => "create_payment",
          "gh.billing.result.success" => result.success?,
          "gh.billing.result.declined" => result.declined?,
          "gh.billing.zuora.account.id" => zuora_account_id,
          "gh.billing.zuora.invoices.ids" => invoices.map(&:id),
          "gh.billing.zuora.invoices.balances" => invoices.map(&:balance),
          "gh.billing.zuora.payment.id" => payment_id,
          "gh.billing.zuora.payment.amount" => payment["Amount"],
          "gh.billing.zuora.payment.number" => payment["PaymentNumber"],
          "gh.billing.zuora.payment.status" => payment["Status"],
          "gh.billing.zuora.payment.gateway_response" => payment["GatewayResponse"],
          "gh.billing.zuora.payment.gateway_response_code" => payment["GatewayResponseCode"],
          "gh.billing.zuora.payment_effective_date" => effective_date,
          "gh.billing.zuora.payment_gateway" => payment_gateway_name,
          "gh.billing.zuora.payment_method.id" => payment_token,
          "gh.billing.zuora.response" => response,
        )
      )

      result
    end

    sig { params(billable_entity: Billing::Types::Account, payment_token: String, payment_authorization: Billing::PaymentAuthorization).returns(T::Boolean) }
    def should_perform_authorization?(billable_entity, payment_token, payment_authorization:)
      # If we have successful payments then the payment method is already verified
      return false if has_successful_payments?(billable_entity, payment_token)
      # Billing locked accounts need an authorization to trigger an unlock
      return true if billable_entity.disabled?

      payment_authorization.should_be_authorized?(eligibility_options: Billing::PaymentAuthorization::EligibilityOptions.only_trust_tier_check)
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

    sig { params(billable_entity: Billing::Types::Account, payment_authorization: Billing::PaymentAuthorization).returns(T::Boolean) }
    def perform_authorization(billable_entity, payment_authorization:)
      result = payment_authorization.create(async: false, metadata: Billing::PaymentAuthorization::Metadata.new(origin: self.class.name.to_s))
      success = result.authorized?
      GitHub.dogstats.increment("billing.verify_payment_method.perform_authorization",
        tags: ["success:#{success}", "disabled:#{billable_entity.disabled?}", "billing_attempts:#{billable_entity.billing_attempts}"])

      GitHub.logger.info(
        logger_fields(billable_entity).merge(
          "code.function": "perform_authorization",
          "gh.billing.authorization.amount_in_cents": result.amount_authorized_in_cents,
          "gh.billing.authorization.success": success,
        )
      )

      success
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
