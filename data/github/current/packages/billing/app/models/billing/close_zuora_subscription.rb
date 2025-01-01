# typed: strict
# frozen_string_literal: true

module Billing
  # Closes down a Zuora subscription by cancelling the subscription in Zuora
  # and making necessary financial adjustments
  class CloseZuoraSubscription
    extend T::Sig

    include GitHub::Memoizer

    # Public: Close down a Zuora subscription
    #
    sig do
      params(
        zuora_subscription_number: T.nilable(String),
        plan_subscription: T.nilable(Billing::PlanSubscription),
        collect_payment: T.nilable(T::Boolean)
      ).returns(GitHub::Billing::Result)
    end
    def self.perform(
      zuora_subscription_number:,
      plan_subscription: nil,
      collect_payment: false
    )
      new(
        zuora_subscription_number: zuora_subscription_number,
        plan_subscription: plan_subscription,
        collect_payment: collect_payment
      ).perform
    end

    # Initialize a new CloseZuoraSubscription
    #
    # zuora_subscription_number - The zuora subscription number of the subscription to be cancelled
    # plan_subscription - The plan subscription to be closed can be nil.
    #   If the plan subscription is present, the PlanSubscription::Synchronizer will take care of
    #   cancelling the subscription and nullifying the values in plan_subscription
    # collect_payment - Boolean indicating whether to collect payment on the subscription balance
    #   instead of immediately zeroing out the balance and invoices. Defaults to false.
    sig do
      params(
        zuora_subscription_number: T.nilable(String),
        plan_subscription: T.nilable(Billing::PlanSubscription),
        collect_payment: T.nilable(T::Boolean),
      ).void
    end
    def initialize(
      zuora_subscription_number:,
      plan_subscription:,
      collect_payment: false
    )
      @zuora_subscription_number = zuora_subscription_number
      @plan_subscription         = plan_subscription
      @collect_payment           = collect_payment
    end

    # Public: Close down a Zuora subscription
    sig { returns(GitHub::Billing::Result) }
    def perform
      return GitHub::Billing::Result.success if zuora_subscription_number.blank? && plan_subscription.blank?

      ActiveRecord::Base.connected_to(role: :writing) do
        cancel_result = cancel_subscription
        return cancel_result unless cancel_result.success?

        collect_outstanding_payment if collect_payment

        result = zero_out_subscription_balance_and_invoices
        reset_user_billed_on

        result
      end
    end

    private

    sig { returns(T.nilable(Billing::PlanSubscription)) }
    attr_reader :plan_subscription
    sig { returns(T.nilable(String)) }
    attr_reader :zuora_subscription_number
    sig { returns(T.nilable(T::Boolean)) }
    attr_reader :collect_payment
    delegate :user, to: :plan_subscription, allow_nil: true

    # Private: Collect payment on the subscription balance.
    #
    # Returns GitHub::Billing::Result
    sig { returns(GitHub::Billing::Result) }
    def collect_outstanding_payment
      begin
        return GitHub::Billing::Result.success if plan_subscription&.customer.nil?
        customer = plan_subscription&.customer
        return GitHub::Billing::Result.success if customer.nil?

        result = GitHub.zuorest_client.create_invoice_collect \
          accountKey: customer.zuora_account_id
        GitHub::Billing::Result.from_zuora(result)
      rescue Zuorest::HttpError, Faraday::Error => e
        Failbot.report!(e, app: "github-zuora")
      end
    end

    # Internal: Mark the Zuora subscription as cancelled
    #
    # Returns GitHub::Billing::Result
    sig { returns(GitHub::Billing::Result) }
    def cancel_subscription
      plan_subscription = self.plan_subscription
      if plan_subscription.present?
        Billing::PlanSubscription::Synchronizer.cancel(plan_subscription)
      else
        zuora_subscription = ::Billing::Zuora::Subscription.find(zuora_subscription_number)
        unless zuora_subscription
          Failbot.report(
            ::Billing::Zuora::Subscription::NotFoundError.new("Subscription not found for #{zuora_subscription_number} when cancelling subscription"),
          )
          return GitHub::Billing::Result.success
        end

        return GitHub::Billing::Result.success if zuora_subscription.cancelled?

        result = zuora_subscription.cancel
        GitHub::Billing::Result.from_zuora(result)
      end
    end

    # Internal: Destroy any manual dunning records for the user if this is their general-purpose customer account
    sig { returns(T.nilable(::Billing::ManualDunningPeriod)) }
    def destroy_general_purpose_dunning_record
      return unless plan_subscription && user
      return unless customer&.general_purpose?

      user.manual_dunning_period&.destroy
    end

    sig { returns(GitHub::Billing::Result) }
    def zero_out_subscription_balance_and_invoices
      plan_subscription&.update(balance_in_cents: 0)
      destroy_general_purpose_dunning_record
      return GitHub::Billing::Result.success if zuora_subscription_number.blank?
      ::Billing::Zuora::ZeroOutInvoices.for_subscription(T.must(zuora_subscription_number))
    end

    # Private: reset the billed on date if a user does not have other zuora subscriptions
    #
    # This ensures that a user can create a new subscription in the future with
    # a predictable billing date
    sig { returns(T.nilable(T::Boolean)) }
    def reset_user_billed_on
      customer = self.customer
      return unless customer && user

      has_other_external_subscription = customer.plan_subscriptions
        .where.not(id: T.must(plan_subscription).id)
        .any?(&:has_external_subscription?)

      # Use update_columns to skip ActiveRecord callbacks
      user.update_columns(billed_on: nil) unless has_other_external_subscription
    end

    sig { returns(T.nilable(Customer)) }
    memoize def customer
      plan_subscription&.customer
    end
  end
end
