# typed: strict
# frozen_string_literal: true

module Billing
  class UpdateCustomerBillCycleDay
    extend T::Sig
    include Instrumentation::Model

    # Public: Allows updating of the bill cycle day for a customer.
    #
    # account - The User/Organization/Business being billed.
    # purpose - Symbol indicating which Customer record to update, :general or :sponsors.
    #
    sig do
      params(account: T.any(User, Organization, Business), new_bill_cycle_day: T.nilable(Integer), purpose: Symbol).void
    end
    def initialize(account, new_bill_cycle_day, purpose: Customer::DEFAULT_PURPOSE)
      @customer = T.let(account.customer_for(purpose), T.nilable(Customer))
      @account = account
      @old_bill_cycle_day = T.let(customer&.bill_cycle_day&.to_i, T.nilable(Integer))
      @new_bill_cycle_day = new_bill_cycle_day
    end

    sig { returns(GitHub::Billing::Result) }
    def call
      if customer.nil?
        account_type = account.is_a?(Business) ? "Business" : "User"
        return GitHub::Billing::Result.failure("#{account_type} has no customer")
      end

      if T.must(customer).zuora?
        result = update_bill_cycle_day_zuora

        if result.failed?
          update_customer_record(bill_cycle_day: T.must(old_bill_cycle_day))
          return GitHub::Billing::Result.failure(result.error_message)
        end
      end

      unless update_customer_record
        return GitHub::Billing::Result.failure(T.must(customer).errors.map(&:message).first)
      end

      track_update_bill_cycle_day

      GitHub::Billing::Result.success
    end

    private

    sig { returns(T.nilable(Customer)) }
    attr_reader :customer

    sig { returns(T.any(User, Organization, Business)) }
    attr_reader :account

    sig { returns(T.nilable(Integer)) }
    attr_reader :old_bill_cycle_day

    sig { returns(T.nilable(Integer)) }
    attr_reader :new_bill_cycle_day

    sig { params(bill_cycle_day: T.nilable(Integer)).returns(T::Boolean) }
    def update_customer_record(bill_cycle_day: new_bill_cycle_day)
      T.must(customer).update(bill_cycle_day: bill_cycle_day)
    end

    sig { returns(GitHub::Billing::Result) }
    def update_bill_cycle_day_zuora
      result = T.must(T.must(customer).zuora_account).update!({
        BcdSettingOption: "ManualSet",
        BillCycleDay: new_bill_cycle_day,
      }).first
      GitHub::Billing::Result.from_zuora(result)
    end

    sig { void }
    def track_update_bill_cycle_day
      if account.is_a?(Business)
        GitHub.instrument("billing.update_bill_cycle_day",
          business: account,
          old_bill_cycle_day: old_bill_cycle_day,
          new_bill_cycle_day: new_bill_cycle_day)
      else
        GitHub.instrument("billing.update_bill_cycle_day",
          user: account,
          old_bill_cycle_day: old_bill_cycle_day,
          new_bill_cycle_day: new_bill_cycle_day)
      end
    end
  end
end
