# typed: true
# frozen_string_literal: true

require "test_helper"

class BillingSubscriptionItemUpdaterTest < GitHub::TestCase
  include HookIntegrationTestHelper
  include HydroTestHelpers
  include AuditLog::IntegrationTestHelpers
  include GitHub::ZuoraTestHelper

  fixtures do
    @monthly_product_uuid = create(:billing_product_uuid, :copilot)
    @yearly_product_uuid = create(:billing_product_uuid, :copilot, :yearly)
    @monthly_product_uuid_different_product_key = create(:billing_product_uuid, :copilot_pro_plus)
    @github_advanced_security_plan = create(:billing_product_uuid, :advanced_security)
    @listing = create(:marketplace_listing, :verified)
    @expensive_plan = create :marketplace_listing_plan, :published,
      listing: @listing,
      monthly_price_in_cents: 40_00,
      yearly_price_in_cents: 400_00
    @cheap_plan = create :marketplace_listing_plan, :published,
      listing: @listing,
      monthly_price_in_cents: 10_00,
      yearly_price_in_cents: 100_00
    @business = create :business, :with_self_serve_payment
    @plan_subscription = create :billing_plan_subscription, :business_owned, customer: @business.customer
    @business_admin = @business.owners.first
    @org = create :organization, business: @business, admin: @business_admin
  end

  setup do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
    disable_feature_flag(:skip_immediate_payment_collection_for_plan_or_seat_changes)
  end

  def with_hook_delivery(&block)
    perform_enqueued_jobs(only: [DeliverHookEventJob]) do
      block.call
    end
  end

  context "#perform" do
    context "with product uuid subscribable" do
      test "continues the free trial when switching between free trial plans" do
        free_trial_end_date = GitHub::Billing.today + 60.days
        item = create :billing_subscription_item,
          subscribable: @monthly_product_uuid,
          quantity: 1,
          free_trial_ends_on: free_trial_end_date

        account = item.account

        assert_difference "Billing::PendingSubscriptionItemChange.count", 1 do
          Billing::SubscriptionItemUpdater.perform \
            subscribable: @monthly_product_uuid,
            start_free_trial: true,
            quantity: 1,
            sender: account,
            plan_subscription: item.plan_subscription
        end

        change = account.pending_subscription_item_changes.sole
        assert_equal free_trial_end_date + 1.day, change.active_on
        assert_equal 1, change.quantity
        assert_equal @monthly_product_uuid.id, change.subscribable_id

        assert_no_difference "Billing::PendingPlanChange.count" do
          assert_no_difference "Billing::PendingSubscriptionItemChange.count" do
            Billing::SubscriptionItemUpdater.perform \
              subscribable: @yearly_product_uuid,
              quantity: 1,
              sender: account,
              plan_subscription: item.plan_subscription
          end
        end
        account.reload
        new_change = account.pending_subscription_item_changes.sole
        new_item = account.subscription_items.last

        refute_equal change, new_change
        assert_equal free_trial_end_date + 1.day, new_change.active_on
        assert_equal 1, change.quantity
        assert_equal @yearly_product_uuid.id, new_change.subscribable_id

        refute_equal item, new_item
        assert new_item.on_free_trial?
        assert_equal @yearly_product_uuid, new_item.subscribable
      end

      # We want to avoid accidently charging a customer as a result of them having seperate pending
      # subscription item changes for ending their free trial and cancelling their subscription.
      # See: https://github.com/github/gitcoin/issues/9060
      test "ensures we don't create additional pending plan changes" do
        free_trial_end_date = GitHub::Billing.today + 60.days
        item = create :billing_subscription_item,
          subscribable: @monthly_product_uuid,
          quantity: 1,
          free_trial_ends_on: free_trial_end_date

        account = item.account

        # Schedule the free trial to end
        assert_difference "Billing::PendingSubscriptionItemChange.count", 1 do
          Billing::SubscriptionItemUpdater.perform \
            subscribable: @monthly_product_uuid,
            start_free_trial: true,
            quantity: 1,
            sender: account,
            plan_subscription: item.plan_subscription
        end

        # Changing the duration/interval of the item will result the transferring of the free trial
        # but should not result in a new pending plan change (should update the existing one).
        assert_no_difference "Billing::PendingPlanChange.count" do
          assert_no_difference "Billing::PendingSubscriptionItemChange.count" do
            Billing::SubscriptionItemUpdater.perform \
              subscribable: @yearly_product_uuid,
              quantity: 1,
              sender: account,
              plan_subscription: item.plan_subscription
          end
        end

        # assert that we have only one psic and it's for the free trial
        pending_item_change = account.pending_plan_changes.sole.pending_subscription_item_changes.sole
        assert pending_item_change.free_trial

        assert_no_difference "Billing::PendingPlanChange.count" do
          assert_no_difference "Billing::PendingSubscriptionItemChange.count" do
            Billing::SubscriptionItemUpdater.perform \
              subscribable: @monthly_product_uuid,
              quantity: 1,
              sender: account,
              plan_subscription: item.plan_subscription
          end
        end

        # assert we updated the pending item change to switch to monthly subscription
        pending_item_change = account.pending_plan_changes.sole.pending_subscription_item_changes.sole
        assert_equal @monthly_product_uuid, pending_item_change.subscribable
        assert_equal 1, pending_item_change.quantity

        assert_no_difference "Billing::PendingPlanChange.count" do
          assert_no_difference "Billing::PendingSubscriptionItemChange.count" do
            Billing::SubscriptionItemUpdater.perform \
              subscribable: @yearly_product_uuid,
              quantity: 0,
              sender: account,
              plan_subscription: item.plan_subscription
          end
        end

        # assert we updated the pending item change to cancel the active subscrition
        pending_item_change = account.pending_plan_changes.sole.pending_subscription_item_changes.sole
        pending_item_change = account.pending_plan_changes.sole.pending_subscription_item_changes.sole
        assert pending_item_change.subscribable == @yearly_product_uuid
        assert pending_item_change.quantity.zero?
      end


      test "performs an immediate update when changing to a higher price (monthly to yearly)" do
        item = create :billing_subscription_item,
          subscribable: @monthly_product_uuid,
          quantity: 1
        next_billing_date = GitHub::Billing.today + 10.days

        Billing::SubscriptionItem.any_instance.stubs(:next_billing_date).returns(next_billing_date)

        account = item.account

        assert_difference "Billing::SubscriptionItem.count", 1 do
          assert_no_difference "Billing::PendingSubscriptionItemChange.count" do
            Billing::SubscriptionItemUpdater.perform \
              subscribable: @yearly_product_uuid,
              quantity: 1,
              sender: account,
              plan_subscription: item.plan_subscription
          end
        end

        item.reload
        assert_equal 0, item.quantity
        assert_equal @monthly_product_uuid, item.subscribable

        new_item = account.reload.active_subscription_items.last
        assert_equal 1, new_item.quantity
        assert_equal @yearly_product_uuid, new_item.subscribable
      end

      test "performs an immediate update when changing to a product with the same product_type" do
        item = create :billing_subscription_item,
          subscribable: @monthly_product_uuid,
          quantity: 1
        next_billing_date = GitHub::Billing.today + 10.days

        Billing::SubscriptionItem.any_instance.stubs(:next_billing_date).returns(next_billing_date)
        assert_equal @monthly_product_uuid.product_type, @monthly_product_uuid_different_product_key.product_type
        refute_equal @monthly_product_uuid.product_key, @monthly_product_uuid_different_product_key.product_key

        account = item.account
        assert_difference "Billing::SubscriptionItem.count", 1 do
          assert_no_difference "Billing::PendingSubscriptionItemChange.count" do
            Billing::SubscriptionItemUpdater.perform \
              subscribable: @monthly_product_uuid_different_product_key,
              quantity: 1,
              sender: account,
              plan_subscription: item.plan_subscription
          end
        end

        item.reload
        assert_equal 0, item.quantity
        assert_equal @monthly_product_uuid, item.subscribable

        new_item = account.reload.active_subscription_items.last
        assert_equal 1, new_item.quantity
        assert_equal @monthly_product_uuid_different_product_key, new_item.subscribable
      end

      test "schedules a subscription item pending change when updating to a product with a lower price" do
        item = create :billing_subscription_item,
          subscribable: @monthly_product_uuid_different_product_key,
          quantity: 1
        next_billing_date = GitHub::Billing.today + 10.days

        Billing::SubscriptionItem.any_instance.stubs(:next_billing_date).returns(next_billing_date)
        account = item.account
        assert item.price > @monthly_product_uuid.base_price(duration: @monthly_product_uuid.billing_cycle) * item.quantity
        assert_difference "Billing::PendingSubscriptionItemChange.count", 1 do
          Billing::SubscriptionItemUpdater.perform \
            subscribable: @monthly_product_uuid,
            quantity: 1,
            sender: account,
            plan_subscription: item.plan_subscription
        end

        change = account.pending_subscription_item_changes.first
        assert_equal next_billing_date, change.active_on
        assert_equal @monthly_product_uuid, change.subscribable
        assert_equal 1, change.quantity
      end

      test "cancels pending subscription item change when updating to a product with a higher price and same product type" do
        item = create :billing_subscription_item, subscribable: @monthly_product_uuid, quantity: 1
        next_billing_date = GitHub::Billing.today + 10.days
        account = item.account
        subscription_item_change = create :billing_pending_subscription_item_change,
          subscribable: @monthly_product_uuid,
          pending_plan_change: create(:billing_pending_plan_change, user: account, active_on: next_billing_date),
          quantity: 1
        Billing::SubscriptionItem.any_instance.stubs(:next_billing_date).returns(next_billing_date)

        assert_difference "Billing::SubscriptionItem.count", 1 do
          Billing::SubscriptionItemUpdater.perform \
            subscribable: @monthly_product_uuid_different_product_key,
            quantity: 1,
            sender: account,
            plan_subscription: item.plan_subscription
        end
        change = account.reload.pending_subscription_item_changes
        assert_empty change
        new_item = account.active_subscription_items.last
        assert_equal @monthly_product_uuid_different_product_key, new_item.subscribable
      end

      test "schedules a subscription item pending change when performing a downgrade from yearly to monthly" do
        item = create :billing_subscription_item,
          subscribable: @yearly_product_uuid,
          quantity: 1
        next_billing_date = GitHub::Billing.today + 10.days

        Billing::SubscriptionItem.any_instance.stubs(:next_billing_date).returns(next_billing_date)

        account = item.account

        assert_difference "Billing::PendingSubscriptionItemChange.count", 1 do
          Billing::SubscriptionItemUpdater.perform \
            subscribable: @monthly_product_uuid,
            quantity: 1,
            sender: account,
            plan_subscription: item.plan_subscription
        end

        change = account.pending_subscription_item_changes.first
        assert_equal next_billing_date, change.active_on
        assert_equal @monthly_product_uuid, change.subscribable
        assert_equal 1, change.quantity
      end

      test "schedules a downgrade when lowering the quantity" do
        item = create :billing_subscription_item,
          subscribable: @monthly_product_uuid,
          quantity: 1

        account = item.account

        assert_difference "Billing::PendingSubscriptionItemChange.count", 1 do
          Billing::SubscriptionItemUpdater.perform \
            subscribable: @monthly_product_uuid,
            quantity: 0,
            sender: account,
            plan_subscription: item.plan_subscription
        end

        change = account.pending_cycle_change.pending_subscription_item_changes.first
        assert_equal @monthly_product_uuid, change.subscribable
        assert_equal 0, change.quantity
      end

      test "cancels trial subscription item successfully when the account doesn't exist" do
        plan_subscription = create(:billing_plan_subscription, user: nil)
        item = create(:billing_subscription_item, subscribable: @monthly_product_uuid, quantity: 1, plan_subscription: plan_subscription, free_trial_ends_on: GitHub::Billing.today + 30.days)

        Billing::SubscriptionItemUpdater.perform \
          subscribable: @monthly_product_uuid,
          quantity: 0,
          sender: User.ghost,
          force: true,
          plan_subscription: plan_subscription

        item.reload
        assert_equal 0, item.quantity
      end

      test "cancels free trial when end_free_trial is true and updating to a higher-tier item with the same product_type" do
        freeze_time do
          item = create(:billing_subscription_item, subscribable: @monthly_product_uuid, quantity: 1, free_trial_ends_on: GitHub::Billing.today + 30.days)
          account = item.account

          Billing::SubscriptionItemUpdater.perform \
            subscribable: @monthly_product_uuid_different_product_key,
            quantity: 1,
            sender: account,
            end_free_trial: true,
            plan_subscription: item.plan_subscription

          item.reload
          refute item.on_free_trial?
          assert_equal item.free_trial_ends_on, GitHub::Billing.yesterday
          assert_equal account.reload.active_subscription_items.first.subscribable, @monthly_product_uuid_different_product_key
        end
      end


      test "instruments an audit log event when running a scheduled cancellation" do
        item = create :billing_subscription_item,
          subscribable: @monthly_product_uuid,
          quantity: 1

        account = item.account

        events = assert_performed_audit_entries(count: 1, only: "billing.subscription_item_cancelled") do
          Billing::SubscriptionItemUpdater.perform \
            subscribable: @monthly_product_uuid,
            quantity: 0,
            sender: account,
            force: true,
            plan_subscription: item.plan_subscription
        end

        assert_equal last_performed_audit_entries, events

        expected_payload = {
          action: "billing.subscription_item_cancelled",
          subscription_item_id: item.id,
          sender_id: account.id,
          product_type: "github.copilot",
          billing_cycle: "month"
        }

        assert_subset_hash expected_payload, events.first
      end

      test "does not instrument an audit log event when a cancellation is scheduled" do
        item = create :billing_subscription_item,
          subscribable: @monthly_product_uuid,
          quantity: 1

        account = item.account

        events = assert_performed_audit_entries(count: 0, only: "billing.subscription_item_cancelled") do
          Billing::SubscriptionItemUpdater.perform \
            subscribable: @monthly_product_uuid,
            quantity: 0,
            sender: account,
            plan_subscription: item.plan_subscription
        end

        assert_equal 1, account.pending_cycle_change.pending_subscription_item_changes.count
        assert events.empty?
      end

      test "instrumentation includes Apple in-app purchase info for a cancellation" do
        item = create :billing_subscription_item,
          :iap,
          subscribable: @monthly_product_uuid,
          quantity: 1

        assert item.apple_subscription

        original_transaction_id = item.apple_subscription.original_transaction_id

        account = item.account

        events = assert_performed_audit_entries(count: 1, only: "billing.subscription_item_cancelled") do
          Billing::SubscriptionItemUpdater.perform \
            subscribable: @monthly_product_uuid,
            quantity: 0,
            sender: account,
            force: true,
            plan_subscription: item.plan_subscription,
            allow_cancelling_iap: true
        end

        assert_equal last_performed_audit_entries, events

        expected_payload = {
          in_app_purchase_vendor: "apple",
          in_app_purchase_identifier: original_transaction_id,
        }

        assert_subset_hash expected_payload, events.first
      end

      test "instrumentation includes Google in-app purchase info for a cancellation" do
        item = create :billing_subscription_item,
          :google_iap,
          subscribable: @monthly_product_uuid,
          quantity: 1

        assert item.google_subscription

        purchase_token = item.google_subscription.purchase_token

        account = item.account

        events = assert_performed_audit_entries(count: 1, only: "billing.subscription_item_cancelled") do
          Billing::SubscriptionItemUpdater.perform \
            subscribable: @monthly_product_uuid,
            quantity: 0,
            sender: account,
            force: true,
            plan_subscription: item.plan_subscription,
            allow_cancelling_iap: true
        end

        assert_equal last_performed_audit_entries, events

        expected_payload = {
          in_app_purchase_vendor: "google",
          in_app_purchase_identifier: purchase_token,
        }

        assert_subset_hash expected_payload, events.first
      end

      test "schedules a pending plan and subscription item change when cancelling a free trial for a product UUID" do
        freeze_time do
          one_month_and_one_day_from_now = GitHub::Billing.today + 1.month + 1.day
          account = create(:user)
          plan_subscription = create(:billing_plan_subscription, :zuora, user: account)
          customer = create(:credit_card_customer_account, user: account)

          account.reload

          assert_difference -> { Billing::PendingSubscriptionItemChange.count }, 1 do
            Billing::CreateProductSubscriptionItem.call(
              product_uuid: @monthly_product_uuid,
              quantity: 3,
              account: account,
              free_trial_length: 1.month,
              viewer: account,
            )
          end

          assert_equal 1, account.pending_plan_changes.count

          pending_plan_change = account.pending_plan_changes.first
          assert_equal one_month_and_one_day_from_now, pending_plan_change.active_on

          change = account.reload.pending_subscription_item_changes.first

          assert_equal @monthly_product_uuid, change.subscribable
          assert_equal 3, change.quantity

          assert_no_difference [-> { Billing::PendingSubscriptionItemChange.count },  -> { Billing::PendingPlanChange.count }]  do
            Billing::SubscriptionItemUpdater.perform \
              subscribable: @monthly_product_uuid,
              quantity: 0,
              sender: account,
              plan_subscription: plan_subscription
          end

          assert_equal 0, change.reload.quantity
          assert_equal one_month_and_one_day_from_now, pending_plan_change.reload.active_on
        end
      end

      test "does not change anything when there's no difference in the updater" do
        item = create :billing_subscription_item,
          subscribable: @monthly_product_uuid,
          quantity: 1

        account = item.account

        assert_no_difference "Billing::PendingSubscriptionItemChange.count" do
          Billing::SubscriptionItemUpdater.perform \
            subscribable: @monthly_product_uuid,
            quantity: 1,
            sender: account,
            plan_subscription: item.plan_subscription
        end
      end

      test "collects payment immediately for users on a free plan purchasing a product uuid subscription item upgrade" do
        subscription = create :billing_plan_subscription, :zuora
        create_zuora_subscription(
          zuora_subscription_number: subscription.zuora_subscription_number,
        )
        user = create :credit_card_user, plan: "free", plan_subscription: subscription
        subscription_item = create :billing_subscription_item,
          plan_subscription: subscription,
          subscribable: @monthly_product_uuid,
          quantity: 1

        assert_enqueued_jobs(0, only: SynchronizePlanSubscriptionJob) do
          assert_enqueued_jobs(1, only: CollectPaymentForUpgradeJob) do
            result = Billing::SubscriptionItemUpdater.perform(
              subscribable: @monthly_product_uuid,
              quantity: 10,
              sender: user,
              plan_subscription: subscription
            )
          end
        end
      end if GitHub.billing_enabled?

      test "collects payment immediately for users on a paid plan purchasing a product uuid subscription item upgrade" do
        subscription = create :billing_plan_subscription, :zuora
        create_zuora_subscription(
          zuora_subscription_number: subscription.zuora_subscription_number,
        )
        user = create :credit_card_user, plan: "pro", plan_subscription: subscription
        subscription_item = create :billing_subscription_item,
          plan_subscription: subscription,
          subscribable: @monthly_product_uuid,
          quantity: 1

        assert_enqueued_jobs(0, only: SynchronizePlanSubscriptionJob) do
          assert_enqueued_jobs(1, only: CollectPaymentForUpgradeJob) do
            result = Billing::SubscriptionItemUpdater.perform(
              subscribable: @monthly_product_uuid,
              quantity: 10,
              sender: user,
              plan_subscription: subscription
            )
          end
        end
      end if GitHub.billing_enabled?

      test "collects payment immediately for businesses when purchasing a product uuid subscription item upgrade" do
        business = create(:billing_plan_subscription, :business_owned).business
        owner = business.owners.first
        subscription_item = create :billing_subscription_item,
          plan_subscription: business.plan_subscription,
          subscribable: @monthly_product_uuid,
          quantity: 1

        assert_enqueued_jobs(0, only: SynchronizePlanSubscriptionJob) do
          assert_enqueued_jobs(1, only: CollectPaymentForUpgradeJob) do
            result = Billing::SubscriptionItemUpdater.perform(
              subscribable: @monthly_product_uuid,
              quantity: 10,
              sender: owner,
              plan_subscription: business.plan_subscription
            )
          end
        end
      end if GitHub.billing_enabled?


      test "does not collect payment immediately using CollectPaymentForUpgradeJob when the subscription item isn't of type product uuid" do
        item = create :billing_subscription_item,
          subscribable: @expensive_plan,
          quantity: 10
        account = item.account

        assert_enqueued_jobs(1, only: SynchronizePlanSubscriptionJob) do
          assert_enqueued_jobs(0, only: CollectPaymentForUpgradeJob) do
            Billing::SubscriptionItemUpdater.perform \
              subscribable: item.subscribable,
              quantity: 0,
              sender: account,
              plan_subscription: item.plan_subscription
          end
        end
      end

      test "enqueues a single plan subscription synchronization after force cancelling a free trial with a pending change" do
        enable_feature_flag(:billing_skip_sync_when_cancelling_subscription_item_trial)
        account = create(:credit_card_user)
        plan_subscription = create(:billing_plan_subscription, :zuora, user: account)

        result = Billing::CreateProductSubscriptionItem.call(
          product_uuid: @monthly_product_uuid,
          quantity: 1,
          free_trial_length: 30.days,
          account: account,
          viewer: account,
        )
        subscription_item = result[:subscription_item]

        pending_plan_change = create(:billing_pending_plan_change, user: account)
        mp_change = create(:billing_pending_subscription_item_change,
          subscribable: subscription_item.subscribable,
          pending_plan_change: pending_plan_change,
          quantity: 0
        )

        account.reload

        assert_enqueued_jobs(1, only: SynchronizePlanSubscriptionJob) do
          Billing::SubscriptionItemUpdater.perform \
            subscribable: @monthly_product_uuid,
            end_free_trial: true,
            force: true,
            quantity: 0,
            sender: account,
            plan_subscription: plan_subscription
        end
      end
    end

    test "instruments a billing subscription cancelled event when force cancelling a subscription for a product UUID" do
      account = create(:user)
      plan_subscription = create(:billing_plan_subscription, :zuora, user: account)
      customer = create(:credit_card_customer_account, user: account)

      account.reload

      events = subscribe("billing.subscription_item_cancelled")

      result = Billing::CreateProductSubscriptionItem.call(
        product_uuid: @monthly_product_uuid,
        quantity: 1,
        account: account,
        viewer: account,
      )

      Billing::SubscriptionItemUpdater.perform \
        subscribable: @monthly_product_uuid,
        quantity: 0,
        sender: account,
        force: true,
        plan_subscription: plan_subscription

      expected_payload = {
        subscription_item_id: result[:subscription_item].id,
        sender_id: account.id,
        previous_quantity: 1,
        previously_on_free_trial: false,
        previous_free_trial_ends_on: nil,
        previous_subscribable_id: @monthly_product_uuid.id,
        previous_subscribable_type: "Billing::ProductUUID",
      }

      event = events.pop
      refute_nil event, "Expected a billing.subscription_item_cancelled event"
      assert_subset_hash expected_payload, event.payload
      assert_incremented_stat("billing.subscription_item_cancelled")
    end

    test "handles when invalid subscribable is given" do
      plan_sub = create(:billing_plan_subscription)
      user = plan_sub.user
      invalid_subscribable = Billing::ProductUUID.new # not persisted

      update = Billing::SubscriptionItemUpdater.perform(
        plan_subscription: plan_sub,
        subscribable: invalid_subscribable,
        quantity: 1,
        sender: user,
      )

      refute update.result.success
      assert_equal ["Account has no subscription item to update"], update.result.errors
    end

    if GitHub.billing_enabled?
      test "instruments a billing subscription cancelled event when cancelling a subscription for a product UUID" do
        account = create(:user)
        plan_subscription = create(:billing_plan_subscription, :zuora, user: account)
        customer = create(:credit_card_customer_account, user: account)

        account.reload

        events = subscribe("billing.subscription_item_cancelled")

        result = Billing::CreateProductSubscriptionItem.call(
          product_uuid: @monthly_product_uuid,
          quantity: 1,
          account: account,
          viewer: account,
        )

        perform_enqueued_jobs(only: [PerformPendingPlanChangesJob, RunPendingPlanChangeJob]) do
          Billing::SubscriptionItemUpdater.perform \
            subscribable: @monthly_product_uuid,
            quantity: 0,
            sender: account,
            plan_subscription: plan_subscription
        end

        expected_payload = {
          subscription_item_id: result[:subscription_item].id,
          sender_id: account.id,
          previous_quantity: 1,
          previously_on_free_trial: false,
          previous_free_trial_ends_on: nil,
          previous_subscribable_id: @monthly_product_uuid.id,
          previous_subscribable_type: "Billing::ProductUUID",
        }

        event = events.pop
        refute_nil event, "Expected a billing.subscription_item_cancelled event"
        assert_subset_hash expected_payload, event.payload
      end
    end

    test "instruments a billing subscription cancelled event when cancelling a subscription item at the end of the free trial for a product UUID" do
      account = create(:user)
      plan_subscription = create(:billing_plan_subscription, :zuora, user: account)
      customer = create(:credit_card_customer_account, user: account)

      account.reload

      events = subscribe("billing.subscription_item_cancelled")

      result = Billing::CreateProductSubscriptionItem.call(
        product_uuid: @monthly_product_uuid,
        quantity: 1,
        free_trial_length: 30.days,
        account: account,
        viewer: account,
      )

      Billing::SubscriptionItemUpdater.perform \
        subscribable: @monthly_product_uuid,
        end_free_trial: true,
        force: true,
        quantity: 0,
        sender: account,
        plan_subscription: plan_subscription

      expected_payload = {
        subscription_item_id: result[:subscription_item].id,
        sender_id: account.id,
        previous_quantity: 1,
        previously_on_free_trial: true,
        previous_free_trial_ends_on: GitHub::Billing.today + 30.days,
        previous_subscribable_id: @monthly_product_uuid.id,
        previous_subscribable_type: "Billing::ProductUUID",
      }

      event = events.pop
      refute_nil event, "Expected a billing.subscription_item_cancelled event"
      assert_subset_hash expected_payload, event.payload
    end

    test "cancels an existing scheduled GHAS downgrade if an increase in seats is requested and upgrades immediately" do
      owner = create(:user)
      business = create(:business, :with_self_serve_payment, owners: [owner])

      business.subscribe_to_advanced_security(seats: 10, actor: owner, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)

      Billing::SubscriptionItemUpdater.perform(
        subscribable: @github_advanced_security_plan,
        quantity: 4,
        sender: owner,
        plan_subscription: business.plan_subscription,
      )

      change = business.reload.pending_plan_changes.first.pending_subscription_item_changes.first
      assert_equal @github_advanced_security_plan, change.subscribable
      assert_equal 4, change.quantity
      assert_equal 10, business.advanced_security_seats_for_entity

      Billing::SubscriptionItemUpdater.perform(
        subscribable: @github_advanced_security_plan,
        quantity: 11,
        sender: owner,
        plan_subscription: business.plan_subscription
      )

      assert_equal [], business.reload.pending_plan_changes.first.pending_subscription_item_changes
      assert_equal 11, business.advanced_security_seats_for_entity
    end if GitHub.billing_enabled?

    test "cancels an existing scheduled GHAS cancellation if an increase in seats is requested and upgrades immediately" do
      business = create(:business, :with_self_serve_payment)
      business.mark_advanced_security_as_purchased_for_entity(actor: @business_admin)

      plan_subscription = create(:billing_plan_subscription, :zuora, customer: business.customer, user: nil)
      @github_advanced_security_plan = create(:billing_product_uuid, :advanced_security)

      item = create(
        :billing_subscription_item,
        subscribable: @github_advanced_security_plan,
        plan_subscription: plan_subscription,
        quantity: 10,
      )

      Billing::SubscriptionItemUpdater.perform(
        subscribable: @github_advanced_security_plan,
        quantity: 0,
        sender: User.ghost,
        plan_subscription: item.plan_subscription
      )

      change = business.reload.pending_plan_changes.first.pending_subscription_item_changes.first
      assert_equal @github_advanced_security_plan, change.subscribable
      assert_equal 0, change.quantity
      assert_equal 10, business.advanced_security_seats_for_entity

      Billing::SubscriptionItemUpdater.perform(
        subscribable: @github_advanced_security_plan,
        quantity: 11,
        sender: User.ghost,
        plan_subscription: item.plan_subscription
      )

      assert_equal [], business.reload.pending_plan_changes.first.pending_subscription_item_changes
      assert_equal 11, business.advanced_security_seats_for_entity
    end if GitHub.billing_enabled?

    test "cancels existing pending change when cancelling a sponsorship" do
      plan_subscription = create(:billing_plan_subscription, purpose: :sponsors)
      user = plan_subscription.user
      sponsorship = create(:sponsorship, sponsor: user)
      sponsors_tier = sponsorship.tier
      subscription_item = sponsorship.subscription_item
      pending_plan_change = create(:billing_pending_plan_change, user: user)
      create(:billing_pending_subscription_item_change, :cancellation,
        subscribable: sponsors_tier,
        pending_plan_change: pending_plan_change,
      )

      assert_equal 1, user.pending_subscription_item_changes.count

      Billing::SubscriptionItemUpdater.perform(
        subscribable: sponsors_tier,
        force: true,
        quantity: 0,
        sender: User.ghost,
        plan_subscription: plan_subscription,
      )

      assert_predicate subscription_item.reload, :cancelled?
      assert_equal 0, user.pending_subscription_item_changes.count
    end

    test "supports delayed activation of a sponsorship" do
      plan_subscription = create(:billing_plan_subscription, purpose: :sponsors)
      user = plan_subscription.user
      sponsorship = create(:sponsorship, sponsor: user)
      sponsors_tier = sponsorship.tier
      subscription_item = sponsorship.subscription_item
      subscription_item.update!(quantity: 0)
      pending_plan_change = create(:billing_pending_plan_change, user: user)
      create(:billing_pending_subscription_item_change, :cancellation,
        subscribable: sponsors_tier,
        quantity: 1,
        pending_plan_change: pending_plan_change,
      )

      assert_equal 1, user.pending_subscription_item_changes.count

      # active, unpaid sponsorships are pending payment completion
      assert_predicate sponsorship, :active?
      refute_predicate sponsorship, :paid?
      assert_predicate subscription_item, :cancelled?

      Billing::SubscriptionItemUpdater.perform(
        subscribable: sponsors_tier,
        force: true,
        quantity: 1,
        sender: User.ghost,
        plan_subscription: plan_subscription,
      )

      # activating the subscription item will result in payment (asynchronously)
      assert_predicate sponsorship, :active?
      assert_predicate subscription_item.reload, :active?
    end

    test "schedules a downgrade when downgrading the plan" do
      item = create :billing_subscription_item, subscribable: @expensive_plan
      account = item.account

      assert_difference "Billing::PendingSubscriptionItemChange.count", 1 do
        Billing::SubscriptionItemUpdater.perform \
          subscribable: @cheap_plan,
          quantity: 1,
          sender: account,
          plan_subscription: item.plan_subscription
      end

      change = account.pending_cycle_change.pending_subscription_item_changes.first
      assert_equal @cheap_plan, change.subscribable
      assert_equal 1, change.quantity
    end

    test "schedules a downgrade when lowering the quantity" do
      item = create :billing_subscription_item,
        subscribable: @expensive_plan,
        quantity: 10
      account = item.account

      hook = create :hook, :web,
        installation_target: item.listing,
        events: %w(marketplace_purchase)
      deliveries = subscribe_to_hook_delivery "marketplace_purchase"

      with_hook_delivery do
        assert_difference "Billing::PendingSubscriptionItemChange.count", 1 do
          Billing::SubscriptionItemUpdater.perform \
            subscribable: @expensive_plan,
            quantity: 4,
            sender: account,
            plan_subscription: item.plan_subscription
        end
      end

      assert_equal 1, deliveries.count
      assert_includes deliveries.hooks, hook
      payload = deliveries.payload_for_hook(hook)
      assert_equal "pending_change", payload[:action]

      change = account.pending_cycle_change.pending_subscription_item_changes.first
      assert_equal @expensive_plan, change.subscribable
      assert_equal 4, change.quantity
    end

    test "schedules a downgrade for sponsor items when moving to a lower-priced tier" do
      sponsorship = create(:sponsorship, monthly_price_in_cents: 100_00)
      high_tier = sponsorship.tier
      low_tier = create(:sponsors_tier, :published,
        monthly_price_in_cents: 90_00,
        sponsors_listing: sponsorship.sponsors_listing
      )
      assert_equal high_tier.listing, low_tier.listing, "Tiers must be in the same listing"
      account = sponsorship.sponsor

      hook = create :hook,
        installation_target: sponsorship.sponsors_listing,
        events: %w(sponsorship)
      deliveries = subscribe_to_hook_delivery "sponsorship"

      with_hook_delivery do
        assert_difference "Billing::PendingSubscriptionItemChange.count", 1 do
          Billing::SubscriptionItemUpdater.perform \
            subscribable: low_tier,
            quantity: 1,
            sender: account,
            plan_subscription: sponsorship.plan_subscription
        end
      end

      assert_equal 1, deliveries.count
      assert_includes deliveries.hooks, hook
      payload = deliveries.payload_for_hook(hook)
      assert_equal "pending_tier_change", payload[:action]

      change = account.pending_cycle_change.pending_subscription_item_changes.first
      assert_equal low_tier, change.subscribable
      assert_equal 1, change.quantity
    end

    test "performs upgrade for yearly accounts" do
      item = create :billing_subscription_item,
        subscribable: @expensive_plan,
        quantity: 10
      account = item.account
      account.update_attribute :plan_duration, "year"

      assert_no_difference "Billing::PendingSubscriptionItemChange.count" do
        Billing::SubscriptionItemUpdater.perform \
          subscribable: @expensive_plan,
          quantity: 12,
          sender: account,
          plan_subscription: item.plan_subscription
      end

      assert_equal 12, item.reload.quantity
    end

    test "overwrites a scheduled downgrade when upgrading" do
      item = create :billing_subscription_item,
        subscribable: @expensive_plan,
        quantity: 10
      account = item.account

      change = create :billing_pending_plan_change, user: account
      mp_change = create :billing_pending_subscription_item_change,
        subscribable: item.subscribable,
        pending_plan_change: change,
        quantity: 5

      hook = create :hook, :web,
        installation_target: item.listing,
        events: %w(marketplace_purchase)
      deliveries = subscribe_to_hook_delivery "marketplace_purchase"

      with_hook_delivery do
        assert_no_difference "Billing::PendingSubscriptionItemChange.count" do
          Billing::SubscriptionItemUpdater.perform \
            subscribable: @expensive_plan,
            quantity: 12,
            sender: account,
            plan_subscription: item.plan_subscription
        end
      end

      assert_equal 1, deliveries.count
      assert_includes deliveries.hooks, hook

      payload = deliveries.payload_for_hook(hook)
      assert_equal "changed", payload[:action]

      assert_equal 12, mp_change.reload.quantity
      assert_equal 12, item.reload.quantity
    end

    test "schedules a cancellation for a paid marketplace purchase" do
      item = create :billing_subscription_item,
        subscribable: @expensive_plan,
        quantity: 10
      account = item.account

      assert_difference "Billing::PendingSubscriptionItemChange.count", 1 do
        Billing::SubscriptionItemUpdater.perform \
          subscribable: item.subscribable,
          quantity: 0,
          sender: account,
          plan_subscription: item.plan_subscription
      end

      refute_equal 0, item.reload.quantity
      change = account.reload.pending_subscription_item_changes.first
      assert_equal 0, change.quantity
      assert_equal item.subscribable, change.subscribable
    end

    test "schedules a cancellation for sponsor items" do
      travel_to(Time.utc(2020, 9, 24, 6, 53, 31)) do
        sponsorship = create(:sponsorship)
        sponsor_item = sponsorship.subscription_item
        account = sponsor_item.account
        events = subscribe "sponsors.sponsor_sponsorship_pending_cancellation"
        expected_payload = {
          actor: account.login,
          actor_id: account.id,
          user: account.login,
          user_id: account.id,
          active: true,
          sponsorable_user: sponsorship.sponsorable_login,
          sponsorable_user_id: sponsorship.sponsorable_id,
          sponsorship_id: sponsorship.id,
          current_tier_id: sponsor_item.subscribable.id,
          current_tier_monthly_amount_in_cents: sponsorship.monthly_price_in_cents,
          pending_change_on: GitHub::Billing.today,
          sponsor: sponsorship.sponsor.login,
          sponsor_id: sponsorship.sponsor_id,
          public: true,
          frequency: "recurring",
          payment_source: "github",
        }

        assert_difference "Billing::PendingSubscriptionItemChange.count", 1 do
          Billing::SubscriptionItemUpdater.perform \
            subscribable: sponsor_item.subscribable,
            quantity: 0,
            sender: account,
            plan_subscription: sponsor_item.plan_subscription
        end

        refute_equal 0, sponsor_item.reload.quantity
        change = account.reload.pending_subscription_item_changes.first
        assert_equal 0, change.quantity
        assert_equal sponsor_item.subscribable, change.subscribable
        refute_nil event = events.pop, "should have had an event"
        assert_equal expected_payload, event.payload
      end
    end

    test "returns an error result when sponsorship fails to update after subscription item successfully updates" do
      listing = create(:sponsors_listing, :approved, :with_tier)
      old_tier = listing.default_tier
      sponsorship = create(:sponsorship, tier: old_tier, sponsorable: listing.sponsorable)
      sponsor_item = sponsorship.subscription_item
      new_tier = create(:sponsors_tier, :published, sponsors_listing: listing,
        monthly_price_in_cents: old_tier.monthly_price_in_cents + 1_00)
      Sponsorship.any_instance.stubs(:update!).raises(ActiveRecord::RecordInvalid)
      Sponsorship.any_instance.stubs(:errors).returns(stub(full_messages: ["o noes"]))

      update = Billing::SubscriptionItemUpdater.perform \
        subscribable: new_tier,
        quantity: 1,
        sender: sponsorship.sponsor,
        plan_subscription: sponsor_item.plan_subscription

      refute update.result.success
      assert_equal ["o noes"], update.result.errors
    end

    test "returns an error result when sponsorship fails to update after subscription item also fails to update" do
      listing = create(:sponsors_listing, :approved, :with_tier)
      old_tier = listing.default_tier
      sponsorship = create(:sponsorship, tier: old_tier, sponsorable: listing.sponsorable)
      sponsor_item = sponsorship.subscription_item
      new_tier = create(:sponsors_tier, :published, sponsors_listing: listing,
        monthly_price_in_cents: old_tier.monthly_price_in_cents + 1_00)
      Billing::SubscriptionItem.any_instance.stubs(:save).returns(false)
      fake_sub_item_errors = stub(full_messages: ["item error"], empty?: false)
      Billing::SubscriptionItem.any_instance.stubs(:errors).returns(fake_sub_item_errors)
      Sponsorship.any_instance.stubs(:update!).raises(ActiveRecord::RecordInvalid)
      Sponsorship.any_instance.stubs(:errors).returns(stub(full_messages: ["sponsorship error"]))

      update = Billing::SubscriptionItemUpdater.perform \
        subscribable: new_tier,
        quantity: 1,
        sender: sponsorship.sponsor,
        plan_subscription: sponsor_item.plan_subscription

      refute update.result.success
      assert_equal ["item error", "sponsorship error"], update.result.errors
    end

    test "generates a hydro event when scheduling a sponsorship tier change from a custom tier", skip_enterprise: true do
      listing = create(:sponsors_listing, :approved, :with_tier)
      low_tier = listing.default_tier
      high_custom_tier = create(:sponsors_tier, :custom, sponsors_listing: listing,
        monthly_price_in_cents: low_tier.monthly_price_in_cents + 1_00)
      sponsorship = create(:sponsorship, tier: high_custom_tier,
        sponsor: high_custom_tier.creator)
      sponsor_item = sponsorship.subscription_item

      update = Billing::SubscriptionItemUpdater.perform \
        subscribable: low_tier,
        quantity: 1,
        sender: sponsorship.sponsor,
        plan_subscription: sponsor_item.plan_subscription

      assert update.result.success
      assert_hydro_messages(count: 1, schema: "github.sponsors.v1.SponsorshipPendingChange")
      assert_hydro_published({
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        sponsorship: Hydro::EntitySerializer.sponsorship(sponsorship),
        old_tier: Hydro::EntitySerializer.sponsors_tier(high_custom_tier),
        new_tier: Hydro::EntitySerializer.sponsors_tier(low_tier),
        listing: Hydro::EntitySerializer.sponsors_listing(listing),
        action: :CREATE,
        actor: Hydro::EntitySerializer.user(sponsorship.sponsor),
      }, schema: "github.sponsors.v1.SponsorshipPendingChange")
    end

    test "generates a hydro event when scheduling a sponsorship tier change to a custom tier", skip_enterprise: true do
      listing = create(:sponsors_listing, :approved, :with_tier)
      high_tier = create(:sponsors_tier, :published, sponsors_listing: listing,
        monthly_price_in_cents: 50_00)
      sponsorship = create(:sponsorship, tier: high_tier)
      custom_tier = create(:sponsors_tier, :custom, sponsors_listing: listing,
        creator: sponsorship.sponsor,
        monthly_price_in_cents: high_tier.monthly_price_in_cents - 1_00)
      sponsor_item = sponsorship.subscription_item

      update = Billing::SubscriptionItemUpdater.perform \
        subscribable: custom_tier,
        quantity: 1,
        sender: sponsorship.sponsor,
        plan_subscription: sponsor_item.plan_subscription

      assert update.result.success
      assert_hydro_messages(count: 1, schema: "github.sponsors.v1.SponsorshipPendingChange")
      assert_hydro_published({
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        sponsorship: Hydro::EntitySerializer.sponsorship(sponsorship),
        old_tier: Hydro::EntitySerializer.sponsors_tier(high_tier),
        new_tier: Hydro::EntitySerializer.sponsors_tier(custom_tier),
        listing: Hydro::EntitySerializer.sponsors_listing(listing),
        action: :CREATE,
        actor: Hydro::EntitySerializer.user(sponsorship.sponsor),
      }, schema: "github.sponsors.v1.SponsorshipPendingChange")
    end

    test "generates a hydro event when scheduling a sponsorship tier change", skip_enterprise: true do
      listing = create(:sponsors_listing, :approved, tier_count: 2)
      low_tier, high_tier = listing.sponsors_tiers.order(:monthly_price_in_cents)

      sponsorship = create(:sponsorship, tier: high_tier)
      sponsor_item = sponsorship.subscription_item
      sponsor = sponsor_item.account

      Billing::SubscriptionItemUpdater.perform \
        subscribable: low_tier,
        quantity: 1,
        sender: sponsor,
        plan_subscription: sponsor_item.plan_subscription

      assert_hydro_messages(count: 1, schema: "github.sponsors.v1.SponsorshipPendingChange")
      assert_hydro_published({
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        sponsorship: Hydro::EntitySerializer.sponsorship(sponsorship),
        old_tier: Hydro::EntitySerializer.sponsors_tier(high_tier),
        new_tier: Hydro::EntitySerializer.sponsors_tier(low_tier),
        listing: Hydro::EntitySerializer.sponsors_listing(listing),
        action: :CREATE,
        actor: Hydro::EntitySerializer.user(sponsor),
      }, schema: "github.sponsors.v1.SponsorshipPendingChange")
    end

    test "generates hydro event for a sponsorship tier change with an active goal", skip_enterprise: true do
      listing = create(:sponsors_listing, :approved)

      low_tier = create(
        :sponsors_tier,
        :published,
        sponsors_listing: listing,
        monthly_price_in_cents: 1_00,
        yearly_price_in_cents: 12_00,
      )

      high_tier = create(
        :sponsors_tier,
        :published,
        sponsors_listing: listing,
        monthly_price_in_cents: 5_00,
        yearly_price_in_cents: 60_00,
      )

      goal = create(:sponsors_goal, :active, listing: listing, target_value: 100)

      sponsorship = create(:sponsorship, tier: high_tier, sponsorable: listing.sponsorable)
      sponsor_item = sponsorship.subscription_item
      sponsor = sponsor_item.account

      Billing::SubscriptionItemUpdater.perform \
        subscribable: low_tier,
        quantity: 1,
        sender: sponsor,
        plan_subscription: sponsor_item.plan_subscription

      assert_hydro_messages(count: 1, schema: "github.sponsors.v1.SponsorshipPendingChange")
      assert_hydro_published({
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        sponsorship: Hydro::EntitySerializer.sponsorship(sponsorship),
        old_tier: Hydro::EntitySerializer.sponsors_tier(high_tier),
        new_tier: Hydro::EntitySerializer.sponsors_tier(low_tier),
        listing: Hydro::EntitySerializer.sponsors_listing(listing),
        action: :CREATE,
        actor: Hydro::EntitySerializer.user(sponsor),
        goal: Hydro::EntitySerializer.sponsors_goal(goal),
      }, schema: "github.sponsors.v1.SponsorshipPendingChange")
    end

    test "the sponsorship remains active when scheduling a sponsorship downgrade", skip_enterprise: true do
      travel_to(Time.utc(2020, 9, 24, 6, 53, 31)) do
        listing = create(:sponsors_listing, :approved, tier_count: 2)
        sponsorable = listing.sponsorable
        low_tier, high_tier = listing.sponsors_tiers.order(:monthly_price_in_cents).limit(2)

        sponsorship = create(:sponsorship, tier: high_tier, sponsorable: sponsorable)
        sponsor_item = sponsorship.subscription_item
        sponsor = sponsor_item.account

        assert_predicate sponsorship, :active?

        events = subscribe "sponsors.sponsor_sponsorship_pending_tier_change"

        Billing::SubscriptionItemUpdater.perform(
          subscribable: low_tier,
          quantity: 1,
          sender: sponsor,
          plan_subscription: sponsor_item.plan_subscription,
        )

        assert_predicate sponsorship.reload, :active?

        expected_payload = {
          sponsorship_id: sponsorship.id,
          public: true,
          active: true,
          current_tier_id: high_tier.id,
          current_tier_monthly_amount_in_cents: high_tier.monthly_price_in_cents,
          pending_change_tier_id: low_tier.id,
          pending_change_on: GitHub::Billing.today,
          sponsor_id: sponsor.id,
          sponsor: sponsor.login,
          actor: sponsor.login,
          actor_id: sponsor.id,
          user: sponsor.login,
          user_id: sponsor.id,
          frequency: "recurring",
          sponsorable_user: sponsorable.login,
          sponsorable_user_id: sponsorable.id,
          payment_source: "github",
        }
        refute_nil event = events.pop, "should have had an event"
        assert_equal expected_payload, event.payload
      end
    end

    test "the sponsorship subscribable doesn't change for a sponsorship downgrade", skip_enterprise: true do
      listing = create(:sponsors_listing, :approved)
      sponsorable = listing.sponsorable
      low_tier = create(
        :sponsors_tier,
        :published,
        sponsors_listing: listing,
        monthly_price_in_cents: 1_00,
        yearly_price_in_cents: 12_00,
      )

      high_tier = create(
        :sponsors_tier,
        :published,
        sponsors_listing: listing,
        monthly_price_in_cents: 5_00,
        yearly_price_in_cents: 60_00,
      )

      sponsorship = create(:sponsorship, tier: high_tier, sponsorable: sponsorable)
      sponsor_item = sponsorship.subscription_item
      sponsor = sponsor_item.account

      Billing::SubscriptionItemUpdater.perform(
        subscribable: low_tier,
        quantity: 1,
        sender: sponsor,
        plan_subscription: sponsor_item.plan_subscription,
      )

      new_sponsor_item = sponsorship.reload.subscription_item

      assert_equal sponsor_item, new_sponsor_item
      assert_equal high_tier, sponsorship.tier
      assert_equal sponsor_item.subscribable_id, sponsorship.subscribable_id
    end

    test "generates a hydro event and an audit log event when forcing a sponsorship tier change", skip_enterprise: true do
      events = subscribe "sponsors.sponsor_sponsorship_tier_change"
      listing = create(:sponsors_listing, :approved)
      low_tier = listing.sponsors_tiers.order(:monthly_price_in_cents).first

      high_tier = create(
        :sponsors_tier,
        :published,
        sponsors_listing: listing,
        monthly_price_in_cents: low_tier.monthly_price_in_cents + 100,
        yearly_price_in_cents: (low_tier.monthly_price_in_cents + 100) * 12,
      )

      sponsorship = create(:sponsorship, tier: high_tier, sponsorable: listing.sponsorable)
      sponsor_item = sponsorship.subscription_item
      sponsor = sponsor_item.account

      Billing::SubscriptionItemUpdater.perform \
        subscribable: low_tier,
        quantity: 1,
        sender: sponsor,
        force: true,
        plan_subscription: sponsor_item.plan_subscription

      assert_hydro_messages(count: 1, schema: "github.sponsors.v1.SponsorshipTierChange")

      expected_payload = {
        sponsorship_id: sponsorship.id,
        sponsor: sponsor.login,
        sponsor_id: sponsor.id,
        actor: sponsor.login,
        actor_id: sponsor.id,
        user: sponsor.login,
        user_id: sponsor.id,
        frequency: "recurring",
        previous_tier_id: high_tier.id,
        current_tier_id: low_tier.id,
        current_tier_monthly_amount_in_cents: low_tier.monthly_price_in_cents,
        sponsorable_user: listing.sponsorable_login,
        sponsorable_user_id: listing.sponsorable_id,
        public: true,
        active: true,
        payment_source: "github",
      }
      refute_nil event = events.pop, "should have had an audit log event"
      assert_equal expected_payload, event.payload
    end

    test "the sponsorship remains active when forcing a sponsorship downgrade", skip_enterprise: true do
      listing = create(:sponsors_listing, :approved)
      sponsorable = listing.sponsorable
      low_tier = create(
        :sponsors_tier,
        :published,
        sponsors_listing: listing,
        monthly_price_in_cents: 1_00,
        yearly_price_in_cents: 12_00,
      )

      high_tier = create(
        :sponsors_tier,
        :published,
        sponsors_listing: listing,
        monthly_price_in_cents: 5_00,
        yearly_price_in_cents: 60_00,
      )

      sponsorship = create(:sponsorship, tier: high_tier, sponsorable: sponsorable)
      sponsor_item = sponsorship.subscription_item
      sponsor = sponsor_item.account

      assert_predicate sponsorship, :active?

      Billing::SubscriptionItemUpdater.perform(
        subscribable: low_tier,
        quantity: 1,
        sender: sponsor,
        force: true,
        plan_subscription: sponsor_item.plan_subscription,
      )

      assert_predicate sponsorship.reload, :active?
    end

    test "the sponsorship cancels when a forced downgrade fails" do
      listing = create(:sponsors_listing, :approved, tier_count: 2)
      sponsorable = listing.sponsorable
      low_tier, high_tier = listing.published_sponsors_tiers.order(:monthly_price_in_cents)

      sponsorship = create(:sponsorship, tier: high_tier, sponsorable: sponsorable)
      sponsor_item = sponsorship.subscription_item
      sponsor = sponsor_item.account

      assert_predicate sponsorship, :active?

      Billing::SubscriptionItemUpdater.perform(
        subscribable: low_tier,
        quantity: -1,
        sender: sponsor,
        force: true,
        plan_subscription: sponsor_item.plan_subscription,
      )

      refute_predicate sponsorship.reload, :active?
      assert_equal high_tier, sponsorship.tier
    end

    test "the sponsorship subscribable updates when forcing a sponsorship downgrade", skip_enterprise: true do
      listing = create(:sponsors_listing, :approved)
      sponsorable = listing.sponsorable
      low_tier = create(
        :sponsors_tier,
        :published,
        sponsors_listing: listing,
        monthly_price_in_cents: 1_00,
        yearly_price_in_cents: 12_00,
      )

      high_tier = create(
        :sponsors_tier,
        :published,
        sponsors_listing: listing,
        monthly_price_in_cents: 5_00,
        yearly_price_in_cents: 60_00,
      )

      sponsorship = create(:sponsorship, tier: high_tier, sponsorable: sponsorable)
      sponsor_item = sponsorship.subscription_item
      sponsor = sponsor_item.account

      Billing::SubscriptionItemUpdater.perform(
        subscribable: low_tier,
        quantity: 1,
        sender: sponsor,
        force: true,
        plan_subscription: sponsor_item.plan_subscription,
      )

      new_sponsor_item = sponsorship.reload.subscription_item

      refute_equal sponsor_item, new_sponsor_item
      assert_equal low_tier, sponsorship.tier
      assert_equal new_sponsor_item.subscribable_id, sponsorship.subscribable_id
    end

    test "generates a hydro event when scheduling a sponsorship cancellation", skip_enterprise: true do
      sponsorship = create(:sponsorship)
      sponsor_item = sponsorship.subscription_item
      sponsor = sponsor_item.account

      Billing::SubscriptionItemUpdater.perform \
        subscribable: sponsor_item.subscribable,
        quantity: 0,
        sender: sponsor,
        plan_subscription: sponsor_item.plan_subscription

      assert_hydro_messages(count: 1, schema: "github.sponsors.v1.SponsorshipPendingChange")
      assert_hydro_published({
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        sponsorship: Hydro::EntitySerializer.sponsorship(sponsorship),
        old_tier: Hydro::EntitySerializer.sponsors_tier(sponsor_item.subscribable),
        new_tier: nil,
        listing: Hydro::EntitySerializer.sponsors_listing(sponsor_item.subscribable.sponsors_listing),
        action: :CREATE,
        actor: Hydro::EntitySerializer.user(sponsor),
      }, schema: "github.sponsors.v1.SponsorshipPendingChange")
    end

    test "the sponsorship remains active when scheduling a sponsorship cancellation", skip_enterprise: true do
      sponsorship = create(:sponsorship)
      sponsor_item = sponsorship.subscription_item
      sponsor = sponsor_item.account

      assert_predicate sponsorship, :active?

      Billing::SubscriptionItemUpdater.perform \
        subscribable: sponsor_item.subscribable,
        quantity: 0,
        sender: sponsor,
        plan_subscription: sponsor_item.plan_subscription

      assert_predicate sponsorship.reload, :active?
    end

    test "enqueues job to revoke sponsor's access to repository granted by sponsorship being cancelled" do
      sponsorable = create(:organization, :sponsorable)
      repo = create(:private_repository, owner: sponsorable, created_by_user_id: sponsorable.admin.id)
      tier_with_repo = create(:sponsors_tier, :published, sponsors_listing: sponsorable.sponsors_listing,
        repository: repo)
      sponsorship = create(:sponsorship, tier: tier_with_repo)
      sponsor_item = sponsorship.subscription_item
      sponsor = sponsorship.sponsor
      create(:sponsorship_repository, repository: repo, sponsors_tier: tier_with_repo, sponsorable: sponsorable,
        sponsor: sponsor)

      RevokeSponsorsOnlyRepositoryAccessJob.expects(:perform_later)
        .with(sponsorship.sponsor_id, repo.id, tier_with_repo.id).once

      Billing::SubscriptionItemUpdater.perform(subscribable: tier_with_repo, quantity: 0,
        sender: sponsor, force: true, plan_subscription: sponsor_item.plan_subscription)
    end

    test "generates a Hydro event when forcing a sponsorship cancellation", skip_enterprise: true do
      sponsorship = create(:sponsorship)
      assert_hydro_messages(count: 1, schema: "github.sponsors.v1.SponsorshipCreateCancel")

      sponsor_item = sponsorship.subscription_item
      sponsor = sponsor_item.account
      listing = sponsor_item.subscribable.sponsors_listing

      Billing::SubscriptionItemUpdater.perform \
        subscribable: sponsor_item.subscribable,
        quantity: 0,
        sender: sponsor,
        force: true,
        plan_subscription: sponsor_item.plan_subscription

      refute_predicate sponsorship.reload, :active?
      assert_predicate sponsor_item.reload, :cancelled?

      assert_hydro_messages(count: 2, schema: "github.sponsors.v1.SponsorshipCreateCancel")
      assert_hydro_published({
        actor: Hydro::EntitySerializer.user(sponsor),
        sponsorship: Hydro::EntitySerializer.sponsorship(sponsorship),
        listing: Hydro::EntitySerializer.sponsors_listing(listing),
        tier: Hydro::EntitySerializer.sponsors_tier(sponsor_item.subscribable),
        action: :CANCEL,
        invoiced: false,
        listing_stafftools_metadata: Hydro::EntitySerializer.sponsors_listing_stafftools_metadata(
          listing.stafftools_metadata,
        ),
        payment_source: :GITHUB,
      }, schema: "github.sponsors.v1.SponsorshipCreateCancel")
    end

    test "generates a hydro event for sponsorship cancellation with an active goal", skip_enterprise: true do
      sponsorship = create(:sponsorship)
      assert_hydro_messages(count: 1, schema: "github.sponsors.v1.SponsorshipCreateCancel")

      sponsor_item = sponsorship.subscription_item
      sponsor = sponsor_item.account
      listing = sponsor_item.subscribable.sponsors_listing
      goal = create(:sponsors_goal, :active, listing: listing, target_value: 100)

      Billing::SubscriptionItemUpdater.perform \
        subscribable: sponsor_item.subscribable,
        quantity: 0,
        sender: sponsor,
        force: true,
        plan_subscription: sponsor_item.plan_subscription

      assert_hydro_messages(count: 2, schema: "github.sponsors.v1.SponsorshipCreateCancel")
      assert_hydro_published({
        actor: Hydro::EntitySerializer.user(sponsor),
        sponsorship: Hydro::EntitySerializer.sponsorship(sponsorship),
        listing: Hydro::EntitySerializer.sponsors_listing(listing),
        tier: Hydro::EntitySerializer.sponsors_tier(sponsor_item.subscribable),
        action: :CANCEL,
        goal: Hydro::EntitySerializer.sponsors_goal(goal),
        invoiced: false,
        listing_stafftools_metadata: Hydro::EntitySerializer.sponsors_listing_stafftools_metadata(
          listing.stafftools_metadata,
        ),
        payment_source: :GITHUB,
      }, schema: "github.sponsors.v1.SponsorshipCreateCancel")
    end

    test "deactivates the sponsorship when forcing a sponsorship cancellation", skip_enterprise: true do
      sponsorship = create(:sponsorship)
      sponsor_item = sponsorship.subscription_item
      sponsor = sponsor_item.account
      events = subscribe "sponsors.sponsor_sponsorship_cancel"

      assert_predicate sponsorship, :active?

      Billing::SubscriptionItemUpdater.perform \
        subscribable: sponsor_item.subscribable,
        quantity: 0,
        sender: sponsor,
        force: true,
        plan_subscription: sponsor_item.plan_subscription

      refute_predicate sponsorship.reload, :active?

      expected_payload = {
        sponsorship_id: sponsorship.id,
        sponsor: sponsor.login,
        sponsor_id: sponsor.id,
        actor: sponsor.login,
        actor_id: sponsor.id,
        user: sponsor.login,
        user_id: sponsor.id,
        public: true,
        active: false,
        frequency: "recurring",
        sponsorable_user: sponsorship.sponsorable_login,
        sponsorable_user_id: sponsorship.sponsorable_id,
        current_tier_id: sponsor_item.subscribable.id,
        current_tier_monthly_amount_in_cents: sponsorship.monthly_price_in_cents,
        payment_source: "github",
      }
      refute_nil event = events.pop, "should have had an event"
      assert_equal expected_payload, event.payload
    end

    test "generates a hydro event when changing a sponsors tier", skip_enterprise: true do
      listing = create(:sponsors_listing, :approved)
      low_tier = listing.sponsors_tiers.order(:monthly_price_in_cents).first

      high_tier = create(
        :sponsors_tier,
        :published,
        sponsors_listing: listing,
        monthly_price_in_cents: low_tier.monthly_price_in_cents + 100,
        yearly_price_in_cents: (low_tier.monthly_price_in_cents + 100) * 12,
      )

      sponsorship = create(:sponsorship, tier: low_tier, sponsorable: listing.sponsorable)
      sponsor_item = sponsorship.subscription_item
      sponsor = sponsor_item.account

      Billing::SubscriptionItemUpdater.perform \
        subscribable: high_tier,
        quantity: 1,
        sender: sponsor,
        plan_subscription: sponsor_item.plan_subscription

      assert_hydro_messages(count: 1, schema: "github.sponsors.v1.SponsorshipTierChange")
    end

    test "generates a hydro event when changing a sponsors tier with an active goal", skip_enterprise: true do
      listing = create(:sponsors_listing, :approved)
      low_tier = create(
        :sponsors_tier,
        :published,
        sponsors_listing: listing,
        monthly_price_in_cents: 1_00,
        yearly_price_in_cents: 12_00,
      )

      high_tier = create(
        :sponsors_tier,
        :published,
        sponsors_listing: listing,
        monthly_price_in_cents: 5_00,
        yearly_price_in_cents: 60_00,
      )

      goal = create(:sponsors_goal, :active, listing: listing, target_value: 100)
      listing.reload

      sponsorship = create(:sponsorship, tier: low_tier, sponsorable: listing.sponsorable)
      sponsor_item = sponsorship.subscription_item
      sponsor = sponsor_item.account

      Billing::SubscriptionItemUpdater.perform \
        subscribable: high_tier,
        quantity: 1,
        sender: sponsor,
        plan_subscription: sponsor_item.plan_subscription

      assert_hydro_messages(count: 1, schema: "github.sponsors.v1.SponsorshipTierChange")
      assert_hydro_published({
        actor: Hydro::EntitySerializer.user(sponsor),
        sponsorship: Hydro::EntitySerializer.sponsorship(sponsorship),
        listing: Hydro::EntitySerializer.sponsors_listing(listing),
        previous_tier: Hydro::EntitySerializer.sponsors_tier(low_tier),
        current_tier: Hydro::EntitySerializer.sponsors_tier(high_tier),
        goal: Hydro::EntitySerializer.sponsors_goal(goal),
      }, schema: "github.sponsors.v1.SponsorshipTierChange")
    end

    test "the sponsorship remains active when upgrading a sponsorship", skip_enterprise: true do
      listing = create(:sponsors_listing, :approved)
      low_tier = create(
        :sponsors_tier,
        :published,
        sponsors_listing: listing,
        monthly_price_in_cents: 1_00,
        yearly_price_in_cents: 12_00,
      )

      high_tier = create(
        :sponsors_tier,
        :published,
        sponsors_listing: listing,
        monthly_price_in_cents: 5_00,
        yearly_price_in_cents: 60_00,
      )

      sponsorship = create(:sponsorship, tier: low_tier, sponsorable: listing.sponsorable)
      sponsor_item = sponsorship.subscription_item
      sponsor = sponsor_item.account

      assert_predicate sponsorship, :active?

      Billing::SubscriptionItemUpdater.perform \
        subscribable: high_tier,
        quantity: 1,
        sender: sponsor,
        plan_subscription: sponsor_item.plan_subscription

      assert_predicate sponsorship.reload, :active?
    end

    test "the sponsorship subscribable updates when upgrading a sponsorship", skip_enterprise: true do
      listing = create(:sponsors_listing, :approved)
      low_tier = create(
        :sponsors_tier,
        :published,
        sponsors_listing: listing,
        monthly_price_in_cents: 1_00,
        yearly_price_in_cents: 12_00,
      )

      high_tier = create(
        :sponsors_tier,
        :published,
        sponsors_listing: listing,
        monthly_price_in_cents: 5_00,
        yearly_price_in_cents: 60_00,
      )

      sponsorship = create(:sponsorship, tier: low_tier, sponsorable: listing.sponsorable)
      sponsor_item = sponsorship.subscription_item
      sponsor = sponsor_item.account

      Billing::SubscriptionItemUpdater.perform \
        subscribable: high_tier,
        quantity: 1,
        sender: sponsor,
        plan_subscription: sponsor_item.plan_subscription

      new_sponsor_item = sponsorship.reload.subscription_item

      refute_equal sponsor_item, new_sponsor_item
      assert_equal high_tier, sponsorship.tier
      assert_equal new_sponsor_item.subscribable_id, sponsorship.subscribable_id
    end

    test "expires_at is nilled when changing from one-time to recurring sponsorship", skip_enterprise: true do
      sponsorship = create(:sponsorship, :one_time)
      sponsorable = sponsorship.sponsorable
      listing = sponsorable.sponsors_listing
      recurring_tier = create(:sponsors_tier, :published, sponsors_listing: listing)
      sponsor_item = sponsorship.subscription_item
      sponsor = sponsor_item.account

      assert_predicate sponsorship, :one_time_payment?
      refute_nil sponsorship.expires_at

      travel (Sponsorship::LOCK_CUTOFF_IN_DAYS + 1).days do
        Billing::SubscriptionItemUpdater.perform \
          subscribable: recurring_tier,
          quantity: 1,
          sender: sponsor,
          plan_subscription: sponsor_item.plan_subscription
      end

      new_sponsor_item = sponsorship.reload.subscription_item

      refute_equal sponsor_item, new_sponsor_item
      assert_equal recurring_tier, sponsorship.tier
      assert_equal new_sponsor_item.subscribable_id, sponsorship.subscribable_id
      assert_nil sponsorship.expires_at
    end

    test "does not cancel enterprise-billed sponsorship when org-billed sponsorship cancelled", skip_enterprise: true do
      sponsorship = create(:sponsorship, :from_org)
      sponsor = sponsorship.sponsor
      subscribable = sponsorship.tier
      org_sub_item = sponsorship.subscription_item
      business = create(:business, :with_self_serve_payment)
      business.add_organization(sponsor)
      sponsor.reload
      ent_sub_item = create(:sponsors_subscription_item, account: sponsor, subscribable: subscribable)
      sponsorship.update_subscription_item(ent_sub_item)

      Billing::SubscriptionItemUpdater.perform(
        force: true,
        subscribable: subscribable,
        quantity: 0,
        sender: ent_sub_item.managing_entity,
        plan_subscription: org_sub_item.plan_subscription
      )

      assert_predicate sponsorship.reload, :active?
    end

    test "cancels a free marketplace purchase immediately" do
      item = create :billing_subscription_item, :free
      account = item.account

      hook = create :hook, :web,
        installation_target: item.listing,
        events: %w(marketplace_purchase)
      deliveries = subscribe_to_hook_delivery "marketplace_purchase"

      with_hook_delivery do
        assert_no_difference "Billing::PendingSubscriptionItemChange.count" do
          Billing::SubscriptionItemUpdater.perform \
            subscribable: item.subscribable,
            quantity: 0,
            sender: account,
            plan_subscription: item.plan_subscription
        end
      end

      assert_equal 0, item.reload.quantity

      payload = deliveries.payload_for_hook(hook)
      assert_equal "cancelled", payload[:action]
    end

    test "sends webhook when applying a cancellation" do
      item = create :billing_subscription_item, quantity: 4
      account = item.account

      hook = create :hook, :web,
        installation_target: item.listing,
        events: %w(marketplace_purchase)
      deliveries = subscribe_to_hook_delivery "marketplace_purchase"

      with_hook_delivery do
        Billing::SubscriptionItemUpdater.perform \
          force: true,
          subscribable: item.subscribable,
          quantity: 0,
          sender: account,
          plan_subscription: item.plan_subscription
      end

      assert_equal 1, deliveries.count
      assert_includes deliveries.hooks, hook

      payload = deliveries.payload_for_hook(hook)
      assert_equal "cancelled", payload[:action]
    end

    test "sends webhook when applying a cancellation for a free trial" do
      listing_plan = create(:marketplace_listing_plan, :published, has_free_trial: true)
      item = create :billing_subscription_item,
        :free_trial,
        subscribable: listing_plan,
        quantity: 4,
        free_trial_ends_on: GitHub::Billing.today + 2.weeks
      account = item.account

      with_hook_delivery do
        Billing::SubscriptionItemUpdater.perform \
          subscribable: listing_plan,
          start_free_trial: true,
          quantity: 1,
          sender: account,
          plan_subscription: item.plan_subscription
      end

      assert item.on_free_trial?
      deliveries = subscribe_to_hook_delivery "marketplace_purchase"

      assert_equal 0, deliveries.count

      hook = create :hook, :web,
        installation_target: item.listing,
        events: %w(marketplace_purchase)
      deliveries = subscribe_to_hook_delivery "marketplace_purchase"

      with_hook_delivery do
        Billing::SubscriptionItemUpdater.perform \
          subscribable: item.subscribable,
          quantity: 0,
          sender: account,
          plan_subscription: item.plan_subscription
      end

      assert_equal 1, deliveries.count
      assert_includes deliveries.hooks, hook

      payload = deliveries.payload_for_hook(hook)
      assert_equal "cancelled", payload[:action]
    end

    test "schedules the free trial end for 14 days from starting" do
      plan = create :marketplace_listing_plan, :published,
        listing: @listing,
        monthly_price_in_cents: 5_00,
        yearly_price_in_cents: 60_00,
        has_free_trial: true

      item = create :billing_subscription_item, subscribable: plan
      account = item.account

      assert_difference "Billing::PendingSubscriptionItemChange.count", 1 do
        Billing::SubscriptionItemUpdater.perform \
          subscribable: plan,
          start_free_trial: true,
          quantity: 1,
          sender: account,
          plan_subscription: item.plan_subscription
      end

      change = account.pending_subscription_item_changes.first
      # active the day after the free trial ends
      assert_equal GitHub::Billing.today + 15.days, change.active_on
      assert_equal 1, change.quantity
    end

    test "ends trial even if pending change is missing" do
      marketplace_item = create(:billing_subscription_item, :free_trial)
      assert marketplace_item.on_free_trial?

      update = Billing::SubscriptionItemUpdater.perform(
        force: true,
        subscribable: marketplace_item.subscribable,
        quantity: 0,
        sender: marketplace_item.account,
        end_free_trial: true,
        plan_subscription: marketplace_item.plan_subscription,
        skip_sync: true
      )

      # assert
      assert update.result.success
      refute marketplace_item.reload.on_free_trial?
    end

    test "deletes associated pending free trial activations when plan is cancelled" do
      plan = create :marketplace_listing_plan, :published,
        listing: @listing,
        monthly_price_in_cents: 5_00,
        yearly_price_in_cents: 60_00,
        has_free_trial: true

      freeze_time do
        item = create :billing_subscription_item, subscribable: plan
        account = item.account

        Billing::SubscriptionItemUpdater.perform \
          subscribable: plan,
          start_free_trial: true,
          quantity: 1,
          sender: account,
          plan_subscription: item.plan_subscription

        assert_equal GitHub::Billing.today + Billing::Subscription::FREE_TRIAL_LENGTH, item.free_trial_ends_on
        assert_equal 1, account.pending_subscription_item_changes.count
        assert_equal 1, account.pending_plan_changes.count

        pending_plan_change = account.pending_subscription_item_changes.first.pending_plan_change
        assert_equal account.pending_plan_changes.first, pending_plan_change

        assert_difference "Billing::PendingSubscriptionItemChange.count", -1 do
          Billing::SubscriptionItemUpdater.perform \
            subscribable: plan,
            quantity: 0,
            sender: account,
            plan_subscription: item.plan_subscription
        end

        account.reload
        assert_equal GitHub::Billing.yesterday, item.reload.free_trial_ends_on
        assert_equal [], account.pending_subscription_item_changes
        assert_equal [], account.pending_plan_changes
      end
    end

    test "continues the free trial when switching between free trial plans" do
      plan_a = create :marketplace_listing_plan, :published,
        listing: @listing,
        monthly_price_in_cents: 5_00,
        yearly_price_in_cents: 60_00,
        has_free_trial: true

      plan_b = create :marketplace_listing_plan, :published,
        listing: @listing,
        monthly_price_in_cents: 10_00,
        yearly_price_in_cents: 100_00,
        has_free_trial: true

      item = create :billing_subscription_item, subscribable: plan_a
      account = item.account

      assert_difference "Billing::PendingSubscriptionItemChange.count", 1 do
        Billing::SubscriptionItemUpdater.perform \
          subscribable: plan_a,
          start_free_trial: true,
          quantity: 1,
          sender: account,
          plan_subscription: item.plan_subscription
      end

      change = account.pending_subscription_item_changes.first
      assert_equal GitHub::Billing.today + 15.days, change.active_on
      assert_equal 1, change.quantity

      assert_no_difference "Billing::PendingSubscriptionItemChange.count" do
        Billing::SubscriptionItemUpdater.perform \
          subscribable: plan_b,
          quantity: 1,
          sender: account,
          plan_subscription: item.plan_subscription
      end
      account.reload
      new_change = account.pending_subscription_item_changes.first
      new_item = account.subscription_items.last

      refute_equal change, new_change
      assert_equal GitHub::Billing.today + 15.days, new_change.active_on
      assert_equal 1, change.quantity

      refute_equal item, new_item
      assert new_item.on_free_trial?
      assert_equal plan_b, new_item.subscribable
    end

    test "doesn't create a new pending change when switching trial quantity" do
      plan = create :marketplace_listing_plan, :published,
        listing: @listing,
        monthly_price_in_cents: 5_00,
        yearly_price_in_cents: 60_00,
        has_free_trial: true

      item = create :billing_subscription_item, subscribable: plan
      account = item.account

      assert_difference "Billing::PendingSubscriptionItemChange.count", 1 do
        Billing::SubscriptionItemUpdater.perform \
          subscribable: plan,
          start_free_trial: true,
          quantity: 1,
          sender: account,
          plan_subscription: item.plan_subscription
      end

      change = account.pending_subscription_item_changes.first
      assert_equal GitHub::Billing.today + 15.days, change.active_on
      assert_equal 1, change.quantity

      assert_no_difference "Billing::PendingSubscriptionItemChange.count" do
        Billing::SubscriptionItemUpdater.perform \
          subscribable: plan,
          quantity: 2,
          sender: account,
          plan_subscription: item.plan_subscription
      end
      account.reload
      new_change = account.pending_subscription_item_changes.last

      assert_equal change, new_change
      assert_equal 2, new_change.quantity
    end

    test "changing plans from free trial to paid ends free trial period" do
      plan_a = create :marketplace_listing_plan, :published,
        listing: @listing,
        monthly_price_in_cents: 5_00,
        yearly_price_in_cents: 60_00,
        has_free_trial: true

      plan_b = create :marketplace_listing_plan, :published,
        listing: @listing,
        monthly_price_in_cents: 10_00,
        yearly_price_in_cents: 100_00,
        has_free_trial: false

      item = create :billing_subscription_item, subscribable: plan_a
      account = item.account

      assert_difference "Billing::PendingSubscriptionItemChange.count", 1 do
        Billing::SubscriptionItemUpdater.perform \
          subscribable: plan_a,
          start_free_trial: true,
          quantity: 1,
          sender: account,
          plan_subscription: item.plan_subscription
      end

      change = account.pending_subscription_item_changes.first
      assert_equal GitHub::Billing.today + 15.days, change.active_on
      assert_equal 1, change.quantity

      assert_difference "Billing::PendingSubscriptionItemChange.count", -1 do
        Billing::SubscriptionItemUpdater.perform \
          subscribable: plan_b,
          quantity: 1,
          sender: account,
          plan_subscription: item.plan_subscription
      end

      account.reload
      new_item = account.subscription_items.last

      refute_equal item, new_item
      refute new_item.on_free_trial?
      refute item.reload.on_free_trial?
      assert_equal plan_b, new_item.subscribable
    end

    test "does not allow a free trial when switching between free trial plans and free trial is over" do
      plan_a = create :marketplace_listing_plan, :published,
        listing: @listing,
        monthly_price_in_cents: 5_00,
        yearly_price_in_cents: 60_00,
        has_free_trial: true

      plan_b = create :marketplace_listing_plan, :published,
        listing: @listing,
        monthly_price_in_cents: 10_00,
        yearly_price_in_cents: 100_00,
        has_free_trial: true

      item = create :billing_subscription_item, subscribable: plan_a
      account = item.account

      assert_difference "Billing::PendingSubscriptionItemChange.count", 1 do
        Billing::SubscriptionItemUpdater.perform \
          subscribable: plan_a,
          start_free_trial: true,
          quantity: 1,
          sender: account,
          plan_subscription: item.plan_subscription
      end

      change = account.pending_subscription_item_changes.first
      assert_equal GitHub::Billing.today + 15.days, change.active_on
      assert_equal 1, change.quantity

      travel_to(item.free_trial_ends_on.in_time_zone(GitHub::Billing.timezone) + 1.day) do
        assert_difference "Billing::PendingSubscriptionItemChange.count", -1 do
          Billing::SubscriptionItemUpdater.perform \
            subscribable: plan_b,
            quantity: 1,
            sender: account,
            plan_subscription: item.plan_subscription
        end
        account.reload
        new_item = account.subscription_items.last

        refute_equal item, new_item
        refute new_item.on_free_trial?
        assert_equal plan_b, new_item.subscribable
      end
    end

    test "sends webhook when free trial ends" do
      plan = create :marketplace_listing_plan, :published,
        listing: @listing,
        monthly_price_in_cents: 5_00,
        yearly_price_in_cents: 60_00,
        has_free_trial: true

      item = create :billing_subscription_item, subscribable: plan
      account = item.account

      deliveries = subscribe_to_hook_delivery "marketplace_purchase"

      with_hook_delivery do
        Billing::SubscriptionItemUpdater.perform \
          subscribable: plan,
          start_free_trial: true,
          quantity: 1,
          sender: account,
          plan_subscription: item.plan_subscription
      end

      assert_equal 0, deliveries.count

      hook = create :hook, :web,
        installation_target: item.listing,
        events: %w(marketplace_purchase)
      deliveries = subscribe_to_hook_delivery "marketplace_purchase"

      with_hook_delivery do
        Billing::SubscriptionItemUpdater.perform \
          force: true,
          subscribable: item.subscribable,
          end_free_trial: true,
          quantity: 1,
          sender: account,
          plan_subscription: item.plan_subscription
      end

      assert_equal 1, deliveries.count
      assert_includes deliveries.hooks, hook

      payload = deliveries.payload_for_hook(hook)
      assert_equal "changed", payload[:action]
      assert_equal GitHub::Billing.today.to_datetime, payload[:effective_date]
      assert_equal plan.id, payload[:marketplace_purchase][:plan][:id]
    end

    test "keeps unrelated pending subscription item changes when a free trial is cancelled" do
      paid_item = create :billing_subscription_item,
        subscribable: @expensive_plan,
        quantity: 10
      account = paid_item.account

      assert_difference "Billing::PendingSubscriptionItemChange.count", 1 do
        Billing::SubscriptionItemUpdater.perform \
          subscribable: @expensive_plan,
          quantity: 4,
          sender: account,
          plan_subscription: paid_item.plan_subscription
      end

      trial_plan = create :marketplace_listing_plan, :published,
        listing: create(:marketplace_listing, :verified),
        monthly_price_in_cents: 5_00,
        yearly_price_in_cents: 60_00,
        has_free_trial: true

      free_trial_item = create :billing_subscription_item,
        subscribable: trial_plan,
        plan_subscription: account.plan_subscription

      Billing::SubscriptionItemUpdater.perform \
        subscribable: trial_plan,
        start_free_trial: true,
        quantity: 1,
        sender: account,
        plan_subscription: free_trial_item.plan_subscription

      assert_equal 2, account.pending_subscription_item_changes.count

      assert_difference "Billing::PendingSubscriptionItemChange.count", -1 do
        Billing::SubscriptionItemUpdater.perform \
          subscribable: trial_plan,
          quantity: 0,
          sender: account,
          plan_subscription: free_trial_item.plan_subscription
      end

      assert_equal 1, account.pending_subscription_item_changes.count
      change = account.pending_cycle_change.pending_subscription_item_changes.first
      assert_equal @expensive_plan, change.subscribable
      assert_equal 4, change.quantity
    end

    test "unsuccessful when there's no subscription item to update" do
      plan_subscription = create(:billing_plan_subscription)
      account = plan_subscription.user

      update = Billing::SubscriptionItemUpdater.perform \
        subscribable: @cheap_plan,
        quantity: 0,
        sender: account,
        plan_subscription: account.plan_subscription

      refute update.result.success
      assert_match(/no subscription item/, update.result.errors.join)
    end

    test "raises error when an invalid account and increasing quantity" do
      paid_item = create :billing_subscription_item,
        subscribable: @expensive_plan,
        quantity: 10
      account = paid_item.account
      account.update_column(:billing_attempts, 4)
      assert_predicate paid_item.plan_subscription.reload_user, :dunning?

      assert_raises ::Platform::Errors::Unprocessable do
        Billing::SubscriptionItemUpdater.perform \
          subscribable: @expensive_plan,
          quantity: 15,
          sender: account,
          plan_subscription: paid_item.plan_subscription
      end
    end

    test "while changing plan, set quantity 0 for old subscription_item" do
      item = create :billing_subscription_item, subscribable: @expensive_plan
      user = item.account
      listing = create(:marketplace_listing, :verified, :with_plans, :integration)

      result = Billing::CreateMarketplaceSubscriptionItem.call(
        listing_plan: listing.listing_plans.first,
        quantity: 1,
        account: user,
        viewer: user,
      )
      old_subscription_item = result[:subscription_item]

      result = Billing::SubscriptionItemUpdater.perform \
        subscribable: listing.listing_plans.second,
        quantity: 1,
        sender: user,
        plan_subscription: item.plan_subscription

      subscription_item = result.subscription_item
      old_subscription_item.reload

      assert_equal old_subscription_item.quantity, 0
      assert_equal subscription_item&.quantity, 1
    end

    test "when user has not already installed app, does not set installed_at while changing plan" do
      item = create :billing_subscription_item, subscribable: @expensive_plan
      user = item.account
      listing = create(:marketplace_listing, :verified, :with_plans, :integration)

      result = Billing::CreateMarketplaceSubscriptionItem.call(
        listing_plan: listing.listing_plans.first,
        quantity: 1,
        account: user,
        viewer: user,
      )
      old_subscription_item = result[:subscription_item]

      result = Billing::SubscriptionItemUpdater.perform \
        subscribable: listing.listing_plans.second,
        quantity: 1,
        sender: user,
        plan_subscription: item.plan_subscription

      subscription_item = T.must(result.subscription_item)
      old_subscription_item.reload

      assert_nil old_subscription_item.installed_at
      assert_nil subscription_item.installed_at
    end

    test "when user has already installed app, set installed_at same as integration installation created_at &
    same subscription_item_id in integration_installation while changing plan" do
      item = create :billing_subscription_item, subscribable: @expensive_plan
      user = item.account
      integration_installation = make_integration_installation(target: user)
      listing = create(:marketplace_listing, :verified, :with_plans, listable: integration_installation.integration)

      result = Billing::CreateMarketplaceSubscriptionItem.call(
        listing_plan: listing.listing_plans.first,
        quantity: 1,
        account: user,
        viewer: user,
      )
      old_subscription_item = result[:subscription_item]

      result = Billing::SubscriptionItemUpdater.perform \
        subscribable: listing.listing_plans.second,
        quantity: 1,
        sender: user,
        plan_subscription: item.plan_subscription

      subscription_item = T.must(result.subscription_item)
      old_subscription_item.reload
      integration_installation.reload

      assert_nil old_subscription_item.installed_at
      assert_equal integration_installation.created_at, subscription_item.installed_at
      assert_equal integration_installation.subscription_item_id, subscription_item.id
    end

    test "updates the free_trial_ends_on to the provided date" do
      free_trial_ends_on = GitHub::Billing.today + 30.days
      item = create :billing_subscription_item,
        subscribable: @monthly_product_uuid,
        quantity: 1,
        free_trial_ends_on: free_trial_ends_on

      account = item.account

      new_free_trial_ends_on = GitHub::Billing.today + 30.days
      Billing::SubscriptionItemUpdater.perform \
        subscribable: @monthly_product_uuid,
        free_trial_ends_on: new_free_trial_ends_on,
        quantity: 1,
        sender: account,
        plan_subscription: item.plan_subscription

      assert_equal new_free_trial_ends_on, item.reload.free_trial_ends_on
    end

    context "self-serve payment enterprise account orgs for marketplace" do
      test "schedules a downgrade when downgrading the plan" do
        item = create :billing_subscription_item, subscribable: @expensive_plan, plan_subscription: @plan_subscription, organization: @org
        assert_difference "Billing::PendingSubscriptionItemChange.count", 1 do
          Billing::SubscriptionItemUpdater.perform \
            subscribable: @cheap_plan,
            quantity: 1,
            sender: @business_admin,
            plan_subscription: item.plan_subscription,
            organization: @org
        end

        change = @business.pending_cycle_change.pending_subscription_item_changes.first
        assert_equal @cheap_plan, change.subscribable
        assert_equal 1, change.quantity
      end

      test "schedules a downgrade when lowering the quantity" do
        item = create :billing_subscription_item,
          subscribable: @expensive_plan,
          quantity: 10,
          plan_subscription: @plan_subscription,
          organization: @org

        hook = create :hook, :web,
          installation_target: item.listing,
          events: %w(marketplace_purchase)
        deliveries = subscribe_to_hook_delivery "marketplace_purchase"

        with_hook_delivery do
          assert_difference "Billing::PendingSubscriptionItemChange.count", 1 do
            Billing::SubscriptionItemUpdater.perform \
              subscribable: @expensive_plan,
              quantity: 4,
              sender: @business_admin,
              plan_subscription: item.plan_subscription,
              organization: @org
          end
        end

        assert_equal 1, deliveries.count
        assert_includes deliveries.hooks, hook
        payload = deliveries.payload_for_hook(hook)
        assert_equal "pending_change", payload[:action]

        change = @business.pending_cycle_change.pending_subscription_item_changes.first
        assert_equal @expensive_plan, change.subscribable
        assert_equal 4, change.quantity
      end

      test "performs upgrade for yearly accounts" do
        item = create :billing_subscription_item,
          subscribable: @expensive_plan,
          quantity: 10,
          plan_subscription: @plan_subscription,
          organization: @org
        @business.update_attribute :plan_duration, "year"

        assert_no_difference "Billing::PendingSubscriptionItemChange.count" do
          Billing::SubscriptionItemUpdater.perform \
            subscribable: @expensive_plan,
            quantity: 12,
            sender: @business_admin,
            plan_subscription: item.plan_subscription,
            organization: @org
        end

        assert_equal 12, item.reload.quantity
      end

      test "overwrites a scheduled downgrade when upgrading" do
        item = create :billing_subscription_item,
          subscribable: @expensive_plan,
          quantity: 10,
          plan_subscription: @plan_subscription,
          organization: @org

        change = create :billing_pending_plan_change,
          user: nil,
          active_on: @business.next_billing_date,
          customer_id: @business.customer.id
        mp_change = create :billing_pending_subscription_item_change,
          subscribable: item.subscribable,
          pending_plan_change: change,
          quantity: 5,
          plan_subscription: @plan_subscription,
          organization: @org

        hook = create :hook, :web,
          installation_target: item.listing,
          events: %w(marketplace_purchase)
        deliveries = subscribe_to_hook_delivery "marketplace_purchase"

        with_hook_delivery do
          assert_no_difference "Billing::PendingSubscriptionItemChange.count" do
            Billing::SubscriptionItemUpdater.perform \
              subscribable: @expensive_plan,
              quantity: 12,
              sender: @business_admin,
              plan_subscription: item.plan_subscription,
              organization: @org
          end
        end

        assert_equal 1, deliveries.count
        assert_includes deliveries.hooks, hook

        payload = deliveries.payload_for_hook(hook)
        assert_equal "changed", payload[:action]

        assert_equal 12, mp_change.reload.quantity
        assert_equal 12, item.reload.quantity
      end

      test "schedules a cancellation for a paid marketplace purchase" do
        item = create :billing_subscription_item,
          subscribable: @expensive_plan,
          quantity: 10,
          plan_subscription: @plan_subscription,
          organization: @org

        assert_difference "Billing::PendingSubscriptionItemChange.count", 1 do
          Billing::SubscriptionItemUpdater.perform \
            subscribable: item.subscribable,
            quantity: 0,
            sender: @business_admin,
            plan_subscription: item.plan_subscription,
            organization: @org
        end

        refute_equal 0, item.reload.quantity
        change = @business.reload.pending_subscription_item_changes.first
        assert_equal 0, change.quantity
        assert_equal item.subscribable, change.subscribable
      end

      test "cancels a free marketplace purchase immediately" do
        item = create :billing_subscription_item, :free,
          plan_subscription: @plan_subscription,
          organization: @org

        hook = create :hook, :web,
          installation_target: item.listing,
          events: %w(marketplace_purchase)
        deliveries = subscribe_to_hook_delivery "marketplace_purchase"

        with_hook_delivery do
          assert_no_difference "Billing::PendingSubscriptionItemChange.count" do
            Billing::SubscriptionItemUpdater.perform \
              subscribable: item.subscribable,
              quantity: 0,
              sender: @business_admin,
              plan_subscription: item.plan_subscription,
              organization: @org
          end
        end

        assert_equal 0, item.reload.quantity

        payload = deliveries.payload_for_hook(hook)
        assert_equal "cancelled", payload[:action]
      end

      test "cancels a marketplace purchase for the specific org immediately when forced" do
        org2 = create :organization, business: @business, admin: @business_admin
        item = create :billing_subscription_item,
          subscribable: @expensive_plan,
          quantity: 10,
          plan_subscription: @plan_subscription,
          organization: @org
        item2 = create :billing_subscription_item,
          subscribable: @expensive_plan,
          quantity: 13,
          plan_subscription: @plan_subscription,
          organization: org2

        assert_no_difference "Billing::PendingSubscriptionItemChange.count" do
          Billing::SubscriptionItemUpdater.perform \
            subscribable: item.subscribable,
            quantity: 0,
            sender: @business_admin,
            plan_subscription: item.plan_subscription,
            organization: @org,
            force: true
        end

        assert_equal 0, item.reload.quantity
        assert_equal 13, item2.reload.quantity
      end

      test "schedules the free trial end for 14 days from starting" do
        plan = create :marketplace_listing_plan, :published,
          listing: @listing,
          monthly_price_in_cents: 5_00,
          yearly_price_in_cents: 60_00,
          has_free_trial: true

        item = create :billing_subscription_item,
          subscribable: plan,
          plan_subscription: @plan_subscription,
          organization: @org

        assert_difference "Billing::PendingSubscriptionItemChange.count", 1 do
          Billing::SubscriptionItemUpdater.perform \
            subscribable: plan,
            start_free_trial: true,
            quantity: 1,
            sender: @business_admin,
            plan_subscription: item.plan_subscription,
            organization: @org
        end

        change = @business.pending_subscription_item_changes.first
        # active the day after the free trial ends
        assert_equal GitHub::Billing.today + 15.days, change.active_on
        assert_equal 1, change.quantity
      end

      test "deletes associated pending free trial activations when plan is cancelled" do
        plan = create :marketplace_listing_plan, :published,
          listing: @listing,
          monthly_price_in_cents: 5_00,
          yearly_price_in_cents: 60_00,
          has_free_trial: true

        freeze_time do
          item = create :billing_subscription_item,
            subscribable: plan,
            plan_subscription: @plan_subscription,
            organization: @org

          Billing::SubscriptionItemUpdater.perform \
            subscribable: plan,
            start_free_trial: true,
            quantity: 1,
            sender: @business_admin,
            plan_subscription: item.plan_subscription,
            organization: @org

          assert_equal GitHub::Billing.today + Billing::Subscription::FREE_TRIAL_LENGTH, item.free_trial_ends_on
          assert_equal 1, @business.pending_subscription_item_changes.count
          assert_equal 1, @business.pending_plan_changes.count

          pending_plan_change = @business.pending_subscription_item_changes.first.pending_plan_change
          assert_equal @business.pending_plan_changes.first, pending_plan_change

          assert_difference "Billing::PendingSubscriptionItemChange.count", -1 do
            Billing::SubscriptionItemUpdater.perform \
              subscribable: plan,
              quantity: 0,
              sender: @business_admin,
              plan_subscription: item.plan_subscription,
              organization: @org
          end

          @business.reload
          assert_equal GitHub::Billing.yesterday, item.reload.free_trial_ends_on
          assert_equal [], @business.pending_subscription_item_changes
          assert_equal [], @business.pending_plan_changes
        end
      end

      test "continues the free trial when switching between free trial plans" do
        plan_a = create :marketplace_listing_plan, :published,
          listing: @listing,
          monthly_price_in_cents: 5_00,
          yearly_price_in_cents: 60_00,
          has_free_trial: true

        plan_b = create :marketplace_listing_plan, :published,
          listing: @listing,
          monthly_price_in_cents: 10_00,
          yearly_price_in_cents: 100_00,
          has_free_trial: true

        item = create :billing_subscription_item,
          subscribable: plan_a,
          plan_subscription: @plan_subscription,
          organization: @org

        assert_difference "Billing::PendingSubscriptionItemChange.count", 1 do
          Billing::SubscriptionItemUpdater.perform \
            subscribable: plan_a,
            start_free_trial: true,
            quantity: 1,
            sender: @business_admin,
            plan_subscription: item.plan_subscription,
            organization: @org
        end

        change = @business.pending_subscription_item_changes.first
        assert_equal GitHub::Billing.today + 15.days, change.active_on
        assert_equal 1, change.quantity

        assert_no_difference "Billing::PendingSubscriptionItemChange.count" do
          Billing::SubscriptionItemUpdater.perform \
            subscribable: plan_b,
            quantity: 1,
            sender: @business_admin,
            plan_subscription: item.plan_subscription,
            organization: @org
        end
        @business.reload
        new_change = @business.pending_subscription_item_changes.first
        new_item = @business.subscription_items.last

        refute_equal change, new_change
        assert_equal GitHub::Billing.today + 15.days, new_change.active_on
        assert_equal 1, change.quantity

        refute_equal item, new_item
        assert new_item.on_free_trial?
        assert_equal plan_b, new_item.subscribable
      end

      test "doesn't create a new pending change when switching trial quantity" do
        plan = create :marketplace_listing_plan, :published,
          listing: @listing,
          monthly_price_in_cents: 5_00,
          yearly_price_in_cents: 60_00,
          has_free_trial: true

        item = create :billing_subscription_item,
          subscribable: plan,
          plan_subscription: @plan_subscription,
          organization: @org

        assert_difference "Billing::PendingSubscriptionItemChange.count", 1 do
          Billing::SubscriptionItemUpdater.perform \
            subscribable: plan,
            start_free_trial: true,
            quantity: 1,
            sender: @business_admin,
            plan_subscription: item.plan_subscription,
            organization: @org
        end

        change = @business.pending_subscription_item_changes.first
        assert_equal GitHub::Billing.today + 15.days, change.active_on
        assert_equal 1, change.quantity

        assert_no_difference "Billing::PendingSubscriptionItemChange.count" do
          Billing::SubscriptionItemUpdater.perform \
            subscribable: plan,
            quantity: 2,
            sender: @business_admin,
            plan_subscription: item.plan_subscription,
            organization: @org
        end
        @business.reload
        new_change = @business.pending_subscription_item_changes.last

        assert_equal change, new_change
        assert_equal 2, new_change.quantity
      end

      test "changing plans from free trial to paid ends free trial period" do
        plan_a = create :marketplace_listing_plan, :published,
          listing: @listing,
          monthly_price_in_cents: 5_00,
          yearly_price_in_cents: 60_00,
          has_free_trial: true

        plan_b = create :marketplace_listing_plan, :published,
          listing: @listing,
          monthly_price_in_cents: 10_00,
          yearly_price_in_cents: 100_00,
          has_free_trial: false

        item = create :billing_subscription_item,
          subscribable: plan_a,
          plan_subscription: @plan_subscription,
          organization: @org

        assert_difference "Billing::PendingSubscriptionItemChange.count", 1 do
          Billing::SubscriptionItemUpdater.perform \
            subscribable: plan_a,
            start_free_trial: true,
            quantity: 1,
            sender: @business_admin,
            plan_subscription: item.plan_subscription,
            organization: @org
        end

        change = @business.pending_subscription_item_changes.first
        assert_equal GitHub::Billing.today + 15.days, change.active_on
        assert_equal 1, change.quantity

        assert_difference "Billing::PendingSubscriptionItemChange.count", -1 do
          Billing::SubscriptionItemUpdater.perform \
            subscribable: plan_b,
            quantity: 1,
            sender: @business_admin,
            plan_subscription: item.plan_subscription,
            organization: @org
        end

        @business.reload
        new_item = @business.subscription_items.last

        refute_equal item, new_item
        refute new_item.on_free_trial?
        refute item.reload.on_free_trial?
        assert_equal plan_b, new_item.subscribable
      end

      test "keeps unrelated pending subscription item changes when a free trial is cancelled" do
        paid_item = create :billing_subscription_item,
          subscribable: @expensive_plan,
          quantity: 10,
          plan_subscription: @plan_subscription,
          organization: @org

        assert_difference "Billing::PendingSubscriptionItemChange.count", 1 do
          Billing::SubscriptionItemUpdater.perform \
            subscribable: @expensive_plan,
            quantity: 4,
            sender: @business_admin,
            plan_subscription: paid_item.plan_subscription,
            organization: @org
        end

        trial_plan = create :marketplace_listing_plan, :published,
          listing: create(:marketplace_listing, :verified),
          monthly_price_in_cents: 5_00,
          yearly_price_in_cents: 60_00,
          has_free_trial: true

        free_trial_item = create :billing_subscription_item,
          subscribable: trial_plan,
          plan_subscription: @plan_subscription,
          organization: @org

        Billing::SubscriptionItemUpdater.perform \
          subscribable: trial_plan,
          start_free_trial: true,
          quantity: 1,
          sender: @business_admin,
          plan_subscription: free_trial_item.plan_subscription,
          organization: @org

        assert_equal 2, @business.pending_subscription_item_changes.count

        assert_difference "Billing::PendingSubscriptionItemChange.count", -1 do
          Billing::SubscriptionItemUpdater.perform \
            subscribable: trial_plan,
            quantity: 0,
            sender: @business_admin,
            plan_subscription: free_trial_item.plan_subscription,
            organization: @org
        end

        assert_equal 1, @business.pending_subscription_item_changes.count
        change = @business.pending_cycle_change.pending_subscription_item_changes.first
        assert_equal @expensive_plan, change.subscribable
        assert_equal 4, change.quantity
      end

      test "unsuccessful when there's no subscription item to update" do
        update = Billing::SubscriptionItemUpdater.perform \
          subscribable: @cheap_plan,
          quantity: 0,
          sender: @business_admin,
          plan_subscription: @plan_subscription,
          organization: @org

        refute update.result.success
        assert_match(/no subscription item/, update.result.errors.join)
      end
    end
  end
end
