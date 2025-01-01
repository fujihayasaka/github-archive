# typed: true
# frozen_string_literal: true

require "test_helper"
require "github/memory_dogstats_d"

class Billing::CancelInAppPurchasedSubscriptionItemJobTest < GitHub::TestCase
  fixtures do
    @subscription_item = create(:billing_subscription_item, :iap)
  end

  setup do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

    @bad_cancel_result = Billing::Public::SubscriptionItems::ResultStruct.new(
      subscription_item: @subscription_item,
      result: Billing::Public::ResultStruct.new(
        success: false,
        errors: ["ohnoez, billing sez this sub cant be cancelled or somethingz"]
      )
    )
  end

  test "cancels the subscription item" do
    assert @subscription_item.active?

    Billing::CancelInAppPurchasedSubscriptionItemJob.perform_now(@subscription_item.id)

    assert @subscription_item.reload.cancelled?
  end

  test "increments Datadog when successful" do
    Billing::CancelInAppPurchasedSubscriptionItemJob.perform_now(@subscription_item.id)

    assert_equal 1, GitHub.dogstats.increments("billing.cancel_in_app_purchased_subscription_item_job", tags: ["cancelled:true"]).length
  end

  test "increments Datadog when unsuccessful" do
    Billing::SubscriptionItem.any_instance.stubs(:cancel!).returns(@bad_cancel_result)

    Billing::CancelInAppPurchasedSubscriptionItemJob.perform_now(@subscription_item.id)

    assert_equal 1, GitHub.dogstats.increments("billing.cancel_in_app_purchased_subscription_item_job", tags: ["cancelled:false"]).length
  end

  test "reports an error to Failbot when unsuccessful" do
    Billing::SubscriptionItem.any_instance.stubs(:cancel!).returns(@bad_cancel_result)

    Billing::CancelInAppPurchasedSubscriptionItemJob.perform_now(@subscription_item.id)

    needle = Failbot.reports.last
    assert_match "Failed to cancel in-app purchased subscription item.", Failbot.exception_message_from_hash(needle)
    assert_equal "Billing::CancelInAppPurchasedSubscriptionItemJob::CancellationError", Failbot.exception_classname_from_hash(needle)
  end
end
