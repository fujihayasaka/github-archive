# typed: false
# frozen_string_literal: true

FactoryBot.define do
  factory :zuora_invoice_item, class: "Billing::Zuora::InvoiceItem" do
    id { SecureRandom.alphanumeric(32) }
    chargeAmount { Faker::Invoice.amount_between(from: 1, to: 200) }
    unitOfMeasure { "Each" }

    trait :zero_charge do
      chargeAmount { 0.0 }
    end

    skip_create

    initialize_with { new(attributes.with_indifferent_access) }
  end
end
