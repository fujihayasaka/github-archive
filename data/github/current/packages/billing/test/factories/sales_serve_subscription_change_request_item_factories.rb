# typed: false
# frozen_string_literal: true

FactoryBot.define do
  factory :sales_serve_subscription_change_request_item, class: "Billing::SalesServeSubscriptionChangeRequestItem" do
    product_rate_plan_charge_id { SecureRandom.hex(16) }
    status { :pending }
    change_type { :renewal }
    start_date { 1.month.from_now.to_date }
    end_date { start_date ? start_date + 1.year : nil }
    price { 10 }
    quantity { 101 }
    change_request { association :sales_serve_subscription_change_request }

    trait :github_enterprise do
      product_rate_plan_charge_id { GitHub.zuora_sales_serve_ghe_product_charge_ids.first }
    end

    trait :github_advanced_security do
      product_rate_plan_charge_id { GitHub.zuora_sales_serve_ghas_product_charge_ids.first }
    end
  end
end
