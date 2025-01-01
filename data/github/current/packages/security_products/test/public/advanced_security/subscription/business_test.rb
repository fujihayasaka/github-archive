# typed: true
# frozen_string_literal: true

require "test_helper"

class AdvancedSecurity::Public::Subscription::BusinessTest < GitHub::TestCase
  include AuditLog::IntegrationTestHelpers
  include DogstatsTestHelpers

  fixtures do
    @billing_plan_subscription = create(:billing_plan_subscription, :business_owned)
    @advanced_security_product_uuid = create(:billing_product_uuid, :advanced_security)
    @business_metered = create(:business, :metered_ghec)
  end

  setup do
    @business = @billing_plan_subscription.business
    @owner = @business.owners.first
    @advanced_security_product = AdvancedSecurity::Public::Subscription::ADVANCED_SECURITY_MONTHLY_PRODUCT
  end

  context "#subscribe_to_advanced_security_trial", skip_enterprise: true do
    test "can start a trial with metered GHE trial business with feature flag enabled" do
      GitHub.flipper[:metered_ghe_allow_ghas_trials].enable(@business_metered)
      @business_metered.update_attribute(:trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now)
      assert @business_metered.metered_plan?
      assert @business_metered.trial?

      result = @business_metered.subscribe_to_advanced_security_trial(
        actor: @business_metered.owners.first,
        billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
      assert result.ok?
    end

    test "cannot start a trial with metered GHE trial business with feature flag disabled" do
      GitHub.flipper[:metered_ghe_allow_ghas_trials].disable(@business_metered)
      @business_metered.update_attribute(:trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now)
      assert @business_metered.metered_plan?
      assert @business_metered.trial?

      result = @business_metered.subscribe_to_advanced_security_trial(
        actor: @business_metered.owners.first,
        billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
      refute result.ok?
    end

    test "cannot start a trial with metered GHE converted business" do
      assert @business_metered.metered_plan?
      refute @business_metered.trial?

      result = @business_metered.subscribe_to_advanced_security_trial(
        actor: @business_metered.owners.first,
        billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
      refute result.ok?
    end

    test "creates a trial subscription item with a business" do
      jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")

      travel_to jan_1st do
        free_trial_end_date = GitHub::Billing.today + 31.days
        result = @business.subscribe_to_advanced_security_trial(
          actor: @owner,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        assert result.ok?
        assert result.value!.on_free_trial?
        assert @business.advanced_security_purchased_for_entity?

        assert_equal 1, @business.advanced_security_seats_for_entity

        # verify that a pending plan change to quantity 0, is scheduled for trial experation.
        assert_equal 1, @business.pending_plan_changes.count
        pending_plan_change = @business.pending_plan_changes.first
        assert_equal false, pending_plan_change.is_complete
        assert_equal free_trial_end_date, pending_plan_change.active_on
        assert_equal 1, pending_plan_change.pending_subscription_item_changes.count

        pending_subscription_item_change = pending_plan_change.pending_subscription_item_changes.first
        assert_equal 0, pending_subscription_item_change.quantity
        assert_equal true, pending_subscription_item_change.free_trial
      end
    end

    test "creates a trial matching the remaining enterprise trial length" do
      jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")
      jan_9th = GitHub::Billing.date_in_timezone Date.parse("2023-01-09")

      travel_to jan_1st do
        @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
      end
      travel_to jan_9th do
        free_trial_end_date = GitHub::Billing.today + 23.days
        result = @business.subscribe_to_advanced_security_trial(
          actor: @owner,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        assert result.ok?
        assert result.value!.on_free_trial?
        assert @business.advanced_security_purchased_for_entity?

        assert_equal 1, @business.advanced_security_seats_for_entity

        # verify that a pending plan change to quantity 0, is scheduled for trial experation.
        assert_equal 1, @business.pending_plan_changes.count
        pending_plan_change = @business.pending_plan_changes.first
        assert_equal false, pending_plan_change.is_complete
        assert_equal free_trial_end_date, pending_plan_change.active_on
        assert_equal 1, pending_plan_change.pending_subscription_item_changes.count

        pending_subscription_item_change = pending_plan_change.pending_subscription_item_changes.first
        assert_equal 0, pending_subscription_item_change.quantity
        assert_equal true, pending_subscription_item_change.free_trial
      end
    end

    test "creates a 30 day trial with purchased Enterprise" do
      jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")

      travel_to jan_1st do
        free_trial_end_date = GitHub::Billing.today + 31.days
        result = @business.subscribe_to_advanced_security_trial(
          actor: @owner,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        assert result.ok?
        assert result.value!.on_free_trial?
        assert @business.advanced_security_purchased_for_entity?

        assert_equal 1, @business.advanced_security_seats_for_entity

        # verify that a pending plan change to quantity 0, is scheduled for trial experation.
        assert_equal 1, @business.pending_plan_changes.count
        pending_plan_change = @business.pending_plan_changes.first
        assert_equal false, pending_plan_change.is_complete
        assert_equal free_trial_end_date, pending_plan_change.active_on
        assert_equal 1, pending_plan_change.pending_subscription_item_changes.count

        pending_subscription_item_change = pending_plan_change.pending_subscription_item_changes.first
        assert_equal 0, pending_subscription_item_change.quantity
        assert_equal true, pending_subscription_item_change.free_trial
      end
    end

    test "instruments trial business.subscribe_to_advanced_security_trial when trial is created" do
      events = assert_performed_audit_entries(count: 1, only: "business.advanced_security_trial_created") do
        result = @business.subscribe_to_advanced_security_trial(
          actor: @owner,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
      end
      expected_payload = {
        trial_days: 30,
        dual_enterprise_trial: false,
      }

      assert_subset_hash expected_payload, events.first
      assert_dogstats_increment(1, "business.advanced_security_trial_created", tags: ["dual_enterprise_trial:false"])
    end

    test "instruments trial business.subscribe_to_advanced_security_trial when trial is created and has a dual trial" do
      jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")

      travel_to jan_1st do
        @business.update_attribute :trial_expires_at, 21.days.from_now

        events = assert_performed_audit_entries(count: 1, only: "business.advanced_security_trial_created") do
          result = @business.subscribe_to_advanced_security_trial(
            actor: @owner,
            billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        end
        expected_payload = {
          trial_days: 21,
          dual_enterprise_trial: true,
        }

        assert_subset_hash expected_payload, events.first
        assert_dogstats_increment(1, "business.advanced_security_trial_created", tags: ["dual_enterprise_trial:true"])
      end
    end

    test "instruments failure" do
      error = AdvancedSecurity::Public::Subscription::UnprocessableError.new("GHAS is not currently enabled for purchase.")
      Business.any_instance.stubs(:subscribe_to_product).returns(GitHub::Result.error(error))

      @business.subscribe_to_advanced_security_trial(
        actor: @owner,
        billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month
      )
      refute_dogstats_increment("business.advanced_security_trial_created")
      assert_dogstats_increment(1, "business.advanced_security_trial_created.error")
    end

    test "Other product trials collects payment at the end of a trial period" do
      GitHub.flipper[:skip_immediate_payment_collection_for_plan_or_seat_changes].disable

      subscription = create :billing_plan_subscription, :zuora
      copilot = create(:billing_product_uuid, :copilot)
      user = create :credit_card_user, plan: "pro", plan_subscription: subscription

      assert_enqueued_jobs(1, only: SynchronizePlanSubscriptionJob) do
        assert_enqueued_jobs(0, only: CollectPaymentForUpgradeJob) do
          result = Billing::CreateProductSubscriptionItem.call(
            product_uuid: copilot,
            quantity: 1,
            account: user,
            viewer: user,
            free_trial_length: 1.week
          )
          assert result[:subscription_item].on_free_trial?
        end
      end

      reset_jobs

      assert_equal 1, user.pending_plan_changes.count
      pending_plan_change = user.pending_plan_changes.first
      assert_equal false, pending_plan_change.is_complete
      assert_equal 1, pending_plan_change.pending_subscription_item_changes.count
      pending_subscription_item_change = pending_plan_change.pending_subscription_item_changes.first
      assert_equal 1, pending_subscription_item_change.quantity
      assert_equal true, pending_subscription_item_change.free_trial

      assert_enqueued_jobs(1, only: SynchronizePlanSubscriptionJob) do
        assert_enqueued_jobs(0, only: CollectPaymentForUpgradeJob) do
          user.pending_plan_changes.first.run
        end
      end
    end

    test "does not collect payment at the end of a trial period" do
      GitHub.flipper[:skip_immediate_payment_collection_for_plan_or_seat_changes].disable
      assert_enqueued_jobs(1, only: SynchronizePlanSubscriptionJob) do
        assert_enqueued_jobs(0, only: CollectPaymentForUpgradeJob) do
          result = @business.subscribe_to_advanced_security_trial(
            actor: @owner,
            billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
          assert result.value!.on_free_trial?
        end
      end

      reset_jobs

      assert_equal 1, @business.pending_plan_changes.count
      pending_plan_change = @business.pending_plan_changes.first
      assert_equal false, pending_plan_change.is_complete
      assert_equal 1, pending_plan_change.pending_subscription_item_changes.count
      pending_subscription_item_change = pending_plan_change.pending_subscription_item_changes.first
      assert_equal 0, pending_subscription_item_change.quantity
      assert_equal true, pending_subscription_item_change.free_trial

      assert_enqueued_jobs(2, only: SynchronizePlanSubscriptionJob) do
        assert_enqueued_jobs(0, only: CollectPaymentForUpgradeJob) do
          @business.pending_plan_changes.first.run
        end
      end
    end
  end

  context "#has_active_advanced_security_trial?", skip_enterprise: true do
    test "returns false when the business has no trial " do
      refute @business.has_active_advanced_security_trial?
    end

    test "returns true when the business has an active trial" do
      jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")

      travel_to jan_1st do
        result = @business.subscribe_to_advanced_security_trial(
          actor: @owner,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        assert result.ok?
        assert @business.has_active_advanced_security_trial?
      end
    end

    test "returns false when the trial was cancelled" do
      jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")

      travel_to jan_1st do
        result = @business.subscribe_to_advanced_security_trial(
          actor: @owner,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        assert result.ok?
        assert_equal 1, @business.pending_plan_changes.count
        @business.pending_plan_changes.first.run
        refute @business.has_active_advanced_security_trial?
      end
    end

    test "returns false when has active subscription" do
      jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")

      travel_to jan_1st do
        result = @business.subscribe_to_advanced_security(
          actor: @owner,
          seats: 1,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        assert result.ok?
        refute @business.has_active_advanced_security_trial?
      end
    end
  end

  context "#has_advanced_security_trial_in_the_last_year?", skip_enterprise: true do
    test "returns true when the business has active trial" do
      jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")

      travel_to jan_1st do
        result = @business.subscribe_to_advanced_security_trial(
          actor: @owner,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        assert result.ok?
        assert @business.has_advanced_security_trial_in_the_last_year?
      end
    end

    test "returns true when the business has cancelled trial" do
      jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")

      travel_to jan_1st do
        result = @business.subscribe_to_advanced_security_trial(
          actor: @owner,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        assert result.ok?
        assert_equal 1, @business.pending_plan_changes.count
        @business.pending_plan_changes.first.run
        assert @business.has_advanced_security_trial_in_the_last_year?
      end
    end

    test "returns true when the business has had trial in last year" do
      june_1st_2022 = GitHub::Billing.date_in_timezone Date.parse("2022-06-01")
      jan_1st_2023 = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")
      july_1st_2023 = GitHub::Billing.date_in_timezone Date.parse("2023-07-01")

      travel_to june_1st_2022 do
        result = @business.subscribe_to_advanced_security_trial(
          actor: @owner,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        assert result.ok?
        assert_equal 1, @business.pending_plan_changes.count
        @business.pending_plan_changes.first.run
        assert @business.has_advanced_security_trial_in_the_last_year?
      end
      travel_to jan_1st_2023 do
        assert @business.has_advanced_security_trial_in_the_last_year?
      end
      travel_to july_1st_2023 do
        refute @business.has_advanced_security_trial_in_the_last_year?
      end
    end
  end

  context "#subscribe_to_advanced_security", skip_enterprise: true do
    test "can subscribe with metered GHE trial business with feature flag enabled" do
      GitHub.flipper[:metered_ghe_allow_ghas_trials].enable(@business_metered)
      @business_metered.update_attribute(:trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now)
      assert @business_metered.metered_plan?
      assert @business_metered.trial?

      result = @business_metered.subscribe_to_advanced_security(
        actor: @business_metered.owners.first,
        seats: 1,
        billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
      assert result.ok?
    end

    test "cannot subscribe with metered GHE trial business if feature flag is disabled" do
      GitHub.flipper[:metered_ghe_allow_ghas_trials].disable(@business_metered)
      @business_metered.update_attribute(:trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now)
      assert @business_metered.metered_plan?
      assert @business_metered.trial?

      result = @business_metered.subscribe_to_advanced_security(
        actor: @business_metered.owners.first,
        seats: 1,
        billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
      refute result.ok?
      assert_equal "Metered plans cannot add subscription items.", result.error.message
    end

    test "cannot subscribe with metered GHE converted business" do
      assert @business_metered.metered_plan?
      refute @business_metered.trial?

      result = @business_metered.subscribe_to_advanced_security(
        actor: @business_metered.owners.first,
        seats: 1,
        billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
      refute result.ok?
      assert_equal "Metered plans cannot add subscription items.", result.error.message
    end

    test "creates a subscription item with a business" do
      result = @business.subscribe_to_advanced_security(seats: 5, actor: @owner, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)

      assert result.ok?
      assert @business.advanced_security_purchased_for_entity?
      assert_equal 5, @business.advanced_security_seats_for_entity
    end

    test "collects payment on purchase" do
      GitHub.flipper[:skip_immediate_payment_collection_for_plan_or_seat_changes].disable
      assert_enqueued_jobs(0, only: SynchronizePlanSubscriptionJob) do
        assert_enqueued_jobs(1, only: CollectPaymentForUpgradeJob) do
          result = @business.subscribe_to_advanced_security(
            actor: @owner,
            seats: 1,
            billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
          refute result.value!.on_free_trial?
        end
      end
    end

    test "can skip_sync for actions like multi-checkout" do
      GitHub.flipper[:skip_immediate_payment_collection_for_plan_or_seat_changes].disable
      assert_enqueued_jobs(0, only: SynchronizePlanSubscriptionJob) do
        assert_enqueued_jobs(0, only: CollectPaymentForUpgradeJob) do
          result = @business.subscribe_to_advanced_security(
            actor: @owner,
            seats: 1,
            billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month,
            skip_sync: true
          )
          refute result.value!.on_free_trial?
          assert_dogstats_increment(1, "business.advanced_security_subscribed", tags: ["converted_from_trial:false", "skip_sync:true"])
        end
      end
    end

    test "instruments trial business.advanced_security_subscribed when we purchase without trial" do
      GitHub.flipper[:skip_immediate_payment_collection_for_plan_or_seat_changes].disable
      events = assert_performed_audit_entries(count: 1, only: "business.advanced_security_subscribed") do
        result = @business.subscribe_to_advanced_security(
          actor: @owner,
          seats: 4,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
      end
      assert_equal 4, events.first[:seats]
      refute events.first[:converted_from_trial]
      assert_dogstats_increment(1, "business.advanced_security_subscribed", tags: ["converted_from_trial:false"])
    end

    test "instruments failure" do
      error = AdvancedSecurity::Public::Subscription::UnprocessableError.new("GHAS is not currently enabled for purchase.")
      Business.any_instance.stubs(:subscribe_to_product).returns(GitHub::Result.error(error))

      result = @business.subscribe_to_advanced_security(
        actor: @owner,
        seats: 3,
        billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month
      )

      refute_dogstats_increment("business.advanced_security_subscribed")
      assert_dogstats_increment(1, "business.advanced_security_subscribed.error")
    end

    test "can end a trial early by purchasing GHAS", skip_enterprise: true do
      jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")
      GitHub.flipper[:skip_immediate_payment_collection_for_plan_or_seat_changes].disable
      travel_to jan_1st do
        result = @business.subscribe_to_advanced_security_trial(
          actor: @owner,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        assert result.ok?
        assert result.value!.on_free_trial?
        assert @business.advanced_security_purchased_for_entity?
        assert_equal 1, @business.pending_plan_changes.count

        assert @business.has_active_advanced_security_trial?
        assert @business.has_advanced_security_trial_in_the_last_year?

        assert_enqueued_jobs(1, only: SynchronizePlanSubscriptionJob) do
          assert_enqueued_jobs(0, only: CollectPaymentForUpgradeJob) do
            result = @business.subscribe_to_advanced_security(
              actor: @owner,
              seats: 3,
              billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
            assert result.ok?
            refute result.value!.on_free_trial?

            RunPendingPlanChangeJob.perform_now(@business.pending_plan_changes.first)
          end
        end

        assert @business.advanced_security_purchased_for_entity?
        refute @business.has_active_advanced_security_trial?
        assert @business.has_advanced_security_trial_in_the_last_year?
        assert_equal 3, @business.advanced_security_seats_for_entity
        assert_equal 1, @business.pending_plan_changes.count
        assert @business.pending_plan_changes.first.is_complete
      end
    end
  end

  test "instruments business.advanced_security_trial_converted when we convert via a trial", skip_enterprise: true do
    jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")
    GitHub.flipper[:skip_immediate_payment_collection_for_plan_or_seat_changes].disable
    travel_to jan_1st do
      result = @business.subscribe_to_advanced_security_trial(
        actor: @owner,
        billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
      assert result.ok?
      assert result.value!.on_free_trial?
      assert @business.advanced_security_purchased_for_entity?
      assert_equal 1, @business.pending_plan_changes.count

      assert @business.has_active_advanced_security_trial?
      assert @business.has_advanced_security_trial_in_the_last_year?

      events = assert_performed_audit_entries(count: 1, only: "business.advanced_security_subscribed") do
        result = @business.subscribe_to_advanced_security(
          actor: @owner,
          seats: 3,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        assert result.ok?
        refute result.value!.on_free_trial?
      end
      assert_equal 3, events.first[:seats]
      assert events.first[:converted_from_trial]
      assert_dogstats_increment(1, "business.advanced_security_subscribed", tags: ["converted_from_trial:true"])
    end
  end

  context "cancelling subscription", skip_enterprise: true do
    test "clears config settings when subscription_item is cancelled" do
      # Arrange
      @advanced_security_product_uuid = create(:billing_product_uuid, :advanced_security)
      num_seats = 5
      @business.subscribe_to_advanced_security(seats: num_seats, actor: @owner, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
      subscription_item = @business.active_subscription_items.sole

      # Assume
      assert @business.reload.advanced_security_purchased_for_entity?
      assert_equal num_seats, @business.advanced_security_seats_for_entity

      # Act
      subscription_item.cancel!(force: true, actor: @owner)

      # Assert
      refute @business.reload.advanced_security_purchased_for_entity?
      assert_predicate @business.advanced_security_seats_for_entity, :zero?
    end unless GitHub.enterprise?
  end

  context "#cancel_advanced_security_subscription", skip_enterprise: true do
    test "schedules a cancellation pending plan change and CollectPaymentForUpgradeJob when skip_sync is false" do
      GitHub.flipper[:skip_immediate_payment_collection_for_plan_or_seat_changes].disable
      @advanced_security_product_uuid = create(:billing_product_uuid, :advanced_security)
      num_seats = 5
      @business.subscribe_to_advanced_security(seats: num_seats, actor: @owner, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)

      assert @business.advanced_security_purchased_for_entity?
      assert_equal num_seats, @business.advanced_security_seats_for_entity
      assert Billing::PendingPlanChange.all.empty?

      result = T.let(nil, T.nilable(GitHub::Result))
      events = assert_performed_audit_entries(count: 1, only: "business.advanced_security_cancellation_scheduled") do
        assert_enqueued_jobs 1, only: CollectPaymentForUpgradeJob do
          assert_enqueued_jobs 1, only: RunPendingPlanChangeJob do
            assert_difference "Billing::PendingSubscriptionItemChange.count", 1 do
              result = @business.cancel_advanced_security_subscription(actor: @owner, skip_sync: false)
            end
          end
        end
      end

      assert result&.ok?
      pending_plan_change = Billing::PendingPlanChange.last
      assert T.must(pending_plan_change).pending_subscription_item_changes.sole.cancellation?
    end

    test "does not schedule a CollectPaymentForUpgradeJob when skip_sync is true" do
      GitHub.flipper[:skip_immediate_payment_collection_for_plan_or_seat_changes].disable
      @advanced_security_product_uuid = create(:billing_product_uuid, :advanced_security)
      num_seats = 5
      @business.subscribe_to_advanced_security(seats: num_seats, actor: @owner, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)

      assert @business.advanced_security_purchased_for_entity?
      assert_equal num_seats, @business.advanced_security_seats_for_entity
      assert Billing::PendingPlanChange.all.empty?

      result = T.let(nil, T.nilable(GitHub::Result))
      events = assert_performed_audit_entries(count: 1, only: "business.advanced_security_cancellation_scheduled") do
        assert_enqueued_jobs 0, only: CollectPaymentForUpgradeJob do
          assert_enqueued_jobs 1, only: RunPendingPlanChangeJob do
            assert_difference "Billing::PendingSubscriptionItemChange.count", 1 do
              result = @business.cancel_advanced_security_subscription(actor: @owner, skip_sync: true)
            end
          end
        end
      end

      assert result&.ok?
      pending_plan_change = Billing::PendingPlanChange.last
      assert T.must(pending_plan_change).pending_subscription_item_changes.sole.cancellation?
    end

    test "can cancel a subscription immediately" do
      GitHub.flipper[:skip_immediate_payment_collection_for_plan_or_seat_changes].disable
      @advanced_security_product_uuid = create(:billing_product_uuid, :advanced_security)
      num_seats = 5
      @business.subscribe_to_advanced_security(seats: num_seats, actor: @owner, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)

      assert @business.advanced_security_purchased_for_entity?
      assert_equal num_seats, @business.advanced_security_seats_for_entity
      assert Billing::PendingPlanChange.all.empty?

      result = T.let(nil, T.nilable(GitHub::Result))
      events = assert_performed_audit_entries(count: 1, only: "business.advanced_security_cancelled") do
        assert_difference "Billing::PendingSubscriptionItemChange.count", 0 do
          result = @business.cancel_advanced_security_subscription(actor: @owner, force: true, skip_sync: false)
        end
      end

      assert result&.ok?
      refute @business.reload.advanced_security_purchased_for_entity?
    end
  end

  context "#advanced_security_subscription_cancellation_pending?", skip_enterprise: true do
    test "returns true if there is a pending cancellation" do
      @advanced_security_product_uuid = create(:billing_product_uuid, :advanced_security)
      num_seats = 5
      @business.subscribe_to_advanced_security(seats: num_seats, actor: @owner, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)

      result = T.let(nil, T.nilable(GitHub::Result))
      assert_enqueued_jobs 1, only: RunPendingPlanChangeJob do
        assert_difference "Billing::PendingSubscriptionItemChange.count", 1 do
          result = @business.cancel_advanced_security_subscription(actor: @owner)
        end
      end

      assert result&.ok?
      assert @business.advanced_security_subscription_cancellation_pending?
    end

    test "returns false if there is no pending cancellation" do
      refute @business.advanced_security_subscription_cancellation_pending?

      @advanced_security_product_uuid = create(:billing_product_uuid, :advanced_security)
      num_seats = 5
      @business.subscribe_to_advanced_security(seats: num_seats, actor: @owner, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
      refute @business.advanced_security_subscription_cancellation_pending?
    end
  end

  context "#extend_advanced_security_trial", skip_enterprise: true do
    test "can extend trial" do
      jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")
      GitHub.flipper[:skip_immediate_payment_collection_for_plan_or_seat_changes].disable
      travel_to jan_1st do
        free_trial_end_date = GitHub::Billing.today + 30.days
        result = @business.subscribe_to_advanced_security_trial(
          actor: @owner,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        assert result.ok?
        assert result.value!.on_free_trial?
        assert @business.advanced_security_purchased_for_entity?
        assert_equal 1, @business.pending_plan_changes.count

        assert @business.has_active_advanced_security_trial?

        result = @business.extend_advanced_security_trial(
          actor: @owner,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month,
          days: 5
        )
        assert result.ok?

        item_id = @business.advanced_security_subscription_item.id
        subscription_item = Billing::SubscriptionItem.find(item_id)
        assert subscription_item.present? && subscription_item.is_a?(Billing::SubscriptionItem)

        assert @business.has_active_advanced_security_trial?
        assert_equal 1, @business.pending_plan_changes.count
        assert_equal free_trial_end_date + 5.days + 1.day, @business.pending_plan_changes.first.active_on
        assert_equal free_trial_end_date + 5.days, subscription_item.free_trial_ends_on
        assert_equal 1, @business.pending_plan_changes.first.pending_subscription_item_changes.count
        assert_equal 0, @business.pending_plan_changes.first.pending_subscription_item_changes.first.quantity
      end
    end

    test "instruments trial business.advanced_security_trial_extended_in_stafftools" do
      jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")
      GitHub.flipper[:skip_immediate_payment_collection_for_plan_or_seat_changes].disable
      travel_to jan_1st do
        result = @business.subscribe_to_advanced_security_trial(
          actor: @owner,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        assert result.ok?
        assert result.value!.on_free_trial?
        assert @business.advanced_security_purchased_for_entity?
        assert_equal 1, @business.pending_plan_changes.count

        assert @business.has_active_advanced_security_trial?

        events = assert_performed_audit_entries(count: 1, only: "business.advanced_security_trial_extended_in_stafftools") do
          result = @business.extend_advanced_security_trial(
            actor: @owner,
            billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month,
            days: 5
          )
        end
        assert result.ok?
        assert_dogstats_increment(1, "business.advanced_security_trial_extended_in_stafftools")
      end
    end

    test "instruments failure" do
      jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")
      GitHub.flipper[:skip_immediate_payment_collection_for_plan_or_seat_changes].disable
      travel_to jan_1st do
        result = @business.subscribe_to_advanced_security_trial(
          actor: @owner,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        assert result.ok?
        assert result.value!.on_free_trial?
        assert @business.advanced_security_purchased_for_entity?
        assert_equal 1, @business.pending_plan_changes.count

        assert @business.has_active_advanced_security_trial?

        events = assert_performed_audit_entries(count: 0, only: "business.advanced_security_trial_extended_in_stafftools") do
          result = @business.extend_advanced_security_trial(
            actor: @owner,
            billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month,
            days: -1
          )
        end
        refute result.ok?
        refute_dogstats_increment("business.advanced_security_trial_extended_in_stafftools")
        assert_dogstats_increment(1, "business.advanced_security_trial_extended_in_stafftools.error")
      end
    end

    test "actor must be able to manage business to extend trial" do
      jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")
      GitHub.flipper[:skip_immediate_payment_collection_for_plan_or_seat_changes].disable

      rando = create(:user)
      travel_to jan_1st do
        result = @business.subscribe_to_advanced_security_trial(
          actor: @owner,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        assert result.ok?
        assert result.value!.on_free_trial?
        assert @business.advanced_security_purchased_for_entity?
        assert_equal 1, @business.pending_plan_changes.count

        assert @business.has_active_advanced_security_trial?

        result = @business.extend_advanced_security_trial(
          actor: rando,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month,
          days: 5
        )
        refute result.ok?
        assert_equal "#{rando} does not have permission to manage this account (#{@business})", result.error.message
      end
    end
  end

  context "#end_advanced_security_trial_without_purchasing_now", skip_enterprise: true do
    test "cannot end trial when it is not active" do
      result = @business.end_advanced_security_trial_without_purchasing_now(
        actor: @owner,
        billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month
      )
      refute result.ok?
      assert_equal "Cannot end trial when trial is not active.", result.error.message
    end

    test "can end a trial early without purchase" do
      jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")
      GitHub.flipper[:skip_immediate_payment_collection_for_plan_or_seat_changes].disable
      travel_to jan_1st do
        result = @business.subscribe_to_advanced_security_trial(
          actor: @owner,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        assert result.ok?
        assert result.value!.on_free_trial?
        assert @business.advanced_security_purchased_for_entity?
        assert_equal 1, @business.pending_plan_changes.count

        assert @business.has_active_advanced_security_trial?
        assert @business.has_advanced_security_trial_in_the_last_year?

        assert_enqueued_jobs(1, only: SynchronizePlanSubscriptionJob) do
          assert_enqueued_jobs(0, only: CollectPaymentForUpgradeJob) do
            result = @business.end_advanced_security_trial_without_purchasing_now(
              actor: @owner,
              billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month
            )
            assert result.ok?
            refute result.value!.on_free_trial?
          end
        end

        refute @business.has_active_advanced_security_trial?
        assert @business.has_advanced_security_trial_in_the_last_year?
        assert_equal 0, @business.advanced_security_seats_for_entity
      end
    end

    test "instruments business.advanced_security_trial_ended_immediately_in_stafftools from stafftools" do
      jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")
      GitHub.flipper[:skip_immediate_payment_collection_for_plan_or_seat_changes].disable
      travel_to jan_1st do
        result = @business.subscribe_to_advanced_security_trial(
          actor: @owner,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        assert result.ok?
        assert result.value!.on_free_trial?
        assert @business.advanced_security_purchased_for_entity?
        assert_equal 1, @business.pending_plan_changes.count

        assert @business.has_active_advanced_security_trial?
        assert @business.has_advanced_security_trial_in_the_last_year?

        events = assert_performed_audit_entries(count: 0, only: "business.advanced_security_trial_extended_in_stafftools") do
          result = @business.end_advanced_security_trial_without_purchasing_now(
            actor: @owner,
            billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month,
            is_stafftools_action: true
          )
          assert result.ok?
          refute result.value!.on_free_trial?
        end

        assert_dogstats_increment(1, "business.advanced_security_trial_ended_immediately_in_stafftools")
      end
    end

    test "instruments business.advanced_security_trial_ended_immediately from outside stafftools" do
      jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")
      GitHub.flipper[:skip_immediate_payment_collection_for_plan_or_seat_changes].disable
      travel_to jan_1st do
        result = @business.subscribe_to_advanced_security_trial(
          actor: @owner,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        assert result.ok?
        assert result.value!.on_free_trial?
        assert @business.advanced_security_purchased_for_entity?
        assert_equal 1, @business.pending_plan_changes.count

        assert @business.has_active_advanced_security_trial?
        assert @business.has_advanced_security_trial_in_the_last_year?

        events = assert_performed_audit_entries(count: 0, only: "business.advanced_security_trial_extended") do
          result = @business.end_advanced_security_trial_without_purchasing_now(
            actor: @owner,
            billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month,
            is_stafftools_action: false,
          )
          assert result.ok?
          refute result.value!.on_free_trial?
        end

        assert_dogstats_increment(1, "business.advanced_security_trial_ended_immediately")
      end
    end

    test "instruments failure" do
      jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")
      GitHub.flipper[:skip_immediate_payment_collection_for_plan_or_seat_changes].disable
      travel_to jan_1st do
        result = @business.subscribe_to_advanced_security_trial(
          actor: @owner,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        assert result.ok?
        assert result.value!.on_free_trial?
        assert @business.advanced_security_purchased_for_entity?
        assert_equal 1, @business.pending_plan_changes.count

        assert @business.has_active_advanced_security_trial?
        assert @business.has_advanced_security_trial_in_the_last_year?

        rando = create :user
        events = assert_performed_audit_entries(count: 0, only: "business.advanced_security_trial_extended_in_stafftools") do
          result = @business.end_advanced_security_trial_without_purchasing_now(
            actor: rando,
            billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month,
            is_stafftools_action: true,
          )
          refute result.ok?
        end

        refute_dogstats_increment("business.advanced_security_trial_ended_immediately_in_stafftools")
        assert_dogstats_increment(1, "business.advanced_security_trial_ended_immediately_in_stafftools.error")
      end
    end

    test "actor must be able to modify the subscription item to end trial" do
      rando = create(:user)
      jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")
      GitHub.flipper[:skip_immediate_payment_collection_for_plan_or_seat_changes].disable
      travel_to jan_1st do
        result = @business.subscribe_to_advanced_security_trial(
          actor: @owner,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        assert result.ok?
        assert result.value!.on_free_trial?
        assert @business.advanced_security_purchased_for_entity?
        assert_equal 1, @business.pending_plan_changes.count

        assert @business.has_active_advanced_security_trial?
        assert @business.has_advanced_security_trial_in_the_last_year?

        result = @business.end_advanced_security_trial_without_purchasing_now(
          actor: rando,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month
        )
        refute result.ok?
        assert_equal "#{rando} does not have permission to manage this account (#{@business})", result.error.message
      end
    end
  end

  context "#advanced_security_subscription_seat_changes_pending?", skip_enterprise: true do
    test "returns true if there is a pending seat change" do
      @advanced_security_product_uuid = create(:billing_product_uuid, :advanced_security)
      num_seats = 5
      @business.subscribe_to_advanced_security(seats: num_seats, actor: @owner, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
      assert_enqueued_jobs 1, only: RunPendingPlanChangeJob do
        assert_difference "Billing::PendingSubscriptionItemChange.count", 1 do
          @business.set_advanced_security_seats_for_entity(seats: num_seats - 1, actor: @owner)
        end
      end
      assert @business.advanced_security_subscription_seat_changes_pending?
    end

    test "returns false if there is no pending seat change" do
      refute @business.advanced_security_subscription_seat_changes_pending?

      @advanced_security_product_uuid = create(:billing_product_uuid, :advanced_security)
      num_seats = 5
      @business.subscribe_to_advanced_security(seats: num_seats, actor: @owner, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
      refute @business.advanced_security_subscription_seat_changes_pending?

      result = @business.set_advanced_security_seats_for_entity(seats: num_seats + 1, actor: @owner)
      refute @business.advanced_security_subscription_seat_changes_pending?
    end
  end

  context "#advanced_security_subscription_change", skip_enterprise: true do
    test "returns last ghas subscription change" do
      @advanced_security_product_uuid = create(:billing_product_uuid, :advanced_security)
      num_seats = 5
      @business.subscribe_to_advanced_security(seats: num_seats, actor: @owner, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
      @business.set_advanced_security_seats_for_entity(seats: num_seats - 1, actor: @owner)
      last_pending_change = @business.pending_subscription_item_changes.last

      assert_equal "GitHub Advanced Security", last_pending_change.subscribable.name
      assert_equal last_pending_change, @business.advanced_security_subscription_change
    end

    test "returns nil if there is no pending advanced security change" do
      assert_nil @business.advanced_security_subscription_change
    end
  end

  context "#eligible_for_self_serve_advanced_security", skip_enterprise: true do
    test "is not eligible when Enterprise is metered trial because trial accounts are false" do
      @business_metered.update_attribute(:trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now)
      assert @business_metered.metered_plan?
      assert @business_metered.trial?
      refute @business_metered.eligible_for_self_serve_advanced_security?
    end

    test "is not eligible when Enterprise is metered converted" do
      assert @business_metered.metered_plan?
      refute @business_metered.trial?
      refute @business_metered.eligible_for_self_serve_advanced_security?
    end

    test "returns true when eligible" do
      refute @business.trial?
      assert @business.eligible_for_self_serve_payment?
      assert @business.eligible_for_self_serve_advanced_security?
      assert @business.eligible_for_self_serve_advanced_security?(skip_shared_checks: true)
    end

    test "returns false if in enterprise account trial" do
      @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now

      assert @business.trial?
      assert @business.eligible_for_self_serve_payment?
      refute @business.eligible_for_self_serve_advanced_security?
      refute @business.eligible_for_self_serve_advanced_security?(skip_shared_checks: true)
    end

    test "returns false if not eligible for self_serve_payment" do
      b = create :business

      refute b.trial?
      refute b.eligible_for_self_serve_payment?
      refute b.eligible_for_self_serve_advanced_security?
    end

    test "returns false if is dunning?" do
      @business.increment_billing_attempts

      refute @business.trial?
      assert @business.eligible_for_self_serve_payment?
      assert @business.dunning?
      refute @business.eligible_for_self_serve_advanced_security?
    end

    test "returns false if the business has been downgraded to a free plan" do
      @business.downgrade_to_free_plan

      assert @business.eligible_for_self_serve_payment?
      assert @business.downgraded_to_free_plan?
      refute @business.eligible_for_self_serve_advanced_security?
    end
  end

  context "#eligible_for_self_serve_advanced_security_trial", skip_enterprise: true do
    test "is eligible when Enterprise is metered trial and feature flag is enabled" do
      GitHub.flipper[:metered_ghe_allow_ghas_trials].enable(@business_metered)
      @business_metered.update_attribute(:trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now)
      assert @business_metered.metered_plan?
      assert @business_metered.trial?
      assert @business_metered.eligible_for_self_serve_advanced_security_trial?
    end

    test "is not eligible when Enterprise is metered trial and feature flag is disabled" do
      GitHub.flipper[:metered_ghe_allow_ghas_trials].disable(@business_metered)
      @business_metered.update_attribute(:trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now)
      assert @business_metered.metered_plan?
      assert @business_metered.trial?
      refute @business_metered.eligible_for_self_serve_advanced_security_trial?
    end

    test "is not eligible when Enterprise is metered converted" do
      assert @business_metered.metered_plan?
      refute @business_metered.trial?
      refute @business_metered.eligible_for_self_serve_advanced_security_trial?
    end

    test "returns true if not purchased" do
      assert @business.eligible_for_self_serve_payment?
      assert @business.eligible_for_self_serve_advanced_security?
      assert @business.eligible_for_self_serve_advanced_security_trial?
    end

    test "returns false if purchased" do
      owner = @business.owners.first

      result = @business.subscribe_to_advanced_security(
        seats: 1,
        actor: owner,
        billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month
      )

      assert result.ok?
      refute ::Billing::Public::SubscriptionItem.eligible_for_free_trial?(
        product: ::AdvancedSecurity::Public::Subscription::ADVANCED_SECURITY_MONTHLY_PRODUCT,
        account: @business,
      )
      refute @business.eligible_for_self_serve_advanced_security_trial?
    end

    test "returns false if in advanced security trial" do
      owner = @business.owners.first

      result = @business.subscribe_to_advanced_security_trial(
        actor: owner,
        billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month
      )

      assert result.ok?
      refute @business.eligible_for_self_serve_advanced_security_trial?
    end

    test "returns true if in an enterprise trial" do
      @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now

      assert @business.trial?
      assert @business.eligible_for_self_serve_advanced_security_trial?
    end

    test "returns false if in an enterprise trial with not enough days left" do
      jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")
      jan_20th = GitHub::Billing.date_in_timezone Date.parse("2023-01-20")
      travel_to jan_1st do
        @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
      end
      travel_to jan_20th do
        assert @business.trial?
        refute @business.eligible_for_self_serve_advanced_security_trial?
      end
    end

    test "returns false if already had trial in the last year" do
      june_1st_2022 = GitHub::Billing.date_in_timezone Date.parse("2022-06-01")
      jan_1st_2023 = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")
      july_1st_2023 = GitHub::Billing.date_in_timezone Date.parse("2023-07-01")

      travel_to june_1st_2022 do
        owner = @business.owners.first

        assert @business.eligible_for_self_serve_advanced_security_trial?
        assert @business.eligible_for_self_serve_advanced_security_trial?(skip_shared_checks: true)

        result = @business.subscribe_to_advanced_security_trial(
          actor: owner,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month
        )
        assert result.ok?
        assert_equal 1, @business.pending_plan_changes.count
        # cancel trial
        @business.pending_plan_changes.first.run
        refute @business.has_self_serve_advanced_security?
        refute @business.eligible_for_self_serve_advanced_security_trial?
        refute @business.eligible_for_self_serve_advanced_security_trial?(skip_shared_checks: true)
      end
      travel_to jan_1st_2023 do
        assert @business.has_advanced_security_trial_in_the_last_year?
        refute @business.eligible_for_self_serve_advanced_security_trial?
        refute @business.eligible_for_self_serve_advanced_security_trial?(skip_shared_checks: true)
      end
      travel_to july_1st_2023 do
        refute @business.has_advanced_security_trial_in_the_last_year?
        #TODO: trials need to be updated to support re-trials
        refute @business.eligible_for_self_serve_advanced_security_trial?
        refute @business.eligible_for_self_serve_advanced_security_trial?(skip_shared_checks: true)
      end
    end
  end

  context "#show_advanced_security_onboarding?", skip_enterprise: true do
    if TestEnv.test_in_multitenancy_mode?
      test "returns false for multitenant EMU" do
        jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")

        travel_to jan_1st do
          free_trial_end_date = GitHub::Billing.today + 30.days
          result = @business.subscribe_to_advanced_security_trial(
            actor: @owner,
            billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
          assert @business.has_active_advanced_security_trial?
          assert_equal free_trial_end_date, @business.advanced_security_subscription_item.free_trial_ends_on

          refute @business.show_advanced_security_onboarding?
        end
      end
    else
      test "returns true if trial is active" do
        jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")

        travel_to jan_1st do
          free_trial_end_date = GitHub::Billing.today + 30.days
          result = @business.subscribe_to_advanced_security_trial(
            actor: @owner,
            billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
          assert @business.has_active_advanced_security_trial?
          assert_equal free_trial_end_date, @business.advanced_security_subscription_item.free_trial_ends_on

          assert @business.show_advanced_security_onboarding?
        end
      end

      test "returns true if trial is recent"  do
        jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")

        end_date_plus_seven = 0.days
        end_date_plus_eight = 0.days

        travel_to jan_1st do
          free_trial_end_date = GitHub::Billing.today + 30.days
          end_date_plus_seven = free_trial_end_date + 7.days
          end_date_plus_eight = free_trial_end_date + 8.days
          result = @business.subscribe_to_advanced_security_trial(
            actor: @owner,
            billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
          assert @business.has_active_advanced_security_trial?
          assert_equal free_trial_end_date, @business.advanced_security_subscription_item.free_trial_ends_on

          @business.pending_plan_changes.first.run
          refute @business.has_active_advanced_security_trial?
          assert @business.show_advanced_security_onboarding?
        end
        travel_to end_date_plus_seven do
          assert @business.show_advanced_security_onboarding?
        end
        travel_to end_date_plus_eight do
          refute @business.show_advanced_security_onboarding?
        end
      end

      test "returns false if trial then purchased" do
        @business.subscribe_to_advanced_security_trial(
          actor: @owner,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        assert @business.has_active_advanced_security_trial?

        @business.subscribe_to_advanced_security(seats: 3, actor: @owner, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)

        refute @business.has_active_advanced_security_trial?
        assert @business.has_self_serve_advanced_security?
        refute @business.show_advanced_security_onboarding?
      end

      test "returns false if purchased" do
        @business.subscribe_to_advanced_security(seats: 3, actor: @owner, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)

        refute @business.has_active_advanced_security_trial?
        assert @business.has_self_serve_advanced_security?
        refute @business.show_advanced_security_onboarding?
      end

      test "returns false if enterprise trial expires ahead of advanced security trial" do
        @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now

        result = @business.subscribe_to_advanced_security_trial(
          actor: @owner,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        assert result.ok?

        assert @business.show_advanced_security_onboarding?

        @business.expire_trial(@owner)

        refute @business.show_advanced_security_onboarding?
      end

      test "returns false if enterprise trial is cancelled ahead of advanced security trial" do
        @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now

        result = @business.subscribe_to_advanced_security_trial(
          actor: @owner,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        assert result.ok?

        assert @business.show_advanced_security_onboarding?

        @business.cancel_trial(@owner)

        refute @business.show_advanced_security_onboarding?
      end
    end
  end

  context "never_billed_for_self_serve_advanced_security?", skip_enterprise: true do
    test "returns false with successful transaction" do
      assert @business.never_billed_for_self_serve_advanced_security?

      jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")
      GitHub.flipper[:skip_immediate_payment_collection_for_plan_or_seat_changes].disable
      travel_to jan_1st do
        result = @business.subscribe_to_advanced_security_trial(
          actor: @owner,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        assert result.ok?
        assert result.value!.on_free_trial?
        assert @business.advanced_security_purchased_for_entity?
        assert_equal 1, @business.pending_plan_changes.count

        assert @business.has_active_advanced_security_trial?
        assert @business.has_advanced_security_trial_in_the_last_year?

        assert_enqueued_jobs(1, only: SynchronizePlanSubscriptionJob) do
          assert_enqueued_jobs(0, only: CollectPaymentForUpgradeJob) do
            result = @business.subscribe_to_advanced_security(
              actor: @owner,
              seats: 4,
              billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
            assert result.ok?
            refute result.value!.on_free_trial?

            RunPendingPlanChangeJob.perform_now(@business.pending_plan_changes.first)
          end
        end

        assert @business.advanced_security_purchased_for_entity?
        refute @business.has_active_advanced_security_trial?
        assert @business.has_advanced_security_trial_in_the_last_year?
        assert_equal 4, @business.advanced_security_seats_for_entity
        assert_equal 1, @business.pending_plan_changes.count
        assert @business.pending_plan_changes.first.is_complete

        transaction = create(:billing_transaction, customer: @business.customer, amount_in_cents: 196_00)

        line_item = create(:billing_transaction_line_item,
          billing_transaction: transaction,
          subscribable: @advanced_security_product_uuid,
          amount_in_cents: 196_00,
          quantity: 4,
          description: "GitHub Advanced Security",
          subscribable_type: Billing::ProductUUID.name
        )
        refute @business.never_billed_for_self_serve_advanced_security?
      end
    end

    test "returns false with failed transaction" do
      assert @business.never_billed_for_self_serve_advanced_security?

      jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")
      GitHub.flipper[:skip_immediate_payment_collection_for_plan_or_seat_changes].disable
      travel_to jan_1st do
        result = @business.subscribe_to_advanced_security_trial(
          actor: @owner,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        assert result.ok?
        assert result.value!.on_free_trial?
        assert @business.advanced_security_purchased_for_entity?
        assert_equal 1, @business.pending_plan_changes.count

        assert @business.has_active_advanced_security_trial?
        assert @business.has_advanced_security_trial_in_the_last_year?

        assert_enqueued_jobs(1, only: SynchronizePlanSubscriptionJob) do
          assert_enqueued_jobs(0, only: CollectPaymentForUpgradeJob) do
            result = @business.subscribe_to_advanced_security(
              actor: @owner,
              seats: 4,
              billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
            assert result.ok?
            refute result.value!.on_free_trial?

            RunPendingPlanChangeJob.perform_now(@business.pending_plan_changes.first)
          end
        end

        assert @business.advanced_security_purchased_for_entity?
        refute @business.has_active_advanced_security_trial?
        assert @business.has_advanced_security_trial_in_the_last_year?
        assert_equal 4, @business.advanced_security_seats_for_entity
        assert_equal 1, @business.pending_plan_changes.count
        assert @business.pending_plan_changes.first.is_complete

        transaction = create(:billing_transaction, customer: @business.customer, amount_in_cents: 196_00, last_status: :failed)

        line_item = create(:billing_transaction_line_item,
          billing_transaction: transaction,
          subscribable: @advanced_security_product_uuid,
          amount_in_cents: 196_00,
          quantity: 4,
          description: "GitHub Advanced Security",
          subscribable_type: Billing::ProductUUID.name
        )
        refute @business.never_billed_for_self_serve_advanced_security?
      end
    end

    test "returns true with no transactions" do
      assert @business.never_billed_for_self_serve_advanced_security?

      jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")
      GitHub.flipper[:skip_immediate_payment_collection_for_plan_or_seat_changes].disable
      travel_to jan_1st do
        result = @business.subscribe_to_advanced_security_trial(
          actor: @owner,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        assert result.ok?
        assert result.value!.on_free_trial?
        assert @business.advanced_security_purchased_for_entity?
        assert_equal 1, @business.pending_plan_changes.count

        assert @business.has_active_advanced_security_trial?
        assert @business.has_advanced_security_trial_in_the_last_year?

        assert_enqueued_jobs(1, only: SynchronizePlanSubscriptionJob) do
          assert_enqueued_jobs(0, only: CollectPaymentForUpgradeJob) do
            result = @business.subscribe_to_advanced_security(
              actor: @owner,
              seats: 4,
              billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
            assert result.ok?
            refute result.value!.on_free_trial?

            RunPendingPlanChangeJob.perform_now(@business.pending_plan_changes.first)
          end
        end

        assert @business.advanced_security_purchased_for_entity?
        refute @business.has_active_advanced_security_trial?
        assert @business.has_advanced_security_trial_in_the_last_year?
        assert_equal 4, @business.advanced_security_seats_for_entity
        assert_equal 1, @business.pending_plan_changes.count
        assert @business.pending_plan_changes.first.is_complete

        assert @business.never_billed_for_self_serve_advanced_security?
      end
    end

    test "returns true with 0 transaction amount" do
      assert @business.never_billed_for_self_serve_advanced_security?

      jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")
      GitHub.flipper[:skip_immediate_payment_collection_for_plan_or_seat_changes].disable
      travel_to jan_1st do
        result = @business.subscribe_to_advanced_security_trial(
          actor: @owner,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        assert result.ok?
        assert result.value!.on_free_trial?
        assert @business.advanced_security_purchased_for_entity?
        assert_equal 1, @business.pending_plan_changes.count

        assert @business.has_active_advanced_security_trial?
        assert @business.has_advanced_security_trial_in_the_last_year?

        assert_enqueued_jobs(1, only: SynchronizePlanSubscriptionJob) do
          assert_enqueued_jobs(0, only: CollectPaymentForUpgradeJob) do
            result = @business.subscribe_to_advanced_security(
              actor: @owner,
              seats: 4,
              billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
            assert result.ok?
            refute result.value!.on_free_trial?

            RunPendingPlanChangeJob.perform_now(@business.pending_plan_changes.first)
          end
        end

        assert @business.advanced_security_purchased_for_entity?
        refute @business.has_active_advanced_security_trial?
        assert @business.has_advanced_security_trial_in_the_last_year?
        assert_equal 4, @business.advanced_security_seats_for_entity
        assert_equal 1, @business.pending_plan_changes.count
        assert @business.pending_plan_changes.first.is_complete

        transaction = create(:billing_transaction, customer: @business.customer, amount_in_cents: 0)

        line_item = create(:billing_transaction_line_item,
          billing_transaction: transaction,
          subscribable: @advanced_security_product_uuid,
          amount_in_cents: 0,
          quantity: 4,
          description: "GitHub Advanced Security",
          subscribable_type: Billing::ProductUUID.name
        )
        assert @business.never_billed_for_self_serve_advanced_security?
      end
    end
  end

  context "#organization_for_advanced_security_trial", skip_enterprise: true do
    test "returns org when business only has one org" do
      org = create(:organization, admins: [@owner])
      @business.add_organization(org)

      assert_equal org, @business.organization_for_advanced_security_trial(actor: @owner)
    end

    test "returns nil when actor has no adminable organizations" do
      org = create(:organization, admins: [@owner])
      non_admin_user = create(:user)
      @business.add_organization(org)

      assert_nil @business.organization_for_advanced_security_trial(actor: non_admin_user)
    end

    test "returns first lexicographical adminable org when user is admin of many orgs" do
      non_admin_user = create(:user)
      adminable_orgs = create_list(:organization, 2, admins: [@owner, non_admin_user])
      non_adminable_orgs = create_list(:organization, 2, admins: [@owner])
      business = create(:business, organizations: adminable_orgs + non_adminable_orgs, owners: [@owner])

      expected_org = adminable_orgs.sort_by(&:login).first

      assert_equal expected_org, business.organization_for_advanced_security_trial(actor: non_admin_user)
    end
  end

  context "#potentially_trial_or_purchase_advanced_security?", skip_enterprise: true do
    if TestEnv.test_in_multitenancy_mode?
      test "is not eligible for multitenant EMU" do
        @business_metered.enable_feature(:metered_ghe_allow_ghas_trials)

        refute_predicate @business_metered, :potentially_trial_or_purchase_advanced_security?
      end
    elsif TestEnv.test_with_all_emus?
      test "is eligible for EMU metered trial business with feature flag enabled" do
        @business_metered.enable_feature(:metered_ghe_allow_ghas_trials)
        @business_metered.customer.update!(metered_ghe: true)
        @business_metered.update!(trial_expires_at: Billing::EnterpriseCloudTrial.trial_length.from_now)
        assert_predicate @business_metered, :metered_ghe?
        assert_predicate @business_metered, :trial?

        assert_predicate @business_metered, :potentially_trial_or_purchase_advanced_security?
      end

      test "is not eligible for EMU metered trial business with feature flag disabled" do
        @business_metered.disable_feature(:metered_ghe_allow_ghas_trials)
        @business_metered.customer.update!(metered_ghe: true)
        @business_metered.update!(trial_expires_at: Billing::EnterpriseCloudTrial.trial_length.from_now)
        assert_predicate @business_metered, :metered_ghe?
        assert_predicate @business_metered, :trial?

        refute_predicate @business_metered, :potentially_trial_or_purchase_advanced_security?
      end

      test "is not eligible for EMU metered non-trial business" do
        @business_metered.enable_feature(:metered_ghe_allow_ghas_trials)
        @business_metered.customer.update!(metered_ghe: true)
        assert_predicate @business_metered, :metered_ghe?
        refute_predicate @business_metered, :trial?

        refute_predicate @business_metered, :potentially_trial_or_purchase_advanced_security?
      end
    else
      test "is eligible when Enterprise is metered and trial with feature flag enabled" do
        GitHub.flipper[:metered_ghe_allow_ghas_trials].enable(@business_metered)
        @business_metered.update_attribute(:trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now)
        assert @business_metered.metered_plan?
        assert @business_metered.trial?
        assert @business_metered.potentially_trial_or_purchase_advanced_security?
      end

      test "is not eligible when Enterprise is metered and trial and feature flag is disabled" do
        GitHub.flipper[:metered_ghe_allow_ghas_trials].disable(@business_metered)
        @business_metered.update_attribute(:trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now)
        assert @business_metered.metered_plan?
        assert @business_metered.trial?
        refute @business_metered.potentially_trial_or_purchase_advanced_security?
      end

      test "is not eligible when Enterprise is metered and converted" do
        assert @business_metered.metered_plan?
        refute @business_metered.trial?
        refute @business_metered.potentially_trial_or_purchase_advanced_security?
      end

      test "allows for an EA trial" do
        @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now

        assert @business.trial?
        assert @business.potentially_trial_or_purchase_advanced_security?
      end
    end
  end

  context "#new_advanced_security_trial_days", skip_enterprise: true, skip_with_all_emus: true do

    test "returns 30 days if EA is purchased" do
      assert_equal 30, @business.new_advanced_security_trial_days
    end

    test "returns Enterprise trial days left if EA has an active trial" do
      jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")
      jan_10th = GitHub::Billing.date_in_timezone Date.parse("2023-01-10")
      travel_to jan_1st do
        @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
      end
      travel_to jan_10th do
        assert_equal 21, @business.new_advanced_security_trial_days
      end
    end

    test "returns 30 if trial_days_remaining is nil" do
      @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
      @business.stubs(:trial_days_remaining).returns(nil)
      assert_equal 30, @business.new_advanced_security_trial_days
    end
  end

end
