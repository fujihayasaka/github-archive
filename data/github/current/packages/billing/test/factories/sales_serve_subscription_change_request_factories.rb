# typed: false
# frozen_string_literal: true

FactoryBot.define do
  factory :sales_serve_subscription_change_request, class: "Billing::SalesServeSubscriptionChangeRequest" do
    customer { create(:customer, :zuora, :invoiced, term_length: 12) }
    actor { create(:user) }
    zuora_subscription_number { "A-S#{SecureRandom.hex(6)}" }

    factory :sales_serve_subscription_change_request_with_items do
      transient do
        items_count { 2 }
      end

      after(:create) do |change_request, context|
        create_list(:sales_serve_subscription_change_request_item, context.items_count, change_request: change_request)
        # after_commit somehow inteferes with the way associations are loaded.
        change_request.reload
      end
    end
  end
end
