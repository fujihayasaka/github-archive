# typed: false
# frozen_string_literal: true

FactoryBot.define do
  factory :zuora_rate_plan, class: "Billing::Zuora::RatePlan" do
    id                { SecureRandom.uuid }
    productId         { SecureRandom.uuid }
    productName       { Faker::Lorem.sentence }
    productSku        { "hours" }
    productRatePlanId { SecureRandom.uuid }
    ratePlanName      { Faker::Lorem.sentence }
    ratePlanCharges   { [] }
    lastChangeType    { "Add" }

    trait :with_rate_plan_charges do
      ratePlanCharges { 2.times.map { attributes_for(:zuora_rate_plan_charge) } }
    end

    skip_create

    initialize_with { new(attributes) }
  end
end
