# typed: false
# frozen_string_literal: true

FactoryBot.define do
  factory :sales_serve_subscription_change_request_item, class: "Billing::SalesServeSubscriptionChangeRequestItem" do
    product_rate_plan_charge_id { SecureRandom.hex(16) }
    status { :pending }
    change_type { :renewal }
    start_date { 1.month.from_now }
    end_date { start_date ? start_date + 1.year : nil }
    change_request { association :sales_serve_subscription_change_request }
  end
end
