# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::SubscribableTest < GitHub::BillingTestCase
  context ".from_tracking_ids" do
    test "does not resolve classes without zuora tracking enabled" do
      user = create(:user)
      class_name = user.class.name
      components = ["0", class_name.length, ":", class_name, user.id]
      hacked_tracking_id = Base64.strict_encode64(components.join)

      results = Billing::Subscribable.from_tracking_ids([hacked_tracking_id])
      assert_nil results[hacked_tracking_id]
    end

    test "encoded tracking ID can be resolved" do
      sponsors_tier = create(:sponsors_tier)
      tracking_id = sponsors_tier.zuora_tracking_id

      results = Billing::Subscribable.from_tracking_ids([tracking_id])
      assert_equal sponsors_tier, results[tracking_id]
    end
  end

  context ".from_product_rpc_ids" do
    test "does not match zuora product rate plan charge id for a listing which does not exist for test_all_features" do
      product_uuid = create(:billing_product_uuid, :marketplace_listing_plan)
      product_rpc_id = product_uuid.zuora_product_rate_plan_charge_ids[:flat]

      results = Billing::Subscribable.from_product_rpc_ids([product_rpc_id])
      refute_nil results[product_rpc_id]
    end if TestEnv.test_all_features?

    test "does not match zuora product rate plan charge id for a listing which does not exist unless test_all_features" do
      product_uuid = create(:billing_product_uuid, :marketplace_listing_plan)
      product_rpc_id = product_uuid.zuora_product_rate_plan_charge_ids[:flat]

      results = Billing::Subscribable.from_product_rpc_ids([product_rpc_id])
      assert(results)
    end unless TestEnv.test_all_features?

    test "matches zuora product rate plan charge id with a listing plan" do
      product_uuid = create(:billing_product_uuid, :marketplace_listing_plan)
      listing_plan = Marketplace::ListingPlan.find_by(product_uuid.product_key)
      product_rpc_id = product_uuid.zuora_product_rate_plan_charge_ids[:flat]
      results = Billing::Subscribable.from_product_rpc_ids([product_rpc_id])
      assert_equal listing_plan, results[product_rpc_id]
    end

    # see https://github.com/github/sponsors/issues/4747
    test "does not lookup products when passed an empty array" do
      assert_query_count_per_table({ product_uuids: 0 }) do
        Billing::Subscribable.from_product_rpc_ids([])
      end
    end
  end
end
