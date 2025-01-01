# typed: false
# frozen_string_literal: true

FactoryBot.define do
  factory :zuora_account, class: "Billing::Zuora::Account" do
    basicInfo { FactoryBot.attributes_for(:zuora_account_basic_info) }
    billingAndPayment { FactoryBot.attributes_for(:zuora_account_billing_and_payment) }
    metrics { FactoryBot.attributes_for(:zuora_account_metrics) }
    billToContact { FactoryBot.attributes_for(:zuora_account_contact) }
    success { true }

    skip_create

    initialize_with { new(attributes) }
  end

  factory :zuora_account_basic_info, class: "Billing::Zuora::Account::BasicInfo" do
    id { SecureRandom.alphanumeric(32) }
    accountNumber { SecureRandom.alphanumeric(32) }
    status { "Active" }

    trait :partner_customer do
      add_attribute(:PartnerCustomer__c) { "Yes" }
    end

    skip_create

    initialize_with { new(attributes) }
  end

  factory :zuora_account_billing_and_payment, class: "Billing::Zuora::Account::BillingAndPayment" do
    autoPay { true }
    billCycleDay { 1 }

    skip_create

    initialize_with { new(attributes) }
  end

  factory :zuora_account_metrics, class: "Billing::Zuora::Account::Metrics" do
    creditBalance { 0.0 }
    balance { 0.0 }

    skip_create

    initialize_with { new(attributes) }
  end

  factory :zuora_account_contact, class: "Billing::Zuora::Account::Contact" do
    id { SecureRandom.alphanumeric(32) }

    skip_create

    initialize_with { new(attributes) }
  end
end
