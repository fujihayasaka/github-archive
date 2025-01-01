# typed: false
# frozen_string_literal: true

FactoryBot.define do
  factory :sales_serve_subscription_change_request, class: "Billing::SalesServeSubscriptionChangeRequest" do
    customer { create(:customer) }
    zuora_subscription_id { SecureRandom.hex(16) }

    factory :sales_serve_subscription_change_request_with_items do
      transient do
        items_count { 2 }
      end

      after(:create) do |change_request, context|
        create_list(:sales_serve_subscription_change_request_item, context.items_count, change_request: change_request)
      end
    end
  end
end
