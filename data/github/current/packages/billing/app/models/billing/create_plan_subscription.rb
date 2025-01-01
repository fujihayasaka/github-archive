# typed: strict
# frozen_string_literal: true

module Billing
  class CreatePlanSubscription
    extend T::Sig

    class UnprocessableError < StandardError; end
    include GitHub::Memoizer

    # Public: Create a plan subscription for the specified account.
    sig { params(account: ::Billing::Types::Account, skip_sync: T::Boolean).returns(Billing::PlanSubscription) }
    def self.call(account:, skip_sync: false)
      new(account: account, skip_sync: skip_sync).call
    end

    sig { params(account: ::Billing::Types::Account, skip_sync: T::Boolean).void }
    def initialize(account:, skip_sync: false)
      @account = account
      @skip_sync = skip_sync
    end

    sig { returns(::Billing::Types::Account) }
    attr_reader :account

    sig { returns(T::Boolean) }
    attr_reader :skip_sync

    sig { returns(Billing::PlanSubscription) }
    def call
      new_plan_sub = Billing::PlanSubscription.new(**new_plan_subscription_params)

      unless new_plan_sub.save
        errors = new_plan_sub.errors.full_messages.to_sentence
        raise UnprocessableError.new("Could not save subscription: #{errors}")
      end

      after_plan_subscription_saved
      new_plan_sub
    end

    protected

    sig { returns(T.nilable(Customer)) }
    def customer
      account.customer
    end

    sig { returns(Symbol) }
    def purpose
      :general
    end

    sig do
      returns({
        user: T.nilable(::Billing::Types::Account),
        customer: T.nilable(Customer),
        purpose: Symbol,
        skip_synchronize_later: T::Boolean
      })
    end
    def new_plan_subscription_params
      { user: account, customer: customer, purpose: purpose, skip_synchronize_later: skip_sync }
    end

    sig { void }
    def after_plan_subscription_saved
      account.reload_plan_subscription
    end
  end
end
