# typed: true
# frozen_string_literal: true

FactoryBot.define do
  T.bind(self, T.untyped)

  factory :sponsorship_match_ban do
    sponsor { create(:credit_card_user, plan_subscription: create(:billing_plan_subscription), plan: GitHub::Plan.free_with_addons) }
    sponsorable { create(:user, :sponsorable) }
  end
end
