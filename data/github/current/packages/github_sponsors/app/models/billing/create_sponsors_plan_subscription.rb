# typed: strict
# frozen_string_literal: true

module Billing
  # Public: A Plain Old Ruby Object (PORO) used for creating a plan subscription
  # representing a subscription for sponsorship purchases
  class CreateSponsorsPlanSubscription < CreatePlanSubscription
    include GitHub::Memoizer

    # account - The User or Organization or Business who will be purchasing sponsorships
    # skip_sync - A Boolean representing whether we should attempt to sync
    #             the new plan subscription to Zuora
    sig { params(account: Billing::Types::Account, skip_sync: T::Boolean).returns(Billing::PlanSubscription) }
    def self.call(account:, skip_sync: false)
      new(account: account, skip_sync: skip_sync).call
    end

    private

    sig { override.returns(T.nilable(Customer)) }
    memoize def customer
      account.sponsors_customer || super
    end

    sig { override.returns Symbol }
    def purpose
      :sponsors
    end

    sig do
      override.returns({
        user: T.nilable(::Billing::Types::Account),
        customer: T.nilable(Customer),
        purpose: Symbol,
        skip_synchronize_later: T::Boolean
      })
    end
    def new_plan_subscription_params
      result = super
      if account.business?
        result[:user] = nil
      end
      result
    end

    sig { override.void }
    def after_plan_subscription_saved
      account.try(:reload_sponsors_plan_subscription)
    end
  end
end
