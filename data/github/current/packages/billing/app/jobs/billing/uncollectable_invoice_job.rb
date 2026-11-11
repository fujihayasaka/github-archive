# typed: strict
# frozen_string_literal: true

module Billing
  class UncollectableInvoiceJob < BillingJob
    include GitHub::Billing::ZuoraRateLimitHandler
    include GitHub::Memoizer

    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    ::Billing::Zuora::RETRYABLE_ERRORS.each do |error|
      retry_on(error, wait: :polynomially_longer) do |_job, error|
        Failbot.report(error)
      end
    end

    rescue_from(Zuorest::TooManyRequestsError) do |error|
      T.bind(self, UncollectableInvoiceJob)

      zuora_rate_limit_handler(self, error)
    end

    # Public: Checks if the provided invoice is uncollectable for the given billable entity, and if so,
    #         takes appropriate actions such as disabling the account or cancelling subscriptions.
    #
    # invoice_id - The Zuora ID of the invoice (e.g. 8ad09b7d83132604018314a3f44660d5)
    # billable_entity - User/Org/Business the invoice belongs to
    sig { params(invoice_id: String, billable_entity: Billing::Types::Account).void }
    def perform(invoice_id:, billable_entity:)
      @invoice_id = T.let(invoice_id, T.nilable(String))
      @billable_entity = T.let(billable_entity, T.nilable(Billing::Types::Account))

      return unless invoice_uncollectable?

      billable_entity = T.must(self.billable_entity)
      instrument_uncollectable_invoice

      if !has_valid_payment_method? && FeatureFlag.vexi.enabled?(:billing_support_paid_accounts_with_no_payment_method, default: false)
        # Accounts without a payment method don't need to be disabled because they won't be eligible for paid products
        # or services without a payment method anyways. That said, we do need to cancel any paid products that are up
        # for renewal since the customer won't be able to pay for them.
        Billing::CancelPastDueProductsJob.perform_later(billable_entity: billable_entity, caller: self.class.name)
      elsif payment_method_reflects_need_to_disable?
        # The dotcom billing attempts is updated when Zuora makes a charge attempt and we receive the resulting
        # payment_processed or payment_declined webhook. Thus, we only need to intervene in scenarios where we know we
        # won't receive a webhook from Zuora. This is the case when `payment_method_reflects_need_to_disable?` returns true.
        #
        # Only disabling based on the payment method also ensures that we don't disable accounts where the user is
        # attempting to unlock their account and re-subscribe to a paid product. In those scenarios, an invoice is
        # generated for the account but they still have 3 billing attempts in dotcom. Once Zuora makes a charge
        # attempt and we receive the resulting webhook, we will either reset the billing attempts to zero
        # (successful payment) or re-lock the account (failed payment).
        if billable_entity.disabled?
          Billing::CancelPastDueProductsJob.perform_later(billable_entity: billable_entity, caller: self.class.name)
        else
          with_write do
            billable_entity.set_billing_attempts(external_payment_method_consecutive_failures)
            billable_entity.disable!
          end
        end
      end
    end

    private

    sig { returns(T.nilable(String)) }
    attr_reader :invoice_id

    sig { returns(T.nilable(::Billing::Types::Account)) }
    attr_reader :billable_entity

    sig { returns(T::Boolean) }
    def invoice_uncollectable?
      return false if ignore_account?
      return false if ignore_invoice?
      !has_valid_payment_method? || payment_method_reflects_need_to_disable?
    end

    sig { returns(T::Boolean) }
    def ignore_account?
      billable_entity = self.billable_entity
      return true if billable_entity.nil?
      return true if billable_entity.invoiced?
      return true if billable_entity.delegate_billing_to_business?

      customer = billable_entity.customer
      return false unless customer.present?

      customer.requires_manual_transactions?
    end

    sig { returns(T::Boolean) }
    def ignore_invoice?
      return true unless invoice.posted?
      return true unless invoice.balance.positive?
      false
    end

    sig { void }
    def instrument_uncollectable_invoice
      increment_dogstats
      log_data
    end

    sig { returns(Billing::Zuora::Invoice) }
    memoize def invoice
      Billing::Zuora::Invoice.new(T.must(invoice_id))
    end

    # Internal: Does the current state of the payment method in our subscription service reflect the need
    # to disable the account for billing reasons?
    sig { returns(T::Boolean) }
    memoize def payment_method_reflects_need_to_disable?
      !!(has_valid_payment_method? && external_payment_method_has_three_consecutive_failures?)
    end

    # Internal: Does the customer have a payment method saved in Zuora
    sig { returns(T::Boolean) }
    memoize def has_valid_payment_method?
      !!T.must(billable_entity).payment_method&.valid_payment_token?
    end

    # Internal: Has Zuora attempted payment, and failed to collect, at least three times with the
    # payment method that is associated with this account?
    sig { returns(T::Boolean) }
    memoize def external_payment_method_has_three_consecutive_failures?
      external_payment_method_consecutive_failures >= T.must(billable_entity).billing_attempts_limit
    end

    # Internal: The number of times Zuora has attempted payment, and failed to collect, with the
    # payment method that is associated with this account.
    sig { returns(Integer) }
    memoize def external_payment_method_consecutive_failures
      T.must(billable_entity).payment_method.external_payment_method_consecutive_failure_count.to_i
    end

    sig { void }
    def increment_dogstats
      billable_entity = T.must(self.billable_entity)
      GitHub.dogstats.increment(
        "billing.uncollectable_invoice_job",
        tags: [
          "disabled: #{billable_entity.disabled?}",
          "has_valid_payment_method: #{has_valid_payment_method?}",
          "payment_method_reflects_need_to_disable: #{payment_method_reflects_need_to_disable?}"
        ]
      )
    end

    sig { void }
    def log_data
      billable_entity = T.must(self.billable_entity)
      logger_fields = {
        "code.namespace" => self.class.name,
        "code.function" => "instrument_uncollectable_invoice",
        "gh.billing.billable_entity.billed_on" => billable_entity.billed_on,
        "gh.billing.billable_entity.billing_attempts" => billable_entity.billing_attempts,
        "gh.billing.billable_entity.disabled" => billable_entity.disabled?,
        "gh.billing.billable_entity.has_valid_payment_method" => has_valid_payment_method?,
        "gh.billing.billable_entity.id" => billable_entity.id,
        "gh.billing.billable_entity.login" => billable_entity.display_login,
        "gh.billing.billable_entity.type" => billable_entity.class.name,
        "gh.billing.zuora.invoice.amount" => invoice.amount,
        "gh.billing.zuora.invoice.balance" => invoice.balance,
        "gh.billing.zuora.invoice.id" => invoice.id,
        "gh.billing.zuora.invoice.number" => invoice.number,
        "gh.billing.zuora.invoice.due_date" => invoice.due_date,
      }

      if payment_method = billable_entity.payment_method
        logger_fields.merge!(
          "gh.billing.payment_method.id" => payment_method.id,
          "gh.billing.payment_method.payment_token" => payment_method.payment_token,
          "gh.billing.payment_method.num_consecutive_failures" => external_payment_method_consecutive_failures,
        )
      end

      GitHub.logger.info(logger_fields)
    end
  end
end
