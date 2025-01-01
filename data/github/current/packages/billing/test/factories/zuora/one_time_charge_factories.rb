# typed: false
# frozen_string_literal: true

FactoryBot.define do
  factory :zuora_one_time_charge, class: "Billing::Zuora::OneTimeCharge", parent: :zuora_rate_plan_charge do
  end
end
