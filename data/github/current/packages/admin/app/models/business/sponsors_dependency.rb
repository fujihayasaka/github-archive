# typed: strict
# frozen_string_literal: true

# Creating empty associations to ensure that code paths that refer to either User or Business do not fail
module Business::SponsorsDependency
  extend ActiveSupport::Concern
  extend T::Sig
  extend T::Helpers

  requires_ancestor { Business }

  included do
    delegate :reload_sponsors_plan_subscription, to: :customer, allow_nil: true
  end

  sig { returns(T.nilable(Customer)) }
  def sponsors_customer
    nil
  end

  sig { returns(T.nilable(Billing::PlanSubscription)) }
  def sponsors_plan_subscription
    customer&.sponsors_plan_subscription
  end

  sig { returns(ActiveRecord::Relation) }
  def active_sponsorships_as_sponsor_relation
    Sponsorship.none
  end

  sig { returns(T::Boolean) }
  def has_valid_payment_method_for_sponsorships?
    has_credit_card? && payment_method.valid_payment_token?
  end

  sig { returns(T::Boolean) }
  def sponsors_invoiced?
    false
  end

  sig { returns(T::Boolean) }
  def has_paypal_account_for_sponsors?
    has_paypal_account?
  end

  sig { returns(T::Boolean) }
  def yearly_sponsors_plan?
    yearly_plan?
  end

  sig { returns(Integer) }
  def customer_bill_cycle_day_for_sponsorships
    customer_bill_cycle_day
  end

  sig { returns(Date) }
  def next_sponsors_billing_date
    T.must(next_billing_date)
  end

  sig { returns(String) }
  def sponsors_plan_duration
    plan_duration
  end

  # Sponsorships created by self-serve enterprises are not eligible to be matched by GitHub
  sig { params(sponsorable: T.any(User, Organization)).returns(T::Boolean) }
  def eligible_for_sponsorship_match?(sponsorable:)
    false
  end

  sig { returns(T::Array[Billing::SubscriptionItem]) }
  def self_serve_sponsors_subscription_items
    return [] unless self_serve_payment? && sponsors_plan_subscription.present?

    T.must(sponsors_plan_subscription).active_subscription_items
      .subscribable_SponsorsTier
      .includes(:organization)
      .to_a
  end

  sig { returns(T::Hash[Organization, T::Array[Billing::SubscriptionItem]]) }
  def active_organizations_sponsorships
    self_serve_sponsors_subscription_items.each_with_object({}) do |item, hash|
      hash[item.organization] ||= []
      hash[item.organization] << item
    end
  end

  sig { returns(T::Boolean) }
  def external_sponsors_subscription?
    !!sponsors_plan_subscription&.has_external_subscription?
  end
end
