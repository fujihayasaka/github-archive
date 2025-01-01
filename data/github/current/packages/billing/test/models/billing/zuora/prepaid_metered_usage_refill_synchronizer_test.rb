# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Zuora::PrepaidMeteredUsageRefillSynchronizerTest < GitHub::TestCase
  include GitHub::SalesServeZuoraWebhooksTestHelper

  setup do
    term_ends_on = GitHub::Billing.today + 1.year
    organization = create(:organization)
    @raw_subscription = find_subscription_response(
      id: "valid_subscription_id",
      subscription_number: "valid_subscription_number",
      organization_id: organization.id,
      account_id: "zuora_account_id",
      account_number: "zuora_account_number",
      plan_name: "business_plus",
      seats: 30,
      usage_refills_quantity: 50,
      data_packs: 70,
      start_date: Date.today,
      term_end_date: term_ends_on
    )
    @subscription = Billing::Zuora::SalesManagedSubscription.new(@raw_subscription)
    @expires_on = term_ends_on - 1.day

    @synchronizer = ::Billing::Zuora::PrepaidMeteredUsageRefillSynchronizer.new(
      @subscription,
      @expires_on
    )
  end

  test "syncs usage refills" do
    freeze_time do
      assert_difference -> { Billing::PrepaidMeteredUsageRefill.count } => 1 do
        @synchronizer.synchronize!
      end

      refill = Billing::PrepaidMeteredUsageRefill.last
      refill = T.must(refill)

      assert_equal @subscription.owner, refill.owner
      assert_equal 50_00, refill.amount_in_subunits
      assert_equal "USD", refill.currency_code
      assert_equal @expires_on, refill.expires_on
      assert refill.zuora_rate_plan_charge_id.present?
      assert refill.zuora_rate_plan_charge_number.present?
    end
  end

  test "does not create duplicate records if synchronized multiple times" do
    assert_difference -> { Billing::PrepaidMeteredUsageRefill.count } => 1 do
      @synchronizer.synchronize!
      @synchronizer.synchronize!
    end
  end

  test "does not create duplicate records even if the product rate plan charge ID changes in Zuora" do
    assert_difference -> { Billing::PrepaidMeteredUsageRefill.count } => 1 do
      @synchronizer.synchronize!
    end

    # Change rate plan chanrge ID to mimic what happens when a subscription is ammended
    @raw_subscription[:ratePlans].each do |rate_plan|
      rate_plan[:ratePlanCharges].each do |charge|
        if GitHub.zuora_metered_refill_rate_plan_charge_ids.include?(charge[:productRatePlanChargeId])
          charge[:id] = SecureRandom.hex
        end
      end
    end
    new_synchronizer = ::Billing::Zuora::PrepaidMeteredUsageRefillSynchronizer.new(
      Billing::Zuora::SalesManagedSubscription.new(@raw_subscription),
      @expires_on
    )

    assert_no_difference -> { Billing::PrepaidMeteredUsageRefill.count } do
      new_synchronizer.synchronize!
    end
  end

  test "does not remove refills when they are expired in Zuora" do
    assert_difference -> { Billing::PrepaidMeteredUsageRefill.count } => 1 do
      @synchronizer.synchronize!
    end

    # Change end date to make the refill expired
    @raw_subscription[:ratePlans].each do |rate_plan|
      rate_plan[:ratePlanCharges].each do |charge|
        if GitHub.zuora_metered_refill_rate_plan_charge_ids.include?(charge[:productRatePlanChargeId])
          charge[:effectiveEndDate] = charge[:effectiveStartDate]
        end
      end
    end
    new_synchronizer = ::Billing::Zuora::PrepaidMeteredUsageRefillSynchronizer.new(
      Billing::Zuora::SalesManagedSubscription.new(@raw_subscription),
      @expires_on
    )

    assert_no_difference -> { Billing::PrepaidMeteredUsageRefill.count } do
      new_synchronizer.synchronize!
    end
  end

  test "does not create a record if the rate plan charge is expired in Zuora" do
    # Change end date to make the refill expired
    @raw_subscription[:ratePlans].each do |rate_plan|
      rate_plan[:ratePlanCharges].each do |charge|
        if GitHub.zuora_metered_refill_rate_plan_charge_ids.include?(charge[:productRatePlanChargeId])
          charge[:effectiveEndDate] = charge[:effectiveStartDate]
        end
      end
    end

    assert_no_difference -> { Billing::PrepaidMeteredUsageRefill.count } do
      @synchronizer.synchronize!
    end
  end

  test "does not remove records that no longer exist in Zuora" do
    assert_difference -> { Billing::PrepaidMeteredUsageRefill.count } => 1 do
      @synchronizer.synchronize!
    end

    # Remove the rate plan charge for the refill
    @raw_subscription[:ratePlans].each do |rate_plan|
      rate_plan[:ratePlanCharges].delete_if do |charge|
        GitHub.zuora_metered_refill_rate_plan_charge_ids.include?(charge[:productRatePlanChargeId])
      end
    end
    new_synchronizer = ::Billing::Zuora::PrepaidMeteredUsageRefillSynchronizer.new(
      Billing::Zuora::SalesManagedSubscription.new(@raw_subscription),
      @expires_on
    )

    assert_no_difference -> { Billing::PrepaidMeteredUsageRefill.count } do
      new_synchronizer.synchronize!
    end
  end

  test "enqueues job to reset depleted credits notice when new refill is created" do
    assert_enqueued_with(job: Billing::ResetNoticesJob, args: ["depleted_prepaid_credits", @subscription.owner]) do
      @synchronizer.synchronize!
    end

    # does not enqueue job as it does not create refills on rerun
    assert_enqueued_jobs 0, only: Billing::ResetNoticesJob do
      @synchronizer.synchronize!
    end
  end if GitHub.billing_enabled?
end
