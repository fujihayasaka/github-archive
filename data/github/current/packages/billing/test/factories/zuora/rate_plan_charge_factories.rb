# typed: false
# frozen_string_literal: true

FactoryBot.define do
  factory :zuora_rate_plan_charge, class: "Billing::Zuora::RatePlanCharge" do
    id                      { SecureRandom.alphanumeric(32) }
    originalChargeId        { SecureRandom.alphanumeric(32) }
    productRatePlanChargeId { SecureRandom.alphanumeric(32) }
    number                  { "C-#{SecureRandom.hex(4)}" }
    name                    { Faker::Lorem.sentence }
    currency                { "USD" }
    price                   { Faker::Commerce.price }
    discountAmount          { 0 }
    billingPeriod           { "Month" }
    quantity                { (1..10).to_a.sample }

    active
    recurring

    trait :active do
      effectiveEndDate        { nil }
      effectiveStartDate      { Date.today.to_s }
      processedThroughDate    { Date.today.to_s }
      chargedThroughDate      { 1.month.from_now.to_date.to_s }
    end

    trait :inactive do
      effectiveEndDate     { 1.month.ago.to_date.to_s }
      effectiveStartDate   { 1.year.ago.to_date.to_s }
      processedThroughDate { 1.month.ago.to_date.to_s }
      chargedThroughDate   { 1.month.ago.to_date.to_s }
    end

    trait :recurring do
      type { "Recurring" }
    end

    trait :one_time do
      type { "OneTime" }
    end

    trait :usage do
      type { "Usage" }
    end

    trait :metered_ghec do
      add_attribute(:IsMetered__c) { "true" }
    end

    skip_create

    initialize_with { new(attributes) }
  end
end
