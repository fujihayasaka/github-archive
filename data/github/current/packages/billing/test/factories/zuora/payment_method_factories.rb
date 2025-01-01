# typed: false
# frozen_string_literal: true

FactoryBot.define do
  factory :zuora_payment_method, class: "Billing::Zuora::PaymentMethod" do
    add_attribute(:Id) { SecureRandom.alphanumeric(32) }

    add_attribute(:CreditCardMaskNumber) { "************1234" }
    add_attribute(:CreditCardExpirationMonth) { 12 }
    add_attribute(:CreditCardExpirationYear) { 2023 }
    add_attribute(:CreditCardType) { "Visa" }
    add_attribute(:Type) { "CreditCard" }
    add_attribute(:CreditCardPostalCode) { "12345" }

    trait :paypal do
      add_attribute(:CreditCardMaskNumber) { nil }
      add_attribute(:CreditCardExpirationMonth) { nil }
      add_attribute(:CreditCardExpirationYear) { nil }
      add_attribute(:CreditCardType) { nil }
      add_attribute(:Type) { "PayPal" }
      add_attribute(:CreditCardPostalCode) { nil }
    end

    skip_create

    initialize_with do
      new(attributes.with_indifferent_access)
    end
  end
end
