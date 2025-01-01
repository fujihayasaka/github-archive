# typed: strict
# frozen_string_literal: true

# PORO that supports translating our domain idea of separating funds via manual payments
# with Zuora's data on invoices that are currently due.
module Billing
  class ManualPayment
    include GitHub::Memoizer


    sig { returns(::Billing::Types::Account) }
    attr_reader :target

    # target - billable entity (User/Org/Business) making the manual credit card payment
    sig { params(target: ::Billing::Types::Account, purpose: T.nilable(Symbol)).void }
    def initialize(target:, purpose: nil)
      @target  = target
      @purpose = purpose
    end

    # Get the amount due, optionally narrowed by specific purpose
    #
    # purpose - Optional Symbol purpose of the payment (e.g. :general or :sponsors)
    #
    # Returns a Billing::Money instance
    sig { params(purpose: T.nilable(Symbol)).returns(Billing::Money) }
    def balance_due(purpose: nil)
      invoices = if purpose
        invoices_due_for_purpose(purpose)
      else
        invoices_due
      end

      sum_in_dollars = invoices.sum(&:balance)
      Billing::Money.new(sum_in_dollars * 100)
    end

    # Get the Zuora invoice numbers for a specific purpose
    #
    # purpose - Symbol purpose of the payment relating to PlanSubscription purpose (e.g. :general or :sponsors)
    #
    # Returns an Array of String Zuora invoice numbers (e.g. ["INV001", "INV002"])
    sig { params(purpose: T.nilable(Symbol)).returns(T::Array[String]) }
    def invoice_numbers(purpose:)
      invoices_due_for_purpose(purpose).map(&:invoice_number)
    end

    # Does this manual payment require multiple separate payments due to our Zuora configuration?
    #
    # Sponsorships and other GitHub items require different payment gateways in order to separate funds.
    #
    # Returns a Boolean
    sig { returns(T::Boolean) }
    def requires_separate_payments?
      balance_due(purpose: :sponsors).positive? && balance_due(purpose: :general).positive?
    end

    # Payment due date
    #
    # Returns a Date or nil
    sig { returns(T.nilable(Date)) }
    def due_date
      target.manual_payment_due_date&.to_date
    end

    # Purpose of the payment
    #
    # Returns a Symbol (:sponsors or :general)
    sig { returns(T.nilable(Symbol)) }
    def purpose
      return @purpose if @purpose.present?

      return nil unless balance_due.positive?
      return nil if requires_separate_payments?

      balance_due(purpose: :sponsors).positive? ? :sponsors : :general
    end

    sig { returns(T::Boolean) }
    def single_payment?
      purpose.present?
    end

    private

    sig { returns(T::Array[Billing::Zuora::Invoice]) }
    memoize def invoices_due
      return [] unless GitHub.billing_enabled?

      zuora_account_id = target.customer&.zuora_account_id
      return [] unless zuora_account_id.present?

      Billing::Zuora::Invoice.open_invoices_for_account(zuora_account_id, posted_only: true)
    end

    sig { params(purpose: T.nilable(Symbol)).returns(T::Array[T.untyped]) }
    def invoices_due_for_purpose(purpose)
      return invoices_due unless purpose.present?

      invoices_due.select do |invoice|
        subscription_number = invoice.subscription_number_from_billable_line_items
        next if subscription_number.nil?

        purpose_for(subscription_number: subscription_number) == purpose
      end
    end

    sig { returns(ActiveRecord::Associations::CollectionProxy) }
    memoize def plan_subscriptions
      target.plan_subscriptions
    end

    sig { params(subscription_number: String).returns(Symbol) }
    def purpose_for(subscription_number:)
      purpose = purpose_by_subscription_number[subscription_number]
      return purpose if purpose.present?

      purpose = T.must(Billing::Zuora::Subscription.find(subscription_number)).purpose
      purpose_by_subscription_number[subscription_number] = purpose

      purpose
    end

    sig { returns(T::Hash[String, Symbol]) }
    def purpose_by_subscription_number
      @purpose_by_subscription_number ||= T.let(plan_subscriptions.each_with_object({}) do |subscription, hsh|
        hsh[subscription.zuora_subscription_number] = subscription.purpose.to_sym
      end, T.nilable(T::Hash[String, Symbol]))
    end
  end
end
