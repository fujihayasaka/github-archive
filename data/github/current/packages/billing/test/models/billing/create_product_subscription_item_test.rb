# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::CreateProductSubscriptionItemTest < GitHub::TestCase
  include AuditLog::IntegrationTestHelpers
  include GitHub::ZuoraTestHelper

  fixtures do
    @product_uuid = create(:billing_product_uuid, :copilot)
    @billing_plan_subscription = create(:billing_plan_subscription, :business_owned)
    @advanced_security_product_uuid = create(:billing_product_uuid, :advanced_security)
    @user = create(:credit_card_user)
  end

  setup do
    skip unless GitHub.billing_enabled?
    @business = @billing_plan_subscription.business
    @owner = @business.owners.first
    GitHub.flipper[:skip_immediate_payment_collection_for_plan_or_seat_changes].disable
  end

  test "creates a subscription item for a billing product" do
    assert_difference "Billing::SubscriptionItem.count", 1 do
      result = Billing::CreateProductSubscriptionItem.call(
        product_uuid: @product_uuid,
        quantity: 1,
        account: @user,
        viewer: @user,
      )
      assert_instance_of Hash, result
      refute_nil result[:subscription_item]
      assert_equal 1, result[:subscription_item].quantity
    end
  end

  context "when purchased via app store" do
    test "creates an associated AppleSubscription record" do
      original_transaction_id = "mona-buy-through-iap"
      in_app_purchase = Billing::Public::InAppPurchase.apple(original_transaction_id: original_transaction_id)

      result = Billing::CreateProductSubscriptionItem.call(
        product_uuid: @product_uuid,
        quantity: 1,
        account: @user,
        viewer: @user,
        in_app_purchase:
      )

      assert_instance_of Hash, result
      refute_nil result[:subscription_item]

      actual_apple_subscription = result[:subscription_item].apple_subscription

      refute_nil actual_apple_subscription
      assert_equal original_transaction_id, actual_apple_subscription.original_transaction_id
    end

    test "creates an associated GoogleSubscription record" do
      purchase_token = "mona-buy-through-iap"
      in_app_purchase = Billing::Public::InAppPurchase.google(purchase_token: purchase_token)

      result = Billing::CreateProductSubscriptionItem.call(
        product_uuid: @product_uuid,
        quantity: 1,
        account: @user,
        viewer: @user,
        in_app_purchase:
      )

      assert_instance_of Hash, result
      refute_nil result[:subscription_item]

      actual_google_subscription = result[:subscription_item].google_subscription

      refute_nil actual_google_subscription
      assert_equal purchase_token, actual_google_subscription.purchase_token
    end

    test "creation does not require a payment method" do
      @user.stubs(:has_valid_payment_method?).returns(false)

      original_transaction_id = "mona-buy-through-iap"
      in_app_purchase = Billing::Public::InAppPurchase.apple(original_transaction_id: original_transaction_id)

      result = Billing::CreateProductSubscriptionItem.call(
        product_uuid: @product_uuid,
        quantity: 1,
        account: @user,
        viewer: @user,
        in_app_purchase:
      )

      refute_nil result[:subscription_item]
    end

    test "does not allow business purchases" do
      original_transaction_id = "mona-buy-through-iap"
      in_app_purchase = Billing::Public::InAppPurchase.apple(original_transaction_id: original_transaction_id)

      assert_raises_with_message(Billing::CreateSubscriptionItem::UnprocessableError, "In-app purchases are only available for user accounts.") do
        Billing::CreateProductSubscriptionItem.call(
          product_uuid: @product_uuid,
          quantity: 1,
          account: @business,
          viewer: @owner,
          in_app_purchase:
        )
      end
    end

    test "prevents original_transaction_id re-use across SubscriptionItem records" do
      original_transaction_id = "mona-buy-through-iap"
      in_app_purchase = Billing::Public::InAppPurchase.apple(original_transaction_id: original_transaction_id)

      result = Billing::CreateProductSubscriptionItem.call(
        product_uuid: @product_uuid,
        quantity: 1,
        account: @user,
        viewer: @user,
        in_app_purchase:
      )

      # Verify staged data
      refute_nil result[:subscription_item]

      assert_raises_with_message(Billing::CreateSubscriptionItem::UnprocessableError, "Apple subscription already exists for Original Transaction ID.") do
        Billing::CreateProductSubscriptionItem.call(
          product_uuid: @product_uuid,
          quantity: 1,
          account: @user,
          viewer: @user,
          in_app_purchase:
        )
      end
    end

    test "prevents original_transaction_id re-use across Pro and SubscriptionItem records" do
      plan_subscription = create(:billing_plan_subscription, :apple_iap)
      original_transaction_id = plan_subscription.apple_transaction_id

      assert_raises_with_message(Billing::CreateSubscriptionItem::UnprocessableError, "Apple subscription for Pro already exists for Original Transaction ID.") do
        in_app_purchase = Billing::Public::InAppPurchase.apple(original_transaction_id: original_transaction_id)

        Billing::CreateProductSubscriptionItem.call(
          product_uuid: @product_uuid,
          quantity: 1,
          account: @user,
          viewer: @user,
          in_app_purchase:
        )
      end
    end

    test "prevents yearly subscription items" do
      original_transaction_id = "mona-buy-through-iap"
      in_app_purchase = Billing::Public::InAppPurchase.apple(original_transaction_id: original_transaction_id)
      yearly_copilot_product_uuid = create(:billing_product_uuid, :copilot, :yearly)

      assert_raises_with_message(Billing::CreateSubscriptionItem::UnprocessableError, "In-app purchases are only available for monthly billing cycles.") do
        Billing::CreateProductSubscriptionItem.call(
          product_uuid: yearly_copilot_product_uuid,
          quantity: 1,
          account: @user,
          viewer: @user,
          in_app_purchase:
        )
      end
    end

    test "prevents free trial lengths greater than 0" do
      original_transaction_id = "mona-buy-through-iap"
      in_app_purchase = Billing::Public::InAppPurchase.apple(original_transaction_id: original_transaction_id)
      expected_error_msg = "In-app purchases do not support free trials within our billing system and are externally controlled via the IAP store(s)."

      assert_raises_with_message(Billing::CreateSubscriptionItem::UnprocessableError, expected_error_msg) do
        Billing::CreateProductSubscriptionItem.call(
          product_uuid: @product_uuid,
          quantity: 1,
          account: @user,
          viewer: @user,
          in_app_purchase:,
          free_trial_length: 1.day
        )
      end
    end
  end

  test "instruments when a subscription item is created for a billing product" do
    events = subscribe("billing.subscription_item_created")

    result = Billing::CreateProductSubscriptionItem.call(
      product_uuid: @product_uuid,
      quantity: 1,
      account: @user,
      viewer: @user,
    )

    expected_payload = {
      business: nil,
      business_id: nil,
      subscription_item_id: result[:subscription_item].id,
      sender_id: @user.id,
      product_type: "github.copilot",
      billing_cycle: "month",
      quantity: 1,
    }

    assert_equal 1, events.size
    event = events.first
    assert_subset_hash expected_payload, event.payload
    assert_equal 1, result[:subscription_item].quantity
  end

  test "instruments an audit log event for a billing product" do
    expected_payload = {
      action: "billing.subscription_item_created",
      sender_id: @user.id,
      product_type: @product_uuid.product_type,
      billing_cycle: @product_uuid.billing_cycle,
    }
    events = assert_performed_audit_entries(count: 1, only: "billing.subscription_item_created") do
      result = Billing::CreateProductSubscriptionItem.call(
        product_uuid: @product_uuid,
        quantity: 1,
        account: @user,
        viewer: @user,
      )
      expected_payload[:subscription_item_id] = result[:subscription_item].id
    end

    assert_equal last_performed_audit_entries, events
    assert_subset_hash expected_payload, events.first
  end

  test "includes apple in-app purchasing info in audit log event for a billing product" do
    in_app_purchase = Billing::Public::InAppPurchase.apple(original_transaction_id: "mona-buy-through-iap")

    expected_payload = {
      in_app_purchase_vendor: "apple",
      in_app_purchase_identifier: in_app_purchase.identifier,
    }

    events = assert_performed_audit_entries(count: 1, only: "billing.subscription_item_created") do
      result = Billing::CreateProductSubscriptionItem.call(
        product_uuid: @product_uuid,
        quantity: 1,
        account: @user,
        viewer: @user,
        in_app_purchase:,
      )

      expected_payload[:subscription_item_id] = result[:subscription_item].id
    end

    assert_equal last_performed_audit_entries, events
    assert_subset_hash expected_payload, events.first
  end

  test "includes google in-app purchasing info in audit log event for a billing product" do
    in_app_purchase = Billing::Public::InAppPurchase.google(purchase_token: "mona-work-at-alphabet?---nahhh")

    expected_payload = {
      in_app_purchase_vendor: "google",
      in_app_purchase_identifier: in_app_purchase.identifier,
    }

    events = assert_performed_audit_entries(count: 1, only: "billing.subscription_item_created") do
      result = Billing::CreateProductSubscriptionItem.call(
        product_uuid: @product_uuid,
        quantity: 1,
        account: @user,
        viewer: @user,
        in_app_purchase:,
      )

      expected_payload[:subscription_item_id] = result[:subscription_item].id
    end

    assert_equal last_performed_audit_entries, events
    assert_subset_hash expected_payload, events.first
  end

  test "creates a subscription item with a custom free trial period" do
    trial_length = 20.days

    result = Billing::CreateProductSubscriptionItem.call(
      product_uuid: @product_uuid,
      quantity: 1,
      account: @user,
      viewer: @user,
      free_trial_length: trial_length,
    )

    assert_equal 1, result[:subscription_item].quantity
    assert_equal (GitHub::Billing.today + trial_length), result[:subscription_item].free_trial_ends_on
  end

  test "collects payment immediately for users on a free plan purchasing a product uuid subscription item" do
    subscription = create :billing_plan_subscription, :zuora
    create_zuora_subscription(
      zuora_subscription_number: subscription.zuora_subscription_number,
    )
    user = create :credit_card_user, plan: "free", plan_subscription: subscription

    assert_enqueued_jobs(0, only: SynchronizePlanSubscriptionJob) do
      assert_enqueued_jobs(1, only: CollectPaymentForUpgradeJob) do
        Billing::CreateProductSubscriptionItem.call(
          product_uuid: @product_uuid,
          quantity: 1,
          account: user,
          viewer: user,
        )
      end
    end
  end

  test "collects payment immediately for users on a free plan without a plan subscription purchasing a product uuid subscription item" do
    user = create :credit_card_user, plan: "free"

    assert_enqueued_jobs(0, only: SynchronizePlanSubscriptionJob) do
      assert_enqueued_jobs(1, only: CollectPaymentForUpgradeJob) do
        Billing::CreateProductSubscriptionItem.call(
          product_uuid: @product_uuid,
          quantity: 1,
          account: user,
          viewer: user,
        )
      end
    end
  end

  test "collects payment immediately for users on a paid plan when purchasing a product uuid subscription item" do
    subscription = create :billing_plan_subscription, :zuora
    create_zuora_subscription(
      zuora_subscription_number: subscription.zuora_subscription_number,
    )
    user = create :credit_card_user, plan: "pro", plan_subscription: subscription

    assert_enqueued_jobs(0, only: SynchronizePlanSubscriptionJob) do
      assert_enqueued_jobs(1, only: CollectPaymentForUpgradeJob) do
        Billing::CreateProductSubscriptionItem.call(
          product_uuid: @product_uuid,
          quantity: 1,
          account: user,
          viewer: user,
        )
      end
    end
  end


  test "does not collect payment immediately when purchasing a ProductUUID subscription when there is a free trial" do
    subscription = create :billing_plan_subscription, :zuora
    create_zuora_subscription(
      zuora_subscription_number: subscription.zuora_subscription_number,
    )
    user = create :credit_card_user, plan: "pro", plan_subscription: subscription

    assert_enqueued_jobs(1, only: SynchronizePlanSubscriptionJob) do
      assert_enqueued_jobs(0, only: CollectPaymentForUpgradeJob) do
        result = Billing::CreateProductSubscriptionItem.call(
          product_uuid: @product_uuid,
          quantity: 1,
          account: user,
          viewer: user,
          free_trial_length: 1.week
        )
        assert result[:subscription_item].on_free_trial?
      end
    end
  end

  test "does not verify billing information if trial does not bill on expiry" do

    @business.stubs(:has_valid_payment_method?).returns(false)
    @user.stubs(:has_valid_payment_method?).returns(false)

    trial_length = 30.days

    result = Billing::CreateProductSubscriptionItem.call(
      product_uuid: @advanced_security_product_uuid,
      quantity: 1,
      account: @business,
      viewer: @owner,
      free_trial_length: trial_length,
    )

    assert_equal 1, result[:subscription_item].quantity

    assert_raises_with_message(Billing::CreateSubscriptionItem::UnprocessableError, "Please add a payment method before checking out.") do
      result = Billing::CreateProductSubscriptionItem.call(
        product_uuid: @product_uuid,
        quantity: 1,
        account: @user,
        viewer: @user,
        free_trial_length: 1.week
      )
    end
  end

  test "collects payment immediately for businesses on a business_plus plan when purchasing a product uuid subscription item" do
    business = create(:billing_plan_subscription, :business_owned).business
    owner = business.owners.first
    ghas_product_uuid = create(:billing_product_uuid, :advanced_security)

    assert_enqueued_jobs(0, only: SynchronizePlanSubscriptionJob) do
      assert_enqueued_jobs(1, only: CollectPaymentForUpgradeJob) do
        result = Billing::CreateProductSubscriptionItem.call(
          product_uuid: ghas_product_uuid,
          quantity: 10,
          account: business,
          viewer: owner,
        )
        assert_equal 10, result[:subscription_item].quantity
      end
    end
  end

  test "does not enqueue synchronization job when `skip_sync` is true" do
    assert_difference "Billing::SubscriptionItem.count", 1 do
      assert_enqueued_jobs(0, only: SynchronizePlanSubscriptionJob) do
        assert_enqueued_jobs(0, only: CollectPaymentForUpgradeJob) do
          result = Billing::CreateProductSubscriptionItem.call(
            product_uuid: @product_uuid,
            quantity: 1,
            account: @user,
            viewer: @user,
            skip_sync: true,
          )
          assert_instance_of Hash, result
          refute_nil result[:subscription_item]
          assert_equal 1, result[:subscription_item].quantity
        end
      end
    end
  end
end
