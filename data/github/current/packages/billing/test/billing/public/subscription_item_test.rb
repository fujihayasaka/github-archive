# typed: true
# frozen_string_literal: true

require "test_helper"

module Billing
  module Public
    class PublicSubscriptionItemTest < GitHub::BillingTestCase
      fixtures do
        @copilot_product_uuid = create(:billing_product_uuid, :copilot, billing_cycle: :month)
        @advanced_security_product_uuid = create(:billing_product_uuid, :advanced_security)
        @plan_subscription = create(:billing_plan_subscription, :zuora)
        @user = @plan_subscription.user
        @business = create(:billing_plan_subscription, :business_owned).business
        @owner = @business.owners.first
      end

      setup do
        @advanced_security_monthly_product = ::AdvancedSecurity::Public::Subscription::ADVANCED_SECURITY_MONTHLY_PRODUCT
        @copilot_product_identifier = Billing::Public::Product::ProductIdentifier.new(product_type: "github.copilot", product_key: "v0", billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month).freeze
      end

      context "#product_identifier" do
        test "returns the product identifier for yearly billing cycle" do
          subscription_item = create :billing_subscription_item,
            plan_subscription: @plan_subscription,
            subscribable: create(:billing_product_uuid, :copilot, billing_cycle: :year),
            quantity: 1
          copilot_yearly_product_identifier = Billing::Public::Product::ProductIdentifier.new(
                                                product_type: "github.copilot",
                                                product_key: "v0",
                                                billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Year).freeze


          public_subscription_item = Billing::Public::SubscriptionItem.new(subscription_item)
          assert_equal public_subscription_item.product_identifier, copilot_yearly_product_identifier
        end

        test "returns the product identifier for monthly billing cycle" do
          subscription_item = create :billing_subscription_item,
            plan_subscription: @plan_subscription,
            subscribable: @copilot_product_uuid,
            quantity: 1


          public_subscription_item = Billing::Public::SubscriptionItem.new(subscription_item)
          assert_equal public_subscription_item.product_identifier, @copilot_product_identifier
        end
      end

      context "#pending_change?" do
        context "copilot_subscription_item" do
          test "returns true when there's a pending change for the subscription item's product" do
            subscription_item = create :billing_subscription_item,
              plan_subscription: @plan_subscription,
              subscribable: @copilot_product_uuid,
              quantity: 1

            copilot_yearly = create(:billing_product_uuid, :copilot, billing_cycle: :year)
            create :billing_pending_subscription_item_change,
              subscribable: copilot_yearly,
              pending_plan_change: create(:billing_pending_plan_change, user: @user),
              quantity: 1

            public_subscription_item = Billing::Public::SubscriptionItem.new(subscription_item)
            assert public_subscription_item.pending_change?
          end

          test "returns false when there's no pending changes for the same product" do
            subscription_item = create :billing_subscription_item,
              plan_subscription: @plan_subscription,
              subscribable: @copilot_product_uuid,
              quantity: 1

            create :billing_pending_subscription_item_change,
              pending_plan_change: create(:billing_pending_plan_change, user: @user),
              quantity: 1

            public_subscription_item = Billing::Public::SubscriptionItem.new(subscription_item)
            refute public_subscription_item.pending_change?
          end
        end

        context "advanced_security_subscription_item" do
          test "returns true when there's a pending change for the subscription item's product" do
            subscription_item = create :billing_subscription_item,
              plan_subscription: @plan_subscription,
              subscribable: @advanced_security_product_uuid,
              quantity: 1
            create :billing_pending_subscription_item_change,
              subscribable: @advanced_security_product_uuid,
              pending_plan_change: create(:billing_pending_plan_change, user: @user),
              quantity: 4

            public_subscription_item = Billing::Public::SubscriptionItem.new(subscription_item)
            assert public_subscription_item.pending_change?
          end

          test "returns false when there's no pending changes for the same product" do
            subscription_item = create :billing_subscription_item,
              plan_subscription: @plan_subscription,
              subscribable: @advanced_security_product_uuid,
              quantity: 1

            create :billing_pending_subscription_item_change,
              pending_plan_change: create(:billing_pending_plan_change, user: @user),
              quantity: 1

            public_subscription_item = Billing::Public::SubscriptionItem.new(subscription_item)
            refute public_subscription_item.pending_change?
          end
        end
      end

      context "#pending_change_interval" do
        test "returns the billing cycle of the pending product change" do
          subscription_item = create :billing_subscription_item,
            plan_subscription: @plan_subscription,
            subscribable: @copilot_product_uuid,
            quantity: 1

          copilot_yearly = create(:billing_product_uuid, :copilot, billing_cycle: :year)
          create :billing_pending_subscription_item_change,
            subscribable: copilot_yearly,
            pending_plan_change: create(:billing_pending_plan_change, user: @user),
            quantity: 1

          public_subscription_item = Billing::Public::SubscriptionItem.new(subscription_item)
          assert_equal "year", public_subscription_item.pending_change_interval
        end

        test "returns nil when there's no pending changes for the same product" do
          subscription_item = create :billing_subscription_item,
            plan_subscription: @plan_subscription,
            subscribable: @copilot_product_uuid,
            quantity: 1

          create :billing_pending_subscription_item_change,
            pending_plan_change: create(:billing_pending_plan_change, user: @user),
            quantity: 1

          public_subscription_item = Billing::Public::SubscriptionItem.new(subscription_item)
          assert_nil public_subscription_item.pending_change_interval
        end
      end

      context "#days_until_change" do
        context "copilot_subscription_item" do
          test "returns the number of days until the pending change becomes effective" do
            subscription_item = create :billing_subscription_item,
              plan_subscription: @plan_subscription,
              subscribable: @copilot_product_uuid,
              quantity: 1

            copilot_yearly = create(:billing_product_uuid, :copilot, billing_cycle: :year)
            freeze_time do
              create :billing_pending_subscription_item_change,
                subscribable: copilot_yearly,
                pending_plan_change: create(
                  :billing_pending_plan_change,
                  user: @user,
                  active_on: GitHub::Billing.today + 10.days
                ),
                quantity: 1

              public_subscription_item = Billing::Public::SubscriptionItem.new(subscription_item)
              assert_equal 10, public_subscription_item.days_until_change
            end
          end

          test "returns nil when there's no pending change" do
            subscription_item = create :billing_subscription_item,
              plan_subscription: @plan_subscription,
              subscribable: @copilot_product_uuid,
              quantity: 1

            public_subscription_item = Billing::Public::SubscriptionItem.new(subscription_item)
            assert_nil public_subscription_item.days_until_change
          end
        end

        context "advanced_security_subscription_item" do
          test "returns the number of days until the pending change becomes effective" do
            subscription_item = create :billing_subscription_item,
              plan_subscription: @plan_subscription,
              subscribable: @advanced_security_product_uuid,
              quantity: 1

            freeze_time do
              create :billing_pending_subscription_item_change,
                subscribable: @advanced_security_product_uuid,
                pending_plan_change: create(
                  :billing_pending_plan_change,
                  user: @user,
                  active_on: GitHub::Billing.today + 10.days
                ),
                quantity: 4

              public_subscription_item = Billing::Public::SubscriptionItem.new(subscription_item)
              assert_equal 10, public_subscription_item.days_until_change
            end
          end

          test "returns nil when there's no pending change" do
            subscription_item = create :billing_subscription_item,
              plan_subscription: @plan_subscription,
              subscribable: @advanced_security_product_uuid,
              quantity: 1

            public_subscription_item = Billing::Public::SubscriptionItem.new(subscription_item)
            assert_nil public_subscription_item.days_until_change
          end
        end
      end

      context "#ends_on" do
        context "copilot_subscription_item" do
          test "returns nil when there's no pending cancellation" do
            subscription_item = create :billing_subscription_item,
              plan_subscription: @plan_subscription,
              subscribable: @copilot_product_uuid,
              quantity: 1

            public_subscription_item = Billing::Public::SubscriptionItem.new(subscription_item)
            refute public_subscription_item.ends_on
          end

          test "returns date when there's a pending cancellation" do
            user = create(:credit_card_user)
            arbitrary_billing_date = GitHub::Billing.today.next_week

            subscription_item = create :billing_subscription_item,
              plan_subscription: create(:billing_plan_subscription, user: user),
              subscribable: @copilot_product_uuid,
              quantity: 1
            subscription_item.stubs(:next_billing_date).returns(arbitrary_billing_date)

            create :billing_pending_subscription_item_change,
              subscribable: @copilot_product_uuid,
              free_trial: true,
              pending_plan_change: create(:billing_pending_plan_change, user: user),
              quantity: 0

            public_subscription_item = Billing::Public::SubscriptionItem.new(subscription_item)
            assert_equal arbitrary_billing_date, public_subscription_item.ends_on
          end
        end

        context "advanced_security_subscription_item" do
          test "returns nil when there's no pending cancellation" do
            subscription_item = create :billing_subscription_item,
              plan_subscription: @plan_subscription,
              subscribable: @advanced_security_product_uuid,
              quantity: 1

            public_subscription_item = Billing::Public::SubscriptionItem.new(subscription_item)
            refute public_subscription_item.ends_on
          end

          test "returns date when there's a pending cancellation" do
            user = create(:credit_card_user)
            arbitrary_billing_date = GitHub::Billing.today.next_week

            subscription_item = create :billing_subscription_item,
              plan_subscription: create(:billing_plan_subscription, user: user),
              subscribable: @advanced_security_product_uuid,
              quantity: 1
            subscription_item.stubs(:next_billing_date).returns(arbitrary_billing_date)

            create :billing_pending_subscription_item_change,
              subscribable: @advanced_security_product_uuid,
              free_trial: false,
              pending_plan_change: create(:billing_pending_plan_change, user: user),
              quantity: 0

            public_subscription_item = Billing::Public::SubscriptionItem.new(subscription_item)
            assert_equal arbitrary_billing_date, public_subscription_item.ends_on
          end
        end
      end

      context "#days_left_on_subscription" do
        context "copilot_subscription_item" do
          test "returns 1 day left for a pending subscription item cancellation when the next billing date is one day before" do
            jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")
            march_4th = GitHub::Billing.date_in_timezone Date.parse("2023-03-04")
            next_billing_date = GitHub::Billing.date_in_timezone Date.parse("2023-03-05")
            user = create(:credit_card_user)

            # User signs up
            subscription_item = travel_to jan_1st do
              item = create :billing_subscription_item,
                plan_subscription: create(:billing_plan_subscription, user: user),
                subscribable: @copilot_product_uuid,
                quantity: 1
              item.stubs(:next_billing_date).returns(next_billing_date)
              item
            end

            # User cancels
            travel_to march_4th do
              create :billing_pending_subscription_item_change,
                subscribable: @copilot_product_uuid,
                free_trial: true,
                pending_plan_change: create(:billing_pending_plan_change, user: user),
                quantity: 0
              public_subscription_item = Billing::Public::SubscriptionItem.new(subscription_item)

              assert_equal 1, public_subscription_item.days_left_on_subscription
            end
          end
        end

        context "advanced_security_subscription_item" do
          test "returns 1 day left for a pending subscription item cancellation when the next billing date is one day before" do
            jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")
            march_4th = GitHub::Billing.date_in_timezone Date.parse("2023-03-04")
            next_billing_date = GitHub::Billing.date_in_timezone Date.parse("2023-03-05")
            user = create(:credit_card_user)

            # User signs up
            subscription_item = travel_to jan_1st do
              item = create :billing_subscription_item,
                plan_subscription: create(:billing_plan_subscription, user: user),
                subscribable: @advanced_security_product_uuid,
                quantity: 1
              item.stubs(:next_billing_date).returns(next_billing_date)
              item
            end

            # User cancels
            travel_to march_4th do
              create :billing_pending_subscription_item_change,
                subscribable: @advanced_security_product_uuid,
                free_trial: false,
                pending_plan_change: create(:billing_pending_plan_change, user: user),
                quantity: 0
              public_subscription_item = Billing::Public::SubscriptionItem.new(subscription_item)

              assert_equal 1, public_subscription_item.days_left_on_subscription
            end
          end
        end
      end

      context "#days_left_on_free_trial" do
        test "returns 4 days left for a subscription item with a free trial that has passed" do
          trial_length = 30
          days_before_trial = 4
          result = Billing::Public::SubscriptionItem.create(
            product: @copilot_product_identifier,
            account: @user,
            actor: @user,
            free_trial_length: trial_length.days
          )
          subscription_item = result.value!

          travel (trial_length - days_before_trial).days do
            assert_equal days_before_trial, subscription_item.days_left_on_free_trial
          end
        end

        test "returns 0 days left for a subscription item with a free trial that has passed" do
          trial_length = 30
          result = Billing::Public::SubscriptionItem.create(
            product: @copilot_product_identifier,
            account: @user,
            actor: @user,
            free_trial_length: trial_length.days
          )
          subscription_item = result.value!

          travel (trial_length + 7).days do # time travel 1 week passed the trial end period
            assert_equal 0, subscription_item.days_left_on_free_trial
          end
        end

        test "returns 0 days left for a subscription item without a free_trial_length set" do
          result = Billing::Public::SubscriptionItem.create(product: @copilot_product_identifier, account: @user, actor: @user)
          subscription_item = result.value!

          assert_equal 0, subscription_item.days_left_on_free_trial
        end
      end

      context "#free_trial_length" do
        test "returns the subscription item's free trial length" do
          trial_length = 7
          result = Billing::Public::SubscriptionItem.create(
            product: @copilot_product_identifier,
            account: @user,
            actor: @user,
            free_trial_length: trial_length.days
          )
          subscription_item = result.value!

          assert_equal trial_length, subscription_item.free_trial_length
        end
      end

      context ".in_app_purchase?" do
        test "returns true when purchased via in-app purchase" do
          in_app_purchase = Billing::Public::InAppPurchase.apple(original_transaction_id: "mona-always-buys-in-app")

          result = Billing::Public::SubscriptionItem.create(
            product: @copilot_product_identifier,
            account: @user,
            actor: @user,
            in_app_purchase:
          )
          subscription_item = result.value!

          assert subscription_item.in_app_purchase?
        end

        test "returns false when not purchased via in-app purchase" do
          result = Billing::Public::SubscriptionItem.create(
            product: @copilot_product_identifier,
            account: @user,
            actor: @user
          )
          subscription_item = result.value!

          refute subscription_item.in_app_purchase?
        end
      end

      context ".create" do
        test "creates a subscription item with a trial" do
          assert_difference -> { @user.plan_subscription.active_subscription_items.count }, 1 do
            result = Billing::Public::SubscriptionItem.create(
              product: @copilot_product_identifier,
              account: @user,
              actor: @user,
              free_trial_length: 7.days
            )

            assert_kind_of GitHub::Result, result
            assert result.ok?
            assert_kind_of Billing::Public::SubscriptionItem, result.value!
            assert_equal (GitHub::Billing.today + 7.days), result.value!.free_trial_ends_on
          end
        end

        test "creates a subscription item without a trial" do
          assert_difference -> { @user.plan_subscription.active_subscription_items.count }, 1 do
            result = Billing::Public::SubscriptionItem.create(
              product: @copilot_product_identifier,
              account: @user,
              actor: @user,
            )
            assert_kind_of GitHub::Result, result
            assert result.ok?
            assert_kind_of Billing::Public::SubscriptionItem, result.value!
            refute result.value!.free_trial_ends_on
          end
        end

        test "allows a business to subscribe to a product" do
          business = create(:business, owners: [@user])

          assert_difference -> { business&.plan_subscription&.active_subscription_items&.count.to_i }, 1 do
            result = Billing::Public::SubscriptionItem.create(
              product: @copilot_product_identifier,
              account: business,
              actor: @user,
            )
            assert_kind_of GitHub::Result, result
            assert result.ok?
            assert_kind_of Billing::Public::SubscriptionItem, result.value!
            refute result.value!.free_trial_ends_on
          end
        end

        test "raises TypeError when given a non-subscribable type" do
          assert_raises TypeError do
            Billing::Public::SubscriptionItem.create(
              product: T.unsafe(Object.new),
              account: @user,
              actor: @user,
            )
          end
        end

        test "raises ArgumentError if given a product hash without a billing_cycle" do
          error = assert_raises ArgumentError do
            Billing::Public::SubscriptionItem.create(
              product: Billing::Public::Product::ProductIdentifier.new(product_type: "github.copilot", product_key: "v0"),
              account: @user,
              actor: @user,
            )
          end

          assert_match /Missing billing_cycle key/, error.message
        end

        context "copilot_subscription_item" do
          test "creates a subscription item with a trial" do
            assert_difference -> { @user.plan_subscription.active_subscription_items.count }, 1 do
              result = Billing::Public::SubscriptionItem.create(
                product: @copilot_product_identifier,
                account: @user,
                actor: @user,
                free_trial_length: 7.days
              )
              assert_kind_of GitHub::Result, result
              assert result.ok?
              assert_kind_of Billing::Public::SubscriptionItem, result.value!
              assert_equal (GitHub::Billing.today + 7.days), result.value!.free_trial_ends_on
            end
          end

          test "creates a subscription item without a trial" do
            assert_difference -> { @user.plan_subscription.active_subscription_items.count }, 1 do
              result = Billing::Public::SubscriptionItem.create(
                product: @copilot_product_identifier,
                account: @user,
                actor: @user,
              )
              assert_kind_of GitHub::Result, result
              assert result.ok?
              assert_kind_of Billing::Public::SubscriptionItem, result.value!
              refute result.value!.free_trial_ends_on
            end
          end

          test "returns error when creating a monthly reocurring subscription if user aleady has a monthly one" do
            create(:billing_subscription_item, :paid, plan_subscription: @plan_subscription, subscribable: @copilot_product_uuid)
            result = Billing::Public::SubscriptionItem.create(
              product: @copilot_product_uuid,
              account: @user,
              actor: @user,
            )

            assert_kind_of GitHub::Result, result
            refute result.ok?
            assert_match /already has an active subscription for GitHub Copilot/, result.error.message
          end

          test "returns error when creating a subscription item for a product that has already been subscribed to regardless of cycle" do
            create(:billing_subscription_item, :paid, plan_subscription: @plan_subscription, subscribable: @copilot_product_uuid)
            copilot_yearly_product_uuid = create(:billing_product_uuid, :copilot, billing_cycle: :year)

            result = Billing::Public::SubscriptionItem.create(
              product: copilot_yearly_product_uuid,
              account: @user,
              actor: @user,
            )

            assert_kind_of GitHub::Result, result
            refute result.ok?
            assert_match /already has an active subscription for GitHub Copilot/, result.error.message
          end

          test "returns error when creating a yearly reocurring subscription if user aleady has a yearly one" do
            @copilot_product_uuid = create(:billing_product_uuid, :copilot, billing_cycle: :year)
            create(:billing_subscription_item, :paid, plan_subscription: @plan_subscription, subscribable: @copilot_product_uuid)
            result = Billing::Public::SubscriptionItem.create(
              product: @copilot_product_uuid,
              account: @user,
              actor: @user,
            )

            assert_kind_of GitHub::Result, result
            refute result.ok?
            assert_match /already has an active subscription for GitHub Copilot/, result.error.message
          end
        end

        context "advanced_security_subscription_item" do
          test "creates a subscription item without a trial" do
            assert_difference -> { @user.plan_subscription.active_subscription_items.count }, 1 do
              result = Billing::Public::SubscriptionItem.create(
                product: @advanced_security_monthly_product,
                account: @user,
                actor: @user,
              )
              assert_kind_of GitHub::Result, result
              assert result.ok?
              assert_kind_of Billing::Public::SubscriptionItem, result.value!
              refute result.value!.free_trial_ends_on
            end
          end

          test "returns error when creating a monthly reocurring subscription if user aleady has a monthly one" do
            create(:billing_subscription_item, :paid, plan_subscription: @plan_subscription, subscribable: @advanced_security_product_uuid)
            result = Billing::Public::SubscriptionItem.create(
              product: @advanced_security_monthly_product,
              account: @user,
              actor: @user,
            )

            assert_kind_of GitHub::Result, result
            refute result.ok?
            assert_match /already has an active subscription for GitHub Advanced Security/, result.error.message
          end
        end

        test "does not enqueue a sync job when skip_sync is true" do
          assert_enqueued_jobs(0, only: SynchronizePlanSubscriptionJob) do
            assert_enqueued_jobs(0, only: CollectPaymentForUpgradeJob) do
              result = Billing::Public::SubscriptionItem.create(
                product: @advanced_security_monthly_product,
                account: @user,
                actor: @user,
                skip_sync: true,
              )

              assert_kind_of GitHub::Result, result
              assert result.ok?
            end
          end
        end

        context "perform_authorization is true" do
          test "creates a subscription item when the authorization succeeds" do
            assert_difference -> { @user.plan_subscription.active_subscription_items.count }, 1 do
              Billing::CreateAuthorizationBillingTransactionJob.expects(:perform_now).once.returns(true)

              result = Billing::Public::SubscriptionItem.create(
                product: @copilot_product_identifier,
                account: @user,
                actor: @user,
                free_trial_length: 7.days,
                perform_authorization: true
              )

              assert_kind_of GitHub::Result, result
              assert result.ok?
              assert_kind_of Billing::Public::SubscriptionItem, result.value!
              assert_equal (GitHub::Billing.today + 7.days), result.value!.free_trial_ends_on
            end
          end

          test "creates a subscription item when the authorization with a custom amount succeeds" do
            assert_difference -> { @user.plan_subscription.active_subscription_items.count }, 1 do
              Billing::CreateAuthorizationBillingTransactionJob.expects(:perform_now).once.with(
                entity_id: @user.id,
                amount_in_cents: 1234,
                is_business: false,
                origin: "Billing::CreateProductSubscriptionItem"
              ).returns(true)

              result = Billing::Public::SubscriptionItem.create(
                product: @copilot_product_identifier,
                account: @user,
                actor: @user,
                free_trial_length: 7.days,
                perform_authorization: true,
                authorization_amount_in_cents: 1234
              )

              assert_kind_of GitHub::Result, result
              assert result.ok?
              assert_kind_of Billing::Public::SubscriptionItem, result.value!
              assert_equal (GitHub::Billing.today + 7.days), result.value!.free_trial_ends_on
            end
          end

          test "does not create a subscription item when the authorization fails" do
            assert_difference -> { @user.plan_subscription.active_subscription_items.count }, 0 do
              Billing::CreateAuthorizationBillingTransactionJob.expects(:perform_now).once.returns(false)

              result = Billing::Public::SubscriptionItem.create(
                product: @copilot_product_identifier,
                account: @user,
                actor: @user,
                free_trial_length: 7.days,
                perform_authorization: true
              )

              assert_kind_of GitHub::Result, result
              refute result.ok?
              assert_kind_of Billing::CreateSubscriptionItem::UnprocessableError, result.error
              assert_equal "A valid payment method is required.", result.error.message
            end
          end
        end
      end

      context ".update" do
        test "updates with a product with a different billing cycle" do
          create(:billing_product_uuid, :copilot, billing_cycle: :year)
          product_with_new_billing_cycle = Billing::Public::Product::ProductIdentifier.new(product_type: "github.copilot", product_key: "v0", billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Year)

          plan_subscription = create(:billing_plan_subscription)
          create(:billing_subscription_item, :installed, plan_subscription: plan_subscription, subscribable: @copilot_product_uuid, quantity: 1)

          result = Billing::Public::SubscriptionItem.update(
            product: product_with_new_billing_cycle,
            account: plan_subscription.user,
            actor: plan_subscription.user,
            quantity: 2,
          )

          assert result.ok?
        end

        test "updates with a product with the same product_type but different product_key" do
          copilot_pro_plus_product = create(:billing_product_uuid, :copilot_pro_plus, billing_cycle: :month)
          product_with_same_type_different_key = Billing::Public::Product::ProductIdentifier.new(product_type: copilot_pro_plus_product.product_type, product_key: copilot_pro_plus_product.product_key)

          plan_subscription = create(:billing_plan_subscription)
          user = plan_subscription.user
          create(:billing_subscription_item, :installed, plan_subscription: plan_subscription, subscribable: @copilot_product_uuid, quantity: 1)

          result = Billing::Public::SubscriptionItem.update(
            product: product_with_same_type_different_key,
            account: user,
            actor: user,
            quantity: 1,
          )

          assert result.ok?
          assert_equal user.reload.active_subscription_items.sole.subscribable, copilot_pro_plus_product
        end

        test "does not require a billing cycle and defaults to the existing one" do
          plan_subscription = create(:billing_plan_subscription)
          create(:billing_subscription_item, :installed, plan_subscription: plan_subscription, subscribable: @copilot_product_uuid, quantity: 1)

          result = Billing::Public::SubscriptionItem.update(
            product: @copilot_product_identifier,
            account: plan_subscription.user,
            actor: plan_subscription.user,
            quantity: 2,
          )

          assert result.ok?
        end

        test "allows a business to update their subscription item" do
          business = create(:business, owners: [@user])
          plan_subscription = create(:billing_plan_subscription, customer: business.customer)
          create(:billing_subscription_item, :installed, plan_subscription: plan_subscription, subscribable: @copilot_product_uuid, quantity: 1)

          result = Billing::Public::SubscriptionItem.update(
            product: @copilot_product_identifier,
            account: plan_subscription.user,
            actor: plan_subscription.user,
            quantity: 2,
          )

          assert result.ok?
        end
      end

      context ".all_active" do
        test "returns one subscriptions when only one is active" do
          marketplace_listing_plan = create(:marketplace_listing_plan, :verified_listing)
          create(:billing_subscription_item, :installed, plan_subscription: @plan_subscription, subscribable: marketplace_listing_plan)
          create(:billing_subscription_item, :paid, plan_subscription: @plan_subscription, subscribable: @copilot_product_uuid)

          result = Billing::Public::SubscriptionItem.all_active(product: @copilot_product_identifier, account: @user)
          assert_kind_of GitHub::Result, result
          assert result.ok?
          assert_kind_of Array, result.value!
          assert_equal 1, result.value!.count
        end

        test "returns all active subscription items when product is omitted" do
          marketplace_listing_plan = create(:marketplace_listing_plan, :verified_listing)
          create(:billing_subscription_item, :installed, plan_subscription: @plan_subscription, subscribable: marketplace_listing_plan)
          create(:billing_subscription_item, :paid, plan_subscription: @plan_subscription, subscribable: @copilot_product_uuid)
          create(:billing_subscription_item, :paid, plan_subscription: @plan_subscription, subscribable: @advanced_security_product_uuid)

          result = Billing::Public::SubscriptionItem.all_active(account: @user)
          assert_kind_of GitHub::Result, result
          assert result.ok?
          assert_kind_of Array, result.value!
          assert_equal 3, result.value!.count
        end

        test "returns empty array for accounts without a plan subscription" do
          user = create(:user, plan_subscription: nil)
          result = Billing::Public::SubscriptionItem.all_active(account: user)
          assert_kind_of GitHub::Result, result
          assert result.ok?
          assert_kind_of Array, result.value!
          assert_equal 0, result.value!.count
        end
      end

      context ".trial_exists" do
        test "returns active trial for product" do
          result = Billing::Public::SubscriptionItem.create(
            product: @advanced_security_monthly_product,
            account: @business,
            actor: @owner,
            free_trial_length: 14.days
          )
          assert result.ok?
          result = Billing::Public::SubscriptionItem.trial_exists?(product: @advanced_security_monthly_product, account: @business)
          assert_kind_of GitHub::Result, result
          assert result.ok?
          assert result.value!
        end

        test "returns cancelled trial for product" do
          result = Billing::Public::SubscriptionItem.create(
            product: @advanced_security_monthly_product,
            account: @business,
            actor: @owner,
            free_trial_length: 14.days
          )
          assert result.ok?
          assert_equal 1, @business.pending_plan_changes.count
          @business.pending_plan_changes.first.run
          result = Billing::Public::SubscriptionItem.trial_exists?(product: @advanced_security_monthly_product, account: @business)
          assert_kind_of GitHub::Result, result
          assert result.ok?
          assert result.value!
        end

        test "does not include non-trial results" do
          result = Billing::Public::SubscriptionItem.create(
            product: @advanced_security_monthly_product,
            account: @business,
            actor: @owner,
          )
          assert result.ok?
          result = Billing::Public::SubscriptionItem.trial_exists?(product: @advanced_security_monthly_product, account: @business)
          assert_kind_of GitHub::Result, result
          assert result.ok?
          refute result.value!
        end

        test "can filter by trials within a time duration" do
          june_1st_2022 = GitHub::Billing.date_in_timezone Date.parse("2022-06-01")
          jan_1st_2023 = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")
          july_1st_2023 = GitHub::Billing.date_in_timezone Date.parse("2023-07-01")

          travel_to june_1st_2022 do
            result = Billing::Public::SubscriptionItem.create(
              product: @advanced_security_monthly_product,
              account: @business,
              actor: @owner,
              free_trial_length: 14.days
            )
            assert result.ok?
            assert_equal 1, @business.pending_plan_changes.count
            @business.pending_plan_changes.first.run
            result = Billing::Public::SubscriptionItem.trial_exists?(
              product: @advanced_security_monthly_product,
              account: @business,
              within: 1.year.ago
            )
            assert result.value!
            result = Billing::Public::SubscriptionItem.trial_exists?(
              product: @advanced_security_monthly_product,
              account: @business,
              within: 1.month.ago
            )
            assert result.value!
          end
          travel_to jan_1st_2023 do
            result = Billing::Public::SubscriptionItem.trial_exists?(
              product: @advanced_security_monthly_product,
              account: @business,
              within: 1.year.ago
            )
            assert result.value!
            result = Billing::Public::SubscriptionItem.trial_exists?(
              product: @advanced_security_monthly_product,
              account: @business,
              within: 1.month.ago
            )
            refute result.value!
          end
          travel_to july_1st_2023 do
            result = Billing::Public::SubscriptionItem.trial_exists?(
              product: @advanced_security_monthly_product,
              account: @business,
              within: 1.year.ago
            )
            refute result.value!
            result = Billing::Public::SubscriptionItem.trial_exists?(
              product: @advanced_security_monthly_product,
              account: @business,
              within: 1.month.ago
            )
            refute result.value!
          end
        end
      end

      context ".eligible_for_free_trial?" do
        test "user is eligible for free trial when user has no active subscription items for the product" do
          result = Billing::Public::SubscriptionItem.eligible_for_free_trial?(product: @copilot_product_identifier, account: @user)

          assert result
        end

        test "user is eligible for free trial and no exception is raised when user has a subscription to a non-product-uuid subscribable" do
          marketplace_listing_plan = create(:marketplace_listing_plan, :verified_listing)
          create(:billing_subscription_item, :installed, plan_subscription: @plan_subscription, subscribable: marketplace_listing_plan)

          copilot_product_identifier = Billing::Public::Product::ProductIdentifier.new(product_key: @copilot_product_uuid.product_key, product_type: @copilot_product_uuid.product_type, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
          result = Billing::Public::SubscriptionItem.eligible_for_free_trial?(product: copilot_product_identifier, account: @user)

          assert result
        end

        test "user is *not* eligible for free trial when user currently has an active monthly subscription items for the product" do
          create(:billing_subscription_item, :paid, plan_subscription: @plan_subscription, subscribable: @copilot_product_uuid)
          result = Billing::Public::SubscriptionItem.eligible_for_free_trial?(product: @copilot_product_identifier, account: @user)

          refute result
        end

        test "user is *not* eligible for free trial when user currently has an active yearly subscription items for the product" do
          @copilot_product_uuid = create(:billing_product_uuid, :copilot, billing_cycle: :year)
          create(:billing_subscription_item, :paid, plan_subscription: @plan_subscription, subscribable: @copilot_product_uuid)
          result = Billing::Public::SubscriptionItem.eligible_for_free_trial?(product: @copilot_product_identifier, account: @user)

          refute result
        end

        test "business is eligible for free trial when business has no active subscription items for the product" do
          assert Billing::Public::SubscriptionItem.eligible_for_free_trial?(product: @advanced_security_monthly_product, account: @business)
        end

        test "business is *not* eligible for free trial when business currently has an active subscription items for the product" do
          result = @business.subscribe_to_advanced_security(seats: 1, actor: @owner, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
          assert result.ok?
          refute Billing::Public::SubscriptionItem.eligible_for_free_trial?(product: @advanced_security_monthly_product, account: @business)
        end

        test "business is *not* eligible for free trial when business currently has an active trial for the product" do
          result = @business.subscribe_to_advanced_security_trial(actor: @owner, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
          assert result.ok?
          refute Billing::Public::SubscriptionItem.eligible_for_free_trial?(product: @advanced_security_monthly_product, account: @business)
        end
      end

      context "#extend_trial!" do
        test "Can extend trial" do
          jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")

          disable_feature_flag(:skip_immediate_payment_collection_for_plan_or_seat_changes)

          travel_to jan_1st do
            free_trial_end_date = GitHub::Billing.today + 30.days
            result = @business.subscribe_to_advanced_security_trial(
              actor: @owner,
              billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
            assert result.ok?
            assert result.value!.on_free_trial?
            assert @business.advanced_security_purchased_for_entity?
            assert_equal 1, @business.pending_plan_changes.count
            assert_equal free_trial_end_date + 1.day, @business.pending_plan_changes.first.active_on

            item_id = @business.advanced_security_subscription_item.id
            subscription_item = Billing::SubscriptionItem.find(item_id)
            assert subscription_item.present? && subscription_item.is_a?(Billing::SubscriptionItem)

            result = Billing::Public::SubscriptionItem.extend_trial!(
              product: @advanced_security_monthly_product,
              actor: @owner,
              account: @business,
              days: 3
            )
            assert result.ok?
            assert result.value!.on_free_trial?
            assert result.value!.is_a?(Billing::Public::SubscriptionItem)

            subscription_item.reload

            assert @business.has_active_advanced_security_trial?
            assert_equal 1, @business.pending_plan_changes.count
            assert_equal free_trial_end_date + 3.days + 1.day, @business.pending_plan_changes.first.active_on
            assert_equal free_trial_end_date + 3.days, subscription_item.free_trial_ends_on
            assert_equal 1, @business.pending_plan_changes.first.pending_subscription_item_changes.count
            assert_equal 0, @business.pending_plan_changes.first.pending_subscription_item_changes.first.quantity
          end
        end
      end

      context "#end_free_trial_now!" do
        test "Cannot end trial when trial does not exist" do
          result = Billing::Public::SubscriptionItem.end_free_trial_now!(
            product: @advanced_security_monthly_product,
            actor: @owner,
            account: @business,
            purchase_subscription: false
          )
          refute result.ok?
          assert_equal "Cannot end trial when trial is not active.", result.error.message
        end

        test "Cannot end trial and purchase when the account is disabled" do
          result = @business.subscribe_to_advanced_security_trial(
            actor: @owner,
            billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
          assert result.ok?
          assert result.value!.on_free_trial?

          @business.disable!

          result = Billing::Public::SubscriptionItem.end_free_trial_now!(
            product: @advanced_security_monthly_product,
            actor: @owner,
            account: @business,
            purchase_subscription: true
          )
          refute result.ok?
          assert_equal "Your account is currently locked from purchases. Please update your payment information.", result.error.message
        end

        test "Ends free trial immediately and purchases" do
          disable_feature_flag(:skip_immediate_payment_collection_for_plan_or_seat_changes)

          result = @business.subscribe_to_advanced_security_trial(
            actor: @owner,
            billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
          assert result.ok?
          assert result.value!.on_free_trial?
          assert @business.advanced_security_purchased_for_entity?
          assert_equal 1, @business.pending_plan_changes.count

          assert_enqueued_jobs(1, only: SynchronizePlanSubscriptionJob) do
            assert_enqueued_jobs(0, only: CollectPaymentForUpgradeJob) do
              result = Billing::Public::SubscriptionItem.end_free_trial_now!(
                product: @advanced_security_monthly_product,
                actor: @owner,
                account: @business,
                purchase_subscription: true,
                seats: 5
              )
              assert result.ok?
              refute result.value!.on_free_trial?
              RunPendingPlanChangeJob.perform_now(@business.pending_plan_changes.first)
            end
          end

          assert @business.advanced_security_purchased_for_entity?
          refute @business.has_active_advanced_security_trial?
          assert @business.has_advanced_security_trial_in_the_last_year?
          assert_equal 5, @business.advanced_security_seats_for_entity
          assert_equal 1, @business.pending_plan_changes.count
          assert @business.pending_plan_changes.first.is_complete
        end

        test "Ends free trial immediately and cancels" do
          disable_feature_flag(:skip_immediate_payment_collection_for_plan_or_seat_changes)

          result = @business.subscribe_to_advanced_security_trial(
            actor: @owner,
            billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
          assert result.ok?
          assert result.value!.on_free_trial?
          assert @business.advanced_security_purchased_for_entity?
          assert_equal 1, @business.pending_plan_changes.count

          assert_enqueued_jobs(1, only: SynchronizePlanSubscriptionJob) do
            assert_enqueued_jobs(0, only: CollectPaymentForUpgradeJob) do
              result = Billing::Public::SubscriptionItem.end_free_trial_now!(
                product: @advanced_security_monthly_product,
                actor: @owner,
                account: @business,
                purchase_subscription: false
              )
              assert result.ok?
              refute result.value!.on_free_trial?
            end
          end

          assert_equal 0, @business.advanced_security_seats_for_entity
        end

        test "Ends free trial without enqueuing sync job when skip_sync is true" do
          disable_feature_flag(:skip_immediate_payment_collection_for_plan_or_seat_changes)

          result = @business.subscribe_to_advanced_security_trial(
            actor: @owner,
            billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month
          )
          assert result.ok?
          assert result.value!.on_free_trial?
          assert @business.advanced_security_purchased_for_entity?
          assert_equal 1, @business.pending_plan_changes.count

          assert_enqueued_jobs(0, only: SynchronizePlanSubscriptionJob) do
            assert_enqueued_jobs(0, only: CollectPaymentForUpgradeJob) do
              result = Billing::Public::SubscriptionItem.end_free_trial_now!(
                product: @advanced_security_monthly_product,
                actor: @owner,
                account: @business,
                purchase_subscription: true,
                seats: 5,
                skip_sync: true,
              )
              assert result.ok?
              refute result.value!.on_free_trial?
              RunPendingPlanChangeJob.perform_now(@business.pending_plan_changes.first)
            end
          end

          assert @business.advanced_security_purchased_for_entity?
          refute @business.has_active_advanced_security_trial?
          assert @business.has_advanced_security_trial_in_the_last_year?
          assert_equal 5, @business.advanced_security_seats_for_entity
          assert_equal 1, @business.pending_plan_changes.count
          assert @business.pending_plan_changes.first.is_complete
        end
      end

      context "#all_subscriptions_cancelled?" do
        test "returns true when all subscriptions are cancelled" do
          plan_subscription = create(:billing_plan_subscription)
          create(:billing_subscription_item, :cancelled, plan_subscription: plan_subscription, subscribable: @copilot_product_uuid, account: @user)
          create(:billing_subscription_item, :cancelled, plan_subscription: plan_subscription, subscribable: @copilot_product_uuid, account: @user)

          assert Billing::Public::SubscriptionItem.all_subscriptions_cancelled?(product_type: Billing::ProductUUID::COPILOT_PRODUCT_TYPE, account: @user)
        end

        test "returns false when not all subscriptions are cancelled" do
          plan_subscription = create(:billing_plan_subscription)
          create(:billing_subscription_item, :cancelled, plan_subscription: plan_subscription, subscribable: @copilot_product_uuid, account: @user)
          create(:billing_subscription_item, plan_subscription: plan_subscription, subscribable: @copilot_product_uuid, account: @user, quantity: 1)

          refute Billing::Public::SubscriptionItem.all_subscriptions_cancelled?(product_type: Billing::ProductUUID::COPILOT_PRODUCT_TYPE, account: @user)
        end

        test "returns false when there are no subscriptions" do
          new_user = create(:user)

          refute Billing::Public::SubscriptionItem.all_subscriptions_cancelled?(product_type: Billing::ProductUUID::COPILOT_PRODUCT_TYPE, account: new_user)
        end
      end

      context ".reactivate" do
        context "copilot_subscription_item" do
          test "reactivates a cancelled subscription item with trial" do
            subscription_item = create(:billing_subscription_item, :paid, plan_subscription: @plan_subscription, subscribable: @copilot_product_uuid)
            assert_predicate @user.pending_subscription_item_changes, :empty?
            subscription_item.cancel!(force: true)

            result = Billing::Public::SubscriptionItem.reactivate(product: @copilot_product_uuid, account: @user, actor: @user, free_trial_length: 5.days)

            assert_kind_of GitHub::Result, result

            assert result.ok?
            refute_predicate @user.pending_subscription_item_changes, :empty?
            assert_equal @user.pending_subscription_item_changes.first.quantity, 1
            assert_kind_of Billing::Public::SubscriptionItem, result.value!
            assert_predicate subscription_item.reload, :on_free_trial?
          end

          test "errors for multiple cancelled subscriptions" do
            subscription_item = create(:billing_subscription_item, :paid, plan_subscription: @plan_subscription, subscribable: @copilot_product_uuid)
            assert_predicate @user.pending_subscription_item_changes, :empty?
            subscription_item.cancel!(force: true)

            subscription_item = create(:billing_subscription_item, :paid, plan_subscription: @plan_subscription, subscribable: @copilot_product_uuid)
            assert_predicate @user.pending_subscription_item_changes, :empty?
            subscription_item.cancel!(force: true)

            result = Billing::Public::SubscriptionItem.reactivate(product: @copilot_product_uuid, account: @user, actor: @user, free_trial_length: 5.days)

            assert_kind_of GitHub::Result, result

            refute result.ok?
            assert @user.pending_subscription_item_changes, :empty?
            assert_equal result.error.message, "Can't reactivate multiple subscription items"
          end

          test "errors for missing subscription items" do
            result = Billing::Public::SubscriptionItem.reactivate(product: @copilot_product_uuid, account: @user, actor: @user, free_trial_length: 5.days)

            assert_kind_of GitHub::Result, result

            refute result.ok?
            assert @user.pending_subscription_item_changes, :empty?
            assert_equal result.error.message, "Can't find a subscription to reactivate"
          end
        end
      end

      context ".cancel" do
        context "copilot_subscription_item" do
          test "cancel a subscription item at the end of the billing cycle" do
            create(:billing_subscription_item, :paid, plan_subscription: @plan_subscription, subscribable: @copilot_product_uuid)
            assert_predicate @user.pending_subscription_item_changes, :empty?

            result = Billing::Public::SubscriptionItem.cancel(product: @copilot_product_uuid, account: @user, actor: @user)

            assert_kind_of GitHub::Result, result
            assert result.ok?
            refute_predicate @user.pending_subscription_item_changes, :empty?
            assert_predicate @user.pending_subscription_item_changes.first.quantity, :zero?
            assert_kind_of Billing::Public::SubscriptionItem, result.value!
          end

          test "cancel the subscription item immediately" do
            subscription_item = create(:billing_subscription_item, :paid, plan_subscription: @plan_subscription, subscribable: @copilot_product_uuid)
            assert_includes @plan_subscription.reload.active_subscription_items, subscription_item

            result = Billing::Public::SubscriptionItem.cancel(product: @copilot_product_uuid, account: @user, actor: @user, force: true)

            assert_kind_of GitHub::Result, result
            assert result.ok?
            refute_includes @plan_subscription.active_subscription_items, subscription_item
            assert_kind_of Billing::Public::SubscriptionItem, result.value!
            assert_predicate subscription_item.reload, :cancelled?
          end
        end

        context "advanced_security_subscription_item" do
          test "cancel a subscription item at the end of the billing cycle for an enterprise" do
            plan_subscription = create(:billing_plan_subscription, :business_owned)
            business = plan_subscription.business
            user = plan_subscription.business.owners.first
            business.subscribe_to_advanced_security(seats: 10, actor: user, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
            assert_predicate business.pending_subscription_item_changes, :empty?

            result = Billing::Public::SubscriptionItem.cancel(product: @advanced_security_product_uuid, account: business, actor: user)

            assert_kind_of GitHub::Result, result
            assert result.ok?
            refute_predicate business.pending_subscription_item_changes, :empty?
            assert_predicate business.pending_subscription_item_changes.first.quantity, :zero?
            assert_kind_of Billing::Public::SubscriptionItem, result.value!
          end

          test "cancel the subscription item immediately for an enterprise" do
            plan_subscription = create(:billing_plan_subscription, :business_owned)
            business = plan_subscription.business
            user = plan_subscription.business.owners.first
            subscription_item = create(:billing_subscription_item, :paid, plan_subscription: plan_subscription, subscribable: @advanced_security_product_uuid)
            assert_includes plan_subscription.reload.active_subscription_items, subscription_item

            result = Billing::Public::SubscriptionItem.cancel(product: @advanced_security_product_uuid, account: business, actor: user, force: true)

            assert_kind_of GitHub::Result, result
            assert result.ok?
            refute_includes plan_subscription.active_subscription_items, subscription_item
            assert_kind_of Billing::Public::SubscriptionItem, result.value!
            assert_predicate subscription_item.reload, :cancelled?
          end
        end
      end

      context ".cancel_and_refund" do
        context "copilot_subscription_item" do
          test "enqueues a job to cancel and refund the subscription item with product_uuid passed" do
            organization = create(:organization)
            subscription_item = create(:billing_subscription_item, :paid, plan_subscription: @plan_subscription, subscribable: @copilot_product_uuid)
            assert_includes @plan_subscription.reload.active_subscription_items, subscription_item

            assert_enqueued_with(job: Billing::CancelAndRefundSubscriptionItemJob, args: [subscription_item, organization_id: organization.id, full_refund: false, allow_cancelling_iap: false]) do
              result = Billing::Public::SubscriptionItem.cancel_and_refund(product: @copilot_product_uuid, account: @user, organization: organization)

              assert_kind_of GitHub::Result, result
              assert result.ok?
              assert_kind_of Billing::Public::SubscriptionItem, result.value!
            end
          end

          test "enqueues a job to cancel and refund the subscription item with ProductIdentifier passed" do
            organization = create(:organization)
            subscription_item = create(:billing_subscription_item, :paid, plan_subscription: @plan_subscription, subscribable: @copilot_product_uuid)
            assert_includes @plan_subscription.reload.active_subscription_items, subscription_item

            assert_enqueued_with(job: Billing::CancelAndRefundSubscriptionItemJob, args: [subscription_item, organization_id: organization.id, full_refund: false, allow_cancelling_iap: false]) do
              result = Billing::Public::SubscriptionItem.cancel_and_refund(
                product: @copilot_product_identifier,
                account: @user,
                organization: organization,
              )

              assert_kind_of GitHub::Result, result
              assert result.ok?
              assert_kind_of Billing::Public::SubscriptionItem, result.value!
            end
          end

          test "enqueues a job to cancel and refund in-app purchased subscription item with ProductIdentifier passed" do
            organization = create(:organization)
            subscription_item = create(:billing_subscription_item, :paid, :iap, plan_subscription: @plan_subscription, subscribable: @copilot_product_uuid)
            assert_includes @plan_subscription.reload.active_subscription_items, subscription_item

            assert_enqueued_with(job: Billing::CancelAndRefundSubscriptionItemJob, args: [subscription_item, organization_id: organization.id, full_refund: false, allow_cancelling_iap: true]) do
              result = Billing::Public::SubscriptionItem.cancel_and_refund(
                product: @copilot_product_identifier,
                account: @user,
                organization: organization,
                allow_cancelling_iap: true
              )

              assert_kind_of GitHub::Result, result
              assert result.ok?
              assert_kind_of Billing::Public::SubscriptionItem, result.value!
            end
          end
        end
      end

      context "#quantity" do
        test "returns the quantity of the subscription item" do
          subscription_item = create(:billing_subscription_item, :paid, plan_subscription: @plan_subscription, subscribable: @advanced_security_product_uuid, quantity: 3)
          assert_equal 3, Billing::Public::SubscriptionItem.new(subscription_item).quantity
        end
      end
    end
  end
end
