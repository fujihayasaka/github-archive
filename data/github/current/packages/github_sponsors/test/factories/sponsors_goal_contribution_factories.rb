# typed: true
# frozen_string_literal: true

FactoryBot.define do
  T.bind(self, T.untyped)

  factory :sponsors_goal_contribution do
    goal factory: :sponsors_goal
    tier factory: :sponsors_tier

    sponsor do
      create(:credit_card_user,
        plan_subscription: create(:billing_plan_subscription),
        plan: GitHub::Plan.free_with_addons,
      )
    end
  end
end
