# typed: strict
# frozen_string_literal: true

module Customer::SponsorsDependency
  extend ActiveSupport::Concern
  extend T::Helpers
  extend T::Sig

  requires_ancestor { Customer }

  included do
    T.bind(self, T.class_of(Customer))

    has_one :sponsors_plan_subscription, -> { sponsors_purpose }, class_name: "Billing::PlanSubscription"
  end

  MINIMUM_INVOICE_AMOUNT_IN_CENTS = T.let(500_000, Integer)

  # Public: Check if this customer has a low amount of money left in their credit balance that's used to fund their
  # sponsorships, where "low" is an arbitrary amount that we decide. Only applicable for sponsorship-specific
  # Zuora accounts (Customer purpose=sponsors) and only when GitHub Sponsors is enabled.
  sig { returns T::Boolean }
  def low_sponsorship_credit_balance?
    return false unless GitHub.sponsors_enabled?
    return false unless sponsors_purpose?
    balance_in_usd = (credit_balance || Billing::Money.zero).exchange_to("USD")
    balance_in_usd.cents < MINIMUM_INVOICE_AMOUNT_IN_CENTS
  end
end
