# typed: false
# frozen_string_literal: true

FactoryBot.define do
  factory :zoura_payment_authorization_create_response, class: "Billing::Zuora::PaymentAuthorization::CreateResponse" do
    success { true }
    result_code { "0" }
    result_message { "Approved" }
    transaction_id { SecureRandom.hex }
    gateway_order_id { SecureRandom.hex }

    trait :failure do
      success { false }
      process_id { SecureRandom.hex }
      reasons do
        [{
          "code" => "402",
          "message" => 'gatewayErrorCode="402", gatewayErrorMessage="[card/declined] Card declined"'
        }]
      end
      request_id { SecureRandom.uuid }
    end

    skip_create

    initialize_with { new(attributes) }
  end
end
