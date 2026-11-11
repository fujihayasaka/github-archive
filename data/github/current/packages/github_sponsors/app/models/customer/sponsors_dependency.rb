# typed: strict
# frozen_string_literal: true

module Customer::SponsorsDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { Customer }

  included do
    T.bind(self, T.class_of(Customer))

    has_one :sponsors_plan_subscription, -> { sponsors_purpose }, class_name: "Billing::PlanSubscription"
  end

  MINIMUM_INVOICE_AMOUNT_IN_CENTS = T.let(500_000, Integer)
  ZERO_BALANCE_THRESHOLD_DAYS = T.let(90.days, ActiveSupport::Duration)

  # Public: Returns true if the sponsorship credit balance is low. Uses the projected zero balance date
  # from active recurring sponsorships: true when that date is within ZERO_BALANCE_THRESHOLD_DAYS,
  # false when sponsorships exist but the date can't be calculated (long runway). Falls back to
  # balance < MINIMUM_INVOICE_AMOUNT_IN_CENTS when there are no active sponsorships.
  sig { params(sponsor: T.nilable(User)).returns(T::Boolean) }
  def low_sponsorship_credit_balance?(sponsor: nil)
    return false unless GitHub.sponsors_enabled?
    return false unless sponsors_purpose?
    return false unless sponsor

    sponsorships = T.unsafe(sponsor.active_sponsorships_as_sponsor_relation).recurring
    current_balance = (credit_balance || Billing::Money.zero).exchange_to("USD")

    # Calculate the zero balance date based on active recurring sponsorships
    calculator = Sponsors::ZeroBalanceDateCalculator.new(
      sponsorships: sponsorships,
      current_balance: current_balance,
      customer: self,
    )
    zero_balance_date = calculator.zero_balance_date

    # If we can calculate a zero balance date, check if it's within the threshold
    if zero_balance_date
      threshold_date = zero_balance_date - ZERO_BALANCE_THRESHOLD_DAYS
      GitHub::Billing.today >= threshold_date
    else
      if sponsorships.exists? && !calculator.calculable?
        false
      else
        current_balance.cents < MINIMUM_INVOICE_AMOUNT_IN_CENTS
      end
    end
  end
end
