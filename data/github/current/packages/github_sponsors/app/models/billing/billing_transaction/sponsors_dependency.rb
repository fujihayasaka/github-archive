# typed: true
# frozen_string_literal: true

module Billing::BillingTransaction::SponsorsDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { Billing::BillingTransaction }

  include GitHub::Memoizer

  included do
    T.bind(self, T.class_of(Billing::BillingTransaction))

    has_many :sponsorship_stripe_radar_risk_scores, inverse_of: :billing_transaction

    # Public: Billing Transactions that are associated with a given sponsors plan subscription
    scope :for_sponsors_plan_subscription, -> (sponsors_plan_subscription_id) do
      where(plan_subscription_id: sponsors_plan_subscription_id)
    end
  end

  sig { returns ActiveRecord::Relation }
  def sponsors_line_items
    line_items.sponsorships
  end

  private

  sig { returns Integer }
  def sponsors_line_item_amount
    sponsors_line_items.sum(:amount_in_cents)
  end

  sig do
    params(sponsors_line_items: T.any(T::Array[Billing::BillingTransaction::LineItem], ActiveRecord::Relation)).void
  end
  def after_sponsorship_billable_line_items_created(sponsors_line_items:)
    if billable_business?
      instrument_self_serve_enterprise_sponsorships(sponsors_line_items: sponsors_line_items)
    elsif user.respond_to?(:instrument_sponsorship_payment_complete)
      sponsors_tiers = sponsors_line_items.map(&:subscribable).uniq
      return if sponsors_tiers.empty?

      # Do instrumentation after creating the line item, which reports the transaction to Sift, so that we can
      # accurately tell if this was the first payment for each sponsorship or not:
      T.unsafe(user).instrument_sponsorship_payment_complete(sponsors_tiers: sponsors_tiers)

      if user.sponsors_invoiced? && sponsors_tiers.any?(&:recurring?)
        zero_balance_date = T.unsafe(user).sponsors_zero_balance_date
        if zero_balance_date
          SponsorsLowCreditBalanceWarningJob.perform_later(sponsor: user, zero_balance_date: zero_balance_date)
        end
      end
    end
  end

  sig do
    params(sponsors_line_items: T.any(T::Array[Billing::BillingTransaction::LineItem], ActiveRecord::Relation)).void
  end
  def instrument_self_serve_enterprise_sponsorships(sponsors_line_items:)
    return if billable_entity.nil?
    return if sponsors_line_items.empty?

    sponsor_by_sponsor_id = T.let(Organization.where(id: sponsors_line_items.map(&:sponsor_id)).index_by(&:id),
      T::Hash[Integer, Organization])
    tiers_by_sponsor = sponsors_line_items.each_with_object({}) do |line_item, hash|
      sponsor = sponsor_by_sponsor_id[line_item.sponsor_id]
      if sponsor
        hash[sponsor] ||= Set.new
        hash[sponsor].add(line_item.subscribable)
      end
    end

    tiers_by_sponsor.each do |sponsor, sponsors_tiers|
      sponsor.instrument_sponsorship_payment_complete(sponsors_tiers: sponsors_tiers.to_a)
    end
  end
end
