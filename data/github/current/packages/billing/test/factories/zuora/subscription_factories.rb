# typed: false
# frozen_string_literal: true

FactoryBot.define do
  factory :zuora_subscription, class: "Billing::Zuora::Subscription" do
    id                    { SecureRandom.hex(16) }
    success               { true }
    accountId             { SecureRandom.uuid }
    accountNumber         { SecureRandom.hex(4) }
    subscriptionNumber    { SecureRandom.hex(4) }
    contractEffectiveDate { 1.week.ago.to_date.to_s }

    active
    with_rate_plans

    trait :active do
      status { "Active" }
    end

    trait :pending do
      contractEffectiveDate { 1.week.from_now.to_date.to_s }
    end

    trait :cancelled do
      status { "Cancelled" }
    end

    trait :suspended do
      status { "Suspended" }
    end

    trait :with_rate_plans do
      ratePlans { 2.times.map { attributes_for(:zuora_rate_plan, :with_rate_plan_charges) } }
    end

    skip_create

    initialize_with { new(attributes) }
  end
end
