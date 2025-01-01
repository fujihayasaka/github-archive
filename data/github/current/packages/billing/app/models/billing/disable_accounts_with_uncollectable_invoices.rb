# typed: strict
# frozen_string_literal: true

module Billing
  class DisableAccountsWithUncollectableInvoices

    include GitHub::Memoizer

    sig { params(account: T.nilable(::Billing::Types::Account), amount: ::Billing::Types::Numeric).void }
    def self.perform(account:, amount:)
      new(account: account, amount: amount).perform
    end

    sig { params(account: T.nilable(::Billing::Types::Account), amount: ::Billing::Types::Numeric).void }
    def initialize(account:, amount:)
      @account = account
      @amount = amount
    end

    sig { void }
    def perform
      return unless should_disable?

      account = T.must(self.account)
      instrument_lapsed_billing

      # The dotcom billing attempts is updated when Zuora makes a charge attempt and we receive the resulting
      # payment_processed or payment_declined webhook. Thus, we only need to intervene in scenarios where we know we
      # won't receive a webhook from Zuora. This is the case when `payment_method_reflects_need_to_disable?` returns true.
      #
      # Only disabling based on the payment method also ensures that we don't disable accounts where the user is
      # attempting to unlock their account and re-subscribe to a paid product. In those scenarios, an invoice is
      # generated for the account but they still have 3 billing attempts (`dotcom_record_reflects_need_to_disable?`
      # returns true). Once Zuora makes a charge attempt and we receive the resulting webhook, we will either reset
      # the billing attempts to zero (successful payment) or re-lock the account (failed payment).
      return unless payment_method_reflects_need_to_disable?

      if account.disabled?
        Billing::CancelPastDueProductsJob.perform_later(billable_entity: account, caller: self.class.name)
      else
        account.set_billing_attempts(external_payment_method_consecutive_failures)
        account.disable!
      end
    end

    private

    sig { returns(T.nilable(::Billing::Types::Account)) }
    attr_reader :account

    sig { returns(Billing::Types::Numeric) }
    attr_reader :amount

    # Does either the state of the record in dotcom or the state of the payment method
    # as recorded in Zuora reflect the need to disable this account for lapsed billing?
    sig { returns(T::Boolean) }
    def should_disable?
      return false if ignore_account?
      return false unless amount.to_i.positive?

      dotcom_record_reflects_need_to_disable? || payment_method_reflects_need_to_disable?
    end

    sig { void }
    def instrument_lapsed_billing
      increment_dogstats
      instrument_positive_invoice_with_lapsed_billing
      log_data
    end

    sig { returns(T::Boolean) }
    def ignore_account?
      account = self.account
      return true if account.nil?
      return true if account.invoiced?

      customer = account.customer
      return false unless customer.present?

      customer.requires_manual_transactions?
    end

    # Internal: Returns true the account should never be disabled in dotcom
    sig { returns(T::Boolean) }
    memoize def dotcom_never_disable?
      T.must(account).never_disable?
    end

    # Internal: Does the current state of the record in dotcom warrant the need to disable the account
    # for billing reasons?
    sig { returns(T::Boolean) }
    memoize def dotcom_record_reflects_need_to_disable?
      T.must(account).should_disable?
    end

    # Internal: Does the current state of the payment method in our subscription service reflect the need
    # to disable the account for billing reasons?
    sig { returns(T::Boolean) }
    memoize def payment_method_reflects_need_to_disable?
      has_valid_payment_method? && external_payment_method_has_three_consecutive_failures?
    end

    sig { returns(T::Boolean) }
    def has_valid_payment_method?
      T.must(account).payment_method&.valid_payment_token?
    end

    # Internal: Has Zuora attempted payment, and failed to collect, at least three times with the
    # payment method that is associated with this account?
    sig { returns(T::Boolean) }
    def external_payment_method_has_three_consecutive_failures?
      external_payment_method_consecutive_failures >= T.must(account).billing_attempts_limit
    end

    sig { returns(Integer) }
    memoize def external_payment_method_consecutive_failures
      T.must(account).payment_method.external_payment_method_consecutive_failure_count.to_i
    end

    sig { void }
    def increment_dogstats
      account = T.must(self.account)
      GitHub.dogstats.increment(
        "billing.disable_accounts_with_uncollectable_invoices",
        tags: [
          "disabled: #{account.disabled?}",
          "never_disable: #{dotcom_never_disable?}",
          "dotcom_record_reflects_need_to_disable: #{dotcom_record_reflects_need_to_disable?}",
          "payment_method_reflects_need_to_disable: #{payment_method_reflects_need_to_disable?}"
        ]
      )
    end

    sig { void }
    def instrument_positive_invoice_with_lapsed_billing
      account = T.must(self.account)
      payload = {
        account_id: account.id,
        login: account.display_login,
        payment_method_id: account.payment_method&.id,
        invoice_amount: amount,
        disabled: account.disabled?,
        never_disable: dotcom_never_disable?,
        disabled_in_dotcom: dotcom_record_reflects_need_to_disable?,
        payment_method_num_consecutive_failures: external_payment_method_consecutive_failures
      }

      GlobalInstrumenter.instrument("billing.positive_invoice.lapsed_billing", payload)
    end

    sig { void }
    def log_data
      account = T.must(self.account)
      GitHub::Logger.info(
        "at": "billing.disable_accounts_with_uncollectable_invoices",
        "code.namespace": self.class.name,
        "code.function": "instrument_lapsed_billing",
        "gh.billing.billable_entity.billing_attempts": account.billing_attempts,
        "gh.billing.billable_entity.disabled": account.disabled?,
        "gh.billing.billable_entity.id": account.id,
        "gh.billing.billable_entity.login": account.display_login,
        "gh.billing.billable_entity.never_disable": dotcom_never_disable?,
        "gh.billing.billable_entity.next_billing_date": account.next_billing_date,
        "gh.billing.billable_entity.should_disable": dotcom_record_reflects_need_to_disable?,
        "gh.billing.billable_entity.type": account.class.name,
        "gh.billing.payment_method.id": account.payment_method&.id,
        "gh.billing.payment_method.num_consecutive_failures": external_payment_method_consecutive_failures,
        "gh.billing.zuora.invoice.amount": amount
      )
    end
  end
end
