# typed: true
# frozen_string_literal: true

require "test_helper"

class HookPayloadMarketplacePurchasePayloadTest < GitHub::TestCase
  include GitHub::BillingTest
  include GitHub::BrainTree::TestHelper
  include GitHub::ZuoraTestHelper

  fixtures do
    @item = create :billing_subscription_item, quantity: 3
    @account = @item.account
    @plan = @item.subscribable
    @sender = create(:user)
  end

  context "v3" do
    test "when the marketplace subscription is purchased by an invoiced org" do
      Timecop.freeze(GitHub::Billing.timezone.local(2013, 3, 1)) do
        user = create(:user)
        org = create(:invoiced_org, admin: user)
        plan_subscription = create(:billing_plan_subscription, user: org)
        @item = create(:billing_subscription_item, plan_subscription: plan_subscription, quantity: 3)
        subscribed_plan = @item.subscribable
        @sender = user

        payload = build_marketplace_purchase_payload(action: :purchased)
        v3 = payload.to_hash

        assert_equal :purchased, v3[:action]
        assert_equal "2013-03-01T00:00:00+00:00", v3[:effective_date]
        assert_equal @sender.id, v3[:sender][:id]
        assert_equal @sender.email, v3[:sender][:email]

        purchase = v3[:marketplace_purchase]

        assert_equal 3, purchase[:unit_count]
        assert_equal "monthly", purchase[:billing_cycle]
        assert_equal "2013-03-01T00:00:00+00:00", purchase[:next_billing_date]
        assert_equal false, purchase[:on_free_trial]

        account = purchase[:account]
        assert_equal org.id, account[:id]
        assert_equal "Organization", account[:type]
        assert_equal org.login, account[:login]

        plan = purchase[:plan]
        assert_equal subscribed_plan.id, plan[:id]
        assert_equal subscribed_plan.name, plan[:name]
        assert_equal subscribed_plan.description, plan[:description]
        assert_equal subscribed_plan.monthly_price_in_cents, plan[:monthly_price_in_cents]
        assert_equal subscribed_plan.yearly_price_in_cents, plan[:yearly_price_in_cents]
        assert_equal subscribed_plan.price_model, plan[:price_model]
        assert_equal subscribed_plan.has_free_trial?, plan[:has_free_trial]
        assert_equal [], plan[:bullets]
      end
    end

    test "when the marketplace subscription is purchased" do
      synchronize_github_products_to_zuora
      user = create(:user, :zuora, plan: "pro")
      zuora_successful_customer_account_creation(user)

      Timecop.freeze(GitHub::Billing.timezone.local(2020, 3, 1)) do
        with_live_zuora("zuora/marketplace_purchase_payload") do
          zuora_transaction = Billing::Zuora::Payment.find("2c92c0fa68e558130168f288cfb63731")

          plan_subscription = user.plan_subscription
          Billing::PlanSubscription::ZuoraSynchronizer.create(plan_subscription, false)
          plan_subscription.reload

          @item = create(:billing_subscription_item, plan_subscription: plan_subscription, quantity: 3)
          assert plan_subscription.zuora_subscription, "No Zuora subscription on plan subscription: #{plan_subscription.errors.full_messages.join(", ")}"

          @account = @item.account
          @plan = @item.subscribable
          @sender = create(:user)
          Billing::PlanSubscription::CreateBillingTransaction.perform(
            @item.plan_subscription,
            service_ends_at: @item.plan_subscription.zuora_subscription.next_billing_date,
            zuora_transaction: zuora_transaction,
          )

          payload = build_marketplace_purchase_payload(action: :purchased)
          v3 = payload.to_hash

          assert_equal :purchased, v3[:action]
          assert_equal "2020-03-01T00:00:00+00:00", v3[:effective_date]
          assert_equal @sender.id, v3[:sender][:id]
          assert_equal @sender.email, v3[:sender][:email]

          purchase = v3[:marketplace_purchase]

          assert_equal 3, purchase[:unit_count]
          assert_equal "monthly", purchase[:billing_cycle]
          assert_equal "2019-03-08T00:00:00+00:00", purchase[:next_billing_date]
          assert_equal false, purchase[:on_free_trial]

          account = purchase[:account]
          assert_equal @account.id, account[:id]
          assert_equal "User", account[:type]
          assert_equal @account.login, account[:login]

          plan = purchase[:plan]
          assert_equal @plan.id, plan[:id]
          assert_equal @plan.name, plan[:name]
          assert_equal @plan.description, plan[:description]
          assert_equal @plan.monthly_price_in_cents, plan[:monthly_price_in_cents]
          assert_equal @plan.yearly_price_in_cents, plan[:yearly_price_in_cents]
          assert_equal @plan.price_model, plan[:price_model]
          assert plan.has_key?(:unit_name), "expected unit name to be a key in payload #{plan}"
          assert_equal @plan.has_free_trial?, plan[:has_free_trial]
          assert_equal [], plan[:bullets]
        end
      end
    end

    test "when the marketplace subscription is cancelled" do
      payload = build_marketplace_purchase_payload(action: :cancelled)
      v3 = payload.to_hash

      assert_equal :cancelled, v3[:action]
      assert_equal @sender.id, v3[:sender][:id]
    end

    test "when the marketplace_purchase subscription is upgraded" do
      Timecop.freeze(GitHub::Billing.timezone.local(2013, 3, 1)) do
        previous_item = create :billing_subscription_item, quantity: 2
        payload = build_marketplace_purchase_payload \
          action: :changed,
          previous_subscribable_id: previous_item.subscribable.id,
          previous_subscribable_type: previous_item.subscribable.class.name,
          previous_quantity: 2
        v3 = payload.to_hash

        assert_equal :changed, v3[:action]
        assert_equal "2013-03-01T00:00:00+00:00", v3[:effective_date]

        previous_purchase = v3[:previous_marketplace_purchase]
        assert_equal 2, previous_purchase[:unit_count]

        plan = previous_purchase[:plan]
        assert_equal previous_item.subscribable.id, plan[:id]
      end
    end

    test "when the marketplace_purchase subscription is downgraded to a cheaper plan" do
      Timecop.freeze(GitHub::Billing.timezone.local(2013, 3, 1)) do
        cheaper_listing_plan = create(:marketplace_listing_plan, listing: @item.subscribable.listing)
        pending_plan_change = create(:billing_pending_plan_change, user: @sender, active_on: 3.days.from_now)
        pending_subscription_item_change = pending_plan_change.
          pending_subscription_item_changes.
          create(subscribable: cheaper_listing_plan, quantity: 2, plan_subscription: create(:billing_plan_subscription, user: @sender))

        payload = build_marketplace_purchase_payload \
          action: :pending_change,
          sender_id: @sender.id,
          subscription_item_id: @item.id,
          pending_subscription_item_change_id: pending_subscription_item_change.id

        v3 = payload.to_hash

        assert_equal :pending_change, v3[:action]

        # should use the pending_change's active_on instead of now
        assert_equal "2013-03-04T00:00:00+00:00", v3[:effective_date]

        upcoming_purchase = v3[:marketplace_purchase]
        assert_equal 2, upcoming_purchase[:unit_count]

        current_purchase = v3[:previous_marketplace_purchase]
        assert_equal 3, current_purchase[:unit_count]

        # plan is unchanged
        plan = current_purchase[:plan]
        assert_equal @item.subscribable.id, plan[:id]

        # plan is updated
        plan = upcoming_purchase[:plan]
        assert_equal cheaper_listing_plan.id, plan[:id]
      end
    end

    test "when the marketplace_purchase subscription is downgraded to fewer units" do
      Timecop.freeze(GitHub::Billing.timezone.local(2013, 3, 1)) do
        pending_plan_change = create(:billing_pending_plan_change, user: @sender, active_on: 3.days.from_now)
        pending_subscription_item_change = pending_plan_change.
          pending_subscription_item_changes.
          create(subscribable: @plan, quantity: 2, plan_subscription: create(:billing_plan_subscription, user: @sender))

        payload = build_marketplace_purchase_payload \
          action: :pending_change,
          sender_id: @sender.id,
          subscription_item_id: @item.id,
          pending_subscription_item_change_id: pending_subscription_item_change.id

        v3 = payload.to_hash

        assert_equal :pending_change, v3[:action]

        # should use the pending_change's active_on instead of now
        assert_equal "2013-03-04T00:00:00+00:00", v3[:effective_date]

        upcoming_purchase = v3[:marketplace_purchase]
        assert_equal 2, upcoming_purchase[:unit_count]

        current_purchase = v3[:previous_marketplace_purchase]
        assert_equal 3, current_purchase[:unit_count]

        # plan is unchanged
        plan = current_purchase[:plan]
        assert_equal @item.subscribable.id, plan[:id]

        plan = upcoming_purchase[:plan]
        assert_equal @item.subscribable.id, plan[:id]
      end
    end

    test "when the marketplace_purchase subscription downgrade is cancelled" do
      Timecop.freeze(GitHub::Billing.timezone.local(2013, 3, 1)) do
        pending_plan_change = create(:billing_pending_plan_change, user: @sender)
        pending_subscription_item_change = pending_plan_change.
          pending_subscription_item_changes.
          create(subscribable: @plan, quantity: 2, plan_subscription: create(:billing_plan_subscription, user: @sender))
        payload = build_marketplace_purchase_payload \
          action: :pending_change_cancelled,
          sender_id: @sender.id,
          subscription_item_id: @item.id,
          pending_subscription_item_change_id: pending_subscription_item_change.id

        v3 = payload.to_hash

        assert_equal :pending_change_cancelled, v3[:action]

        assert_equal "2013-03-01T00:00:00+00:00", v3[:effective_date]

        upcoming_purchase = v3[:marketplace_purchase]
        assert_equal 2, upcoming_purchase[:unit_count]

        current_purchase = v3[:previous_marketplace_purchase]
        assert_equal 3, current_purchase[:unit_count]

        # plan is unchanged
        plan = current_purchase[:plan]
        assert_equal @item.subscribable.id, plan[:id]

        plan = upcoming_purchase[:plan]
        assert_equal @item.subscribable.id, plan[:id]
      end
    end

    test "changing the billing cycle" do
      Timecop.freeze(GitHub::Billing.timezone.local(2013, 3, 1)) do
        payload = build_marketplace_purchase_payload \
          action: :changed,
          previous_plan_duration: "year"
        v3 = payload.to_hash

        assert_equal :changed, v3[:action]

        previous_purchase = v3[:previous_marketplace_purchase]
        assert_equal 3, previous_purchase[:unit_count]
        assert_equal "yearly", previous_purchase[:billing_cycle]

        plan = previous_purchase[:plan]
        assert_equal @plan.id, plan[:id]
      end
    end

    test "includes free trial info when item is on a trial" do
      Timecop.freeze(GitHub::Billing.timezone.local(2013, 3, 1)) do
        @item = create :billing_subscription_item,
          :free_trial,
          quantity: 3
        @sender = @item.account

        payload = build_marketplace_purchase_payload
        v3 = payload.to_hash

        assert_equal :purchased, v3[:action]

        purchase = v3[:marketplace_purchase]

        assert_equal true, purchase[:on_free_trial]
        assert_equal "2013-03-15T00:00:00+00:00", purchase[:free_trial_ends_on]

        plan = purchase[:plan]
        assert_equal true, plan[:has_free_trial]
      end
    end

    test "when the free trial ends" do
      Timecop.freeze(GitHub::Billing.timezone.local(2017, 10, 24)) do
        @item = create :billing_subscription_item,
          :free_trial,
          quantity: 2

        @item.update_attribute(:free_trial_ends_on, GitHub::Billing.yesterday)
        payload = build_marketplace_purchase_payload \
          action: :changed,
          previous_subscribable_id: @item.subscribable.id,
          previous_subscribable_type: @item.subscribable.class.name,
          previous_quantity: 2,
          previously_on_free_trial: true,
          previous_free_trial_ends_on: Date.parse("2017-10-31")
        v3 = payload.to_hash

        assert_equal :changed, v3[:action]
        assert_equal "2017-10-24T00:00:00+00:00", v3[:effective_date]

        previous_purchase = v3[:previous_marketplace_purchase]
        assert_equal true, previous_purchase[:on_free_trial]
        assert_equal "2017-10-31T00:00:00+00:00", previous_purchase[:free_trial_ends_on]

        purchase = v3[:marketplace_purchase]
        assert_equal false, purchase[:on_free_trial]
        assert_equal "2017-10-23T00:00:00+00:00", purchase[:free_trial_ends_on]
      end
    end

    test "includes an org's billing email" do
      Timecop.freeze(GitHub::Billing.timezone.local(2013, 3, 1)) do
        @account = create :credit_card_org
        @sender = @account
        plan_sub = create :billing_plan_subscription, user: @account
        @item = create :billing_subscription_item,
          quantity: 3,
          plan_subscription: plan_sub
        payload = build_marketplace_purchase_payload
        v3 = payload.to_hash

        assert_equal :purchased, v3[:action]

        account = v3[:marketplace_purchase][:account]
        assert_equal @account.organization_billing_email, account[:organization_billing_email]
        refute_nil account[:node_id]
        assert_equal @account.global_relay_id, account[:node_id]
      end
    end
  end

  def build_marketplace_purchase_payload(attrs = {})
    default_attrs = {
      action: :purchased,
      subscription_item_id: @item.id,
      sender_id: @sender.id,
    }

    event = Hook::Event::MarketplacePurchaseEvent
      .new(attrs.reverse_merge(default_attrs))
    Hook::Payload::MarketplacePurchasePayload.new(event)
  end
end
