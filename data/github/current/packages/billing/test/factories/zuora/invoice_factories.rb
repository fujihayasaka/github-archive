# typed: false
# frozen_string_literal: true

FactoryBot.define do
  factory :zuora_invoice, class: "Billing::Zuora::Invoice" do
    id { SecureRandom.alphanumeric(32) }
    sequence(:invoiceNumber) { |n| "INV-#{n}" }

    accountId { SecureRandom.alphanumeric(32) }

    amount { Faker::Invoice.amount_between(from: 1, to: 200) }
    refund { 0.0 }
    taxAmount { 0.0 }
    paymentAmount { 0.0 }
    creditBalanceAdjustmentAmount { 0.0 }
    balance { amount }

    invoiceDate { Date.today.to_s }
    dueDate { Date.today.to_s }

    status { "Posted" }

    createdById { SecureRandom.alphanumeric(32) }

    success { true }

    body { Base64.encode64("Invoice PDF contents") }

    trait :draft do
      status { "Draft" }
    end

    trait :cancelled do
      status { "Cancelled" }
    end

    add_attribute(:SuppressFromCustomerView__c) { "No" }

    trait :suppress_from_customer_view do
      add_attribute(:SuppressFromCustomerView__c) { "Yes" }
    end

    trait :unpaid do
      balance { 100.0 }
    end

    trait :paid do
      balance { 0.0 }
    end

    trait :past_due do
      dueDate { 1.month.ago.to_s }
    end

    skip_create

    initialize_with { new(attributes[:id], attributes.with_indifferent_access) }
  end
end
