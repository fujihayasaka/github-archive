# typed: true
# frozen_string_literal: true

class Marketplace::StubbedResponse
  def self.organization_subscription_item
    {
      url: "https://api.github.com/orgs/github",
      type: "Organization",
      id: 4,
      login: "github",
      email: nil,
      organization_billing_email: "billing@github.com",
      marketplace_pending_change: nil,
      marketplace_purchase: {
        billing_cycle: "monthly",
        next_billing_date: 1.month.from_now.beginning_of_month,
        on_free_trial: false,
        free_trial_ends_on: nil,
        unit_count: nil,
        updated_at: 1.week.ago.beginning_of_week,
        plan: pro_plan,
      },
    }.with_indifferent_access
  end

  def self.user_subscription_item
    {
      url: "https://api.github.com/users/test",
      type: "User",
      id: 2,
      login: "test",
      email: "test@example.com",
      marketplace_pending_change: {
        id: 12,
        unit_count: 8,
        plan: hobby_plan,
        effective_date: 1.month.from_now.beginning_of_month,
      },
      marketplace_purchase: {
        billing_cycle: "monthly",
        next_billing_date: 1.month.from_now.beginning_of_month,
        on_free_trial: false,
        free_trial_ends_on: nil,
        unit_count: 10,
        updated_at: 1.week.ago.beginning_of_week,
        plan: hobby_plan,
      },
    }.with_indifferent_access
  end

  def self.subscription_items
    [organization_subscription_item, user_subscription_item]
  end

  def self.free_plan
    {
      url: "https://api.github.com/marketplace_listing/plans/7",
      accounts_url: "https://api.github.com/marketplace_listing/plans/7/accounts",
      id: 7,
      number: 1,
      name: "Free",
      description: "A free CI solution",
      monthly_price_in_cents: 0,
      yearly_price_in_cents: 0,
      price_model: "FREE",
      has_free_trial: false,
      state: "published",
      unit_name: nil,
      bullets: [
        "This is the first bullet of the free plan",
        "This is the second bullet of the free plan",
      ],
    }.with_indifferent_access
  end

  def self.hobby_plan
    {
      url: "https://api.github.com/marketplace_listing/plans/8",
      accounts_url: "https://api.github.com/marketplace_listing/plans/8/accounts",
      id: 8,
      number: 2,
      name: "Hobby",
      description: "A hobby-grade CI solution",
      monthly_price_in_cents: 1099,
      yearly_price_in_cents: 11870,
      has_free_trial: false,
      price_model: "PER_UNIT",
      state: "published",
      unit_name: "seat",
      bullets: [
        "This is the first bullet of the Hobby plan",
        "This is the second bullet of the Hobby plan",
      ],
    }.with_indifferent_access
  end

  def self.pro_plan
    {
      url: "https://api.github.com/marketplace_listing/plans/9",
      accounts_url: "https://api.github.com/marketplace_listing/plans/9/accounts",
      id: 9,
      number: 3,
      name: "Pro",
      description: "A professional-grade CI solution",
      monthly_price_in_cents: 1099,
      yearly_price_in_cents: 11870,
      has_free_trial: false,
      price_model: "FLAT_RATE",
      state: "published",
      unit_name: nil,
      bullets: [
        "This is the first bullet of the Pro plan",
        "This is the second bullet of the Pro plan",
      ],
    }.with_indifferent_access
  end

  def self.plans
    [free_plan, hobby_plan, pro_plan]
  end

  def self.organization_purchase
    {
      billing_cycle: "monthly",
      next_billing_date: 1.month.from_now.beginning_of_month,
      on_free_trial: false,
      free_trial_ends_on: nil,
      unit_count: nil,
      updated_at: 1.week.ago.beginning_of_week,
      account: {
        login: "github",
        id: 4,
        url: "https://api.github.com/orgs/github",
        email: nil,
        organization_billing_email: "billing@github.com",
        type: "Organization",
      },
      plan: pro_plan,
    }.with_indifferent_access
  end

  def self.user_purchase
    {
      billing_cycle: "monthly",
      next_billing_date: 1.month.from_now.beginning_of_month,
      on_free_trial: false,
      free_trial_ends_on: nil,
      unit_count: nil,
      updated_at: 1.week.ago.beginning_of_week,
      account: {
        login: "test",
        id: 2,
        url: "https://api.github.com/users/test",
        email: "test@example.com",
        type: "User",
      },
      plan: free_plan,
    }.with_indifferent_access
  end

  def self.purchases
    [organization_purchase, user_purchase]
  end
end
