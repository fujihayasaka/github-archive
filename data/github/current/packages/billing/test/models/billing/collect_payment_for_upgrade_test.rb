# typed: true
# frozen_string_literal: true

require "test_helper"

module Billing
  class CollectPaymentForUpgradeTest < GitHub::BillingTestCase
    include AuditLog::IntegrationTestHelpers
    include DogstatsTestHelpers
    include GitHub::ZuoraTestHelper

    fixtures do
      @product_uuid = create(:billing_product_uuid, :advanced_security)
    end

    setup do
      synchronize_github_products_to_zuora
    end

    context "#synchronize" do
      test "returns false when the synchronization fails" do
        user = create(:user, :zuora, plan: "free")
        plan_subscription = create(:billing_plan_subscription, :zuora, user: user)

        plan_subscription.expects(:synchronize_with_lock).with(collect: true).returns(GitHub::Billing::Result.failure("error"))

        result = ::Billing::CollectPaymentForUpgrade.synchronize(plan_subscription, GitHub::Plan.pro, 0, user)

        refute result.success?
        assert_dogstats_timing(1, "billing.collect_payment_for_upgrade.synchronize", tags: ["success:false", "collect:true", "error:false"])
      end

      test "Logs metrics and data when an exception is raised" do
        user = create(:user, :zuora, plan: "free")
        plan_subscription = create(:billing_plan_subscription, :zuora, user: user)

        plan_subscription.expects(:synchronize_with_lock).with(collect: true).raises(Zuorest::HttpError.new(504, "Gateway Timeout"))

        assert_raises(Zuorest::HttpError) do
          ::Billing::CollectPaymentForUpgrade.synchronize(plan_subscription, GitHub::Plan.pro, 0, user)
        end

        assert_dogstats_timing(1, "billing.collect_payment_for_upgrade.synchronize", tags: ["success:false", "collect:true", "error:true"])
      end

      context "for a user" do
        test "synchronizes without collect when there are no plan changes" do
          user = create(:user, :zuora, plan: "pro")
          plan_subscription = create(:billing_plan_subscription, :zuora, user: user)

          plan_subscription.expects(:synchronize_with_lock).with(collect: nil).returns(GitHub::Billing::Result.success)

          result = ::Billing::CollectPaymentForUpgrade.synchronize(plan_subscription, GitHub::Plan.pro, 0, user)

          assert result.success?
          assert_dogstats_timing(1, "billing.collect_payment_for_upgrade.synchronize", tags: ["success:true", "collect:false", "error:false"])
        end

        test "synchronizes with collect when there are plan changes" do
          user = create(:user, :zuora, plan: "free")
          plan_subscription = create(:billing_plan_subscription, :zuora, user: user)

          plan_subscription.expects(:synchronize_with_lock).with(collect: true).returns(GitHub::Billing::Result.success)

          result = ::Billing::CollectPaymentForUpgrade.synchronize(plan_subscription, GitHub::Plan.pro, 0, user)

          assert result.success?
          assert_dogstats_timing(1, "billing.collect_payment_for_upgrade.synchronize", tags: ["success:true", "collect:true", "error:false"])
        end

        test "synchronizes without collect when there are no subscription item quantity, seat or plan changes" do
          user = create(:user, :zuora, plan: "pro")
          plan_subscription = create(:billing_plan_subscription, :zuora, user: user)
          subscription_item = create :billing_subscription_item, plan_subscription: plan_subscription, subscribable: @product_uuid, quantity: 1

          plan_subscription.expects(:synchronize_with_lock).with(collect: nil).returns(GitHub::Billing::Result.success)
          result = ::Billing::CollectPaymentForUpgrade.synchronize(plan_subscription, user.plan, 0, user, subscription_item, 1)

          assert result.success?
          assert_dogstats_timing(1, "billing.collect_payment_for_upgrade.synchronize", tags: ["success:true", "collect:false", "error:false"])
        end

        test "synchronizes with collect when there are subscription item quantity changes" do
          user = create(:user, :zuora, plan: "pro")
          plan_subscription = create(:billing_plan_subscription, :zuora, user: user)
          subscription_item = create :billing_subscription_item, plan_subscription: plan_subscription, subscribable: @product_uuid, quantity: 1

          plan_subscription.expects(:synchronize_with_lock).with(collect: true).returns(GitHub::Billing::Result.success)

          result = ::Billing::CollectPaymentForUpgrade.synchronize(plan_subscription, user.plan, 0, user, subscription_item, 2)

          assert result.success?
          assert_dogstats_timing(1, "billing.collect_payment_for_upgrade.synchronize", tags: ["success:true", "collect:true", "error:false"])
        end
      end

      context "for an organization" do
        test "synchronizes without collect when there are no plan or seat changes" do
          org = create(:organization, :zuora, plan: "free", seats: 0)
          plan_subscription = create(:billing_plan_subscription, :zuora, user: org)

          plan_subscription.expects(:synchronize_with_lock).with(collect: nil).returns(GitHub::Billing::Result.success)

          result = ::Billing::CollectPaymentForUpgrade.synchronize(plan_subscription, GitHub::Plan.free, 0,
            org.admin)

          assert result.success?
          assert_dogstats_timing(1, "billing.collect_payment_for_upgrade.synchronize", tags: ["success:true", "collect:false", "error:false"])
        end

        test "synchronizes with collect when there are plan changes" do
          org = create(:organization, :zuora, plan: "business", seats: 5)
          plan_subscription = create(:billing_plan_subscription, :zuora, user: org)

          plan_subscription.expects(:synchronize_with_lock).with(collect: true).returns(GitHub::Billing::Result.success)

          result = ::Billing::CollectPaymentForUpgrade.synchronize(plan_subscription, GitHub::Plan.business_plus, 5,
            org.admin)

          assert result.success?
          assert_dogstats_timing(1, "billing.collect_payment_for_upgrade.synchronize", tags: ["success:true", "collect:true", "error:false"])
        end

        test "synchronizes with collect when there are seat changes" do
          org = create(:organization, :zuora, plan: "business", seats: 5)
          plan_subscription = create(:billing_plan_subscription, :zuora, user: org)

          plan_subscription.expects(:synchronize_with_lock).with(collect: true).returns(GitHub::Billing::Result.success)

          result = ::Billing::CollectPaymentForUpgrade.synchronize(plan_subscription, GitHub::Plan.business, 1,
            org.admin)

          assert result.success?
          assert_dogstats_timing(1, "billing.collect_payment_for_upgrade.synchronize", tags: ["success:true", "collect:true", "error:false"])
        end

        test "synchronizes with collect when there are plan and seat changes" do
          org = create(:organization, :zuora, plan: "business", seats: 5)
          plan_subscription = create(:billing_plan_subscription, :zuora, user: org)

          plan_subscription.expects(:synchronize_with_lock).with(collect: true).returns(GitHub::Billing::Result.success)

          result = ::Billing::CollectPaymentForUpgrade.synchronize(plan_subscription, GitHub::Plan.business_plus, 1,
            org.admin)

          assert result.success?
          assert_dogstats_timing(1, "billing.collect_payment_for_upgrade.synchronize", tags: ["success:true", "collect:true", "error:false"])
        end

        test "synchronizes without collect when there are no subscription item quantity, seat or plan changes" do
          org = create(:organization, :zuora, plan: "business", seats: 5)
          plan_subscription = create(:billing_plan_subscription, :zuora, user: org)
          subscription_item = create :billing_subscription_item, plan_subscription: plan_subscription, subscribable: @product_uuid, quantity: 1

          plan_subscription.expects(:synchronize_with_lock).with(collect: nil).returns(GitHub::Billing::Result.success)
          result = ::Billing::CollectPaymentForUpgrade.synchronize(plan_subscription, org.plan, org.seats, org.owner, subscription_item, 1)

          assert result.success?
          assert_dogstats_timing(1, "billing.collect_payment_for_upgrade.synchronize", tags: ["success:true", "collect:false", "error:false"])
        end

        test "synchronizes with collect when there are subscription item quantity changes" do
          org = create(:organization, :zuora, plan: "business", seats: 5)
          plan_subscription = create(:billing_plan_subscription, :zuora, user: org)
          subscription_item = create :billing_subscription_item, plan_subscription: plan_subscription, subscribable: @product_uuid, quantity: 1

          plan_subscription.expects(:synchronize_with_lock).with(collect: true).returns(GitHub::Billing::Result.success)

          result = ::Billing::CollectPaymentForUpgrade.synchronize(plan_subscription, org.plan, org.seats, org.owner, subscription_item, 2)

          assert result.success?
          assert_dogstats_timing(1, "billing.collect_payment_for_upgrade.synchronize", tags: ["success:true", "collect:true", "error:false"])
        end
      end

      context "for a business" do
        test "synchronizes without collect when there are no seat changes" do
          org = create(:organization)
          business = create(:business, organizations: [org], seats: 50)
          plan_subscription = create(:billing_plan_subscription, :business_owned, customer: business.customer)

          plan_subscription.expects(:synchronize_with_lock).with(collect: nil).returns(GitHub::Billing::Result.success)

          result = ::Billing::CollectPaymentForUpgrade.synchronize(plan_subscription, GitHub::Plan.business_plus, 50,
            org.admin)

          assert result.success?
          assert_dogstats_timing(1, "billing.collect_payment_for_upgrade.synchronize", tags: ["success:true", "collect:false", "error:false"])
        end

        test "synchronizes with collect when there are seat changes" do
          org = create(:organization)
          business = create(:business, organizations: [org], seats: 50)
          plan_subscription = create(:billing_plan_subscription, :business_owned, customer: business.customer)

          plan_subscription.expects(:synchronize_with_lock).with(collect: true).returns(GitHub::Billing::Result.success)

          result = ::Billing::CollectPaymentForUpgrade.synchronize(plan_subscription, GitHub::Plan.business_plus, 10,
            org.admin)

          assert result.success?
          assert_dogstats_timing(1, "billing.collect_payment_for_upgrade.synchronize", tags: ["success:true", "collect:true", "error:false"])
        end

        test "synchronizes without collect when there are no subscription item quantity, seat or plan changes" do
          business = create(:billing_plan_subscription, :business_owned).business
          owner = business.owners.first
          plan_subscription = business.plan_subscription
          subscription_item = create :billing_subscription_item, plan_subscription: plan_subscription, subscribable: @product_uuid, quantity: 1

          plan_subscription.expects(:synchronize_with_lock).with(collect: nil).returns(GitHub::Billing::Result.success)

          result = ::Billing::CollectPaymentForUpgrade.synchronize(plan_subscription, business.plan, business.seats, owner, subscription_item, 1)

          assert result.success?
          assert_dogstats_timing(1, "billing.collect_payment_for_upgrade.synchronize", tags: ["success:true", "collect:false", "error:false"])
        end

        test "synchronizes with collect when there are subscription item quantity changes" do
          business = create(:billing_plan_subscription, :business_owned).business
          owner = business.owners.first
          plan_subscription = business.plan_subscription
          subscription_item = create :billing_subscription_item, plan_subscription: plan_subscription, subscribable: @product_uuid, quantity: 1

          plan_subscription.expects(:synchronize_with_lock).with(collect: true).returns(GitHub::Billing::Result.success)

          result = ::Billing::CollectPaymentForUpgrade.synchronize(plan_subscription, business.plan, business.seats, owner, subscription_item, 2)

          assert result.success?
          assert_dogstats_timing(1, "billing.collect_payment_for_upgrade.synchronize", tags: ["success:true", "collect:true", "error:false"])
        end
      end
    end

    context "#rollback" do
      test "does nothing if the current plan is non-paid" do
        user = create(:user, :zuora, plan: "free")
        plan_subscription = create(:billing_plan_subscription, :zuora, user: user)

        assert_performed_audit_entries(count: 0, only: "account.plan_change") do
          ::Billing::CollectPaymentForUpgrade.rollback(plan_subscription, GitHub::Plan.free, 0, user)
        end

        assert_equal "free", user.reload.plan.name
        assert_dogstats_increment(0, "billing.collect_payment_for_upgrade.rollback")
      end

      test "does nothing if the plan or seats have not changed" do
        org = create(:organization, :zuora, plan: "business", seats: 10)
        plan_subscription = create(:billing_plan_subscription, :zuora, user: org)

        assert_performed_audit_entries(count: 0, only: "account.plan_change") do
          ::Billing::CollectPaymentForUpgrade.rollback(plan_subscription, GitHub::Plan.business, 10, org.admin)
        end

        assert_equal "business", org.reload.plan.name
        assert_dogstats_increment(0, "billing.collect_payment_for_upgrade.rollback")
      end

      context "for a user" do
        test "rolls back the user plan from pro to free with a custom reason" do
          user = create(:user, :zuora, plan: "pro")
          plan_subscription = create(:billing_plan_subscription, :zuora, user: user)

          events = assert_performed_audit_entries(count: 1, only: "account.plan_change") do
            ::Billing::CollectPaymentForUpgrade.rollback(plan_subscription, GitHub::Plan.free, 0, user,
              reason: "test")
          end

          assert_equal "free", user.reload.plan.name
          assert_subset_hash({ old_plan: "pro", plan: "free", reason: "test" }, events.first)
          assert_dogstats_increment(1, "billing.collect_payment_for_upgrade.rollback",
            tags: ["from_plan:pro", "from_seats:0", "to_plan:free", "to_seats:0"])
        end

        test "rolls back the subscription item quantity" do
          quantity_to_rollback_to = 5
          failed_payment_quantity = 10
          user = create(:user, :zuora, plan: "pro")
          plan_subscription = create(:billing_plan_subscription, :zuora, user: user)
          subscription_item = create :billing_subscription_item, plan_subscription: plan_subscription, subscribable: @product_uuid, quantity: failed_payment_quantity
          assert_equal subscription_item.quantity, failed_payment_quantity

          ::Billing::CollectPaymentForUpgrade.rollback(plan_subscription, user.plan, 0, user, subscription_item, quantity_to_rollback_to)
          assert_equal subscription_item.reload.quantity, quantity_to_rollback_to
          user.reload
          assert_equal user.reload.plan.name, "pro"
          assert_equal user.seats, 0
          assert_dogstats_increment(1, "billing.collect_payment_for_upgrade.rollback",
            tags: ["from_plan:pro", "from_seats:0", "to_plan:pro", "to_seats:0", "from_subscription_item_quantity:#{failed_payment_quantity}", "to_subscription_item_quantity:#{quantity_to_rollback_to}", "subscription_item_name:#{@product_uuid.name}"])
        end

        test "rolls back and cancels a newly-created product uuid subscription item" do
          subscription_item_qty = 5
          user = create(:user, :zuora, plan: "pro")
          plan_subscription = create(:billing_plan_subscription, :zuora, user: user)
          subscription_item = create :billing_subscription_item, plan_subscription: plan_subscription, subscribable: @product_uuid, quantity: subscription_item_qty
          assert_equal user.active_subscription_items.sole, subscription_item

          events = subscribe("billing.subscription_item_cancelled")
          ::Billing::CollectPaymentForUpgrade.rollback(plan_subscription, user.plan, 0, user, subscription_item, 0)

          expected_payload = {
            subscription_item_id: subscription_item.id,
            product_type: @product_uuid.product_type,
            billing_cycle: @product_uuid.billing_cycle,
            previous_quantity: subscription_item_qty
          }

          event = events.sole
          assert_equal "billing.subscription_item_cancelled", event.name
          assert_subset_hash expected_payload, event.payload
          assert_empty user.active_subscription_items
          assert_dogstats_increment(1, "billing.collect_payment_for_upgrade.rollback",
            tags: ["from_plan:pro", "from_seats:0", "to_plan:pro", "to_seats:0", "from_subscription_item_quantity:#{subscription_item_qty}", "to_subscription_item_quantity:0", "subscription_item_name:#{@product_uuid.name}"])
        end
      end

      context "for an organization" do
        test "rolls back the organization plan from business_plus to business" do
          org = create(:organization, :zuora, plan: "business_plus", seats: 10)
          plan_subscription = create(:billing_plan_subscription, :zuora, user: org)

          events = assert_performed_audit_entries(count: 1, only: "account.plan_change") do
            ::Billing::CollectPaymentForUpgrade.rollback(plan_subscription, GitHub::Plan.business, 10, org.admin)
          end

          org.reload
          assert_equal "business", org.plan.name
          assert_equal 10, org.seats
          assert_subset_hash({ old_plan: "business_plus", plan: "business", reason: "payment collection failed" }, events.first)
          assert_dogstats_increment(1, "billing.collect_payment_for_upgrade.rollback",
            tags: ["from_plan:business_plus", "from_seats:10", "to_plan:business", "to_seats:10"])
        end

        test "rolls back the organization seats" do
          org = create(:organization, :zuora, plan: "business", seats: 20)
          plan_subscription = create(:billing_plan_subscription, :zuora, user: org)

          events = assert_performed_audit_entries(count: 1, only: "account.plan_change") do
            ::Billing::CollectPaymentForUpgrade.rollback(plan_subscription, GitHub::Plan.business, 10, org.admin)
          end

          org.reload
          assert_equal "business", org.plan.name
          assert_equal 10, org.seats
          assert_subset_hash({ old_seats: 20, seats: 10, reason: "payment collection failed" }, events.last)
          assert_dogstats_increment(1, "billing.collect_payment_for_upgrade.rollback",
            tags: ["from_plan:business", "from_seats:20", "to_plan:business", "to_seats:10"])
        end

        test "rolls back the organization plan from business to free" do
          org = create(:organization, :zuora, plan: "business", seats: 10)
          plan_subscription = create(:billing_plan_subscription, :zuora, user: org)

          events = assert_performed_audit_entries(count: 2, only: "account.plan_change") do
            ::Billing::CollectPaymentForUpgrade.rollback(plan_subscription, GitHub::Plan.free, 0, org.admin)
          end

          org.reload
          assert_equal "free", org.plan.name
          assert_equal 0, org.seats
          assert_subset_hash({ old_plan: "business", plan: "free", reason: "payment collection failed" }, events.first)
          assert_subset_hash({ old_seats: 10, seats: 0, reason: "payment collection failed" }, events.last)
          assert_dogstats_increment(1, "billing.collect_payment_for_upgrade.rollback",
            tags: ["from_plan:business", "from_seats:10", "to_plan:free", "to_seats:0"])
        end

        test "rolls back the subscription item quantity" do
          quantity_to_rollback_to = 5
          failed_payment_quantity = 10
          org = create(:organization, :zuora, plan: "business", seats: 15)
          plan_subscription = create(:billing_plan_subscription, :zuora, user: org)
          subscription_item = create :billing_subscription_item, plan_subscription: plan_subscription, subscribable: @product_uuid, quantity: failed_payment_quantity
          assert_equal subscription_item.quantity, failed_payment_quantity

          ::Billing::CollectPaymentForUpgrade.rollback(plan_subscription, org.plan, org.seats, org.owner, subscription_item, quantity_to_rollback_to)
          assert_equal subscription_item.reload.quantity, quantity_to_rollback_to
          org.reload
          assert_equal org.plan.name, "business"
          assert_equal org.seats, 15
          assert_dogstats_increment(1, "billing.collect_payment_for_upgrade.rollback",
            tags: ["from_plan:business", "from_seats:15", "to_plan:business", "to_seats:15", "from_subscription_item_quantity:#{failed_payment_quantity}", "to_subscription_item_quantity:#{quantity_to_rollback_to}", "subscription_item_name:#{@product_uuid.name}"])
        end

        test "rolls back and cancels a newly-created product uuid subscription item" do
          subscription_item_qty = 5
          org = create(:organization, :zuora, plan: "business", seats: subscription_item_qty)
          plan_subscription = create(:billing_plan_subscription, :zuora, user: org)
          subscription_item = create :billing_subscription_item, plan_subscription: plan_subscription, subscribable: @product_uuid, quantity: subscription_item_qty
          assert_equal org.active_subscription_items.sole, subscription_item

          events = subscribe("billing.subscription_item_cancelled")
          ::Billing::CollectPaymentForUpgrade.rollback(plan_subscription, org.plan, org.seats, org.owner, subscription_item, 0)

          expected_payload = {
            subscription_item_id: subscription_item.id,
            product_type: @product_uuid.product_type,
            billing_cycle: @product_uuid.billing_cycle,
            previous_quantity: subscription_item_qty
          }

          event = events.sole
          assert_equal "billing.subscription_item_cancelled", event.name
          assert_subset_hash expected_payload, event.payload
          assert_empty org.active_subscription_items
          assert_dogstats_increment(1, "billing.collect_payment_for_upgrade.rollback",
            tags: ["from_plan:business", "from_seats:#{org.seats}", "to_plan:business", "to_seats:#{org.seats}", "from_subscription_item_quantity:#{subscription_item_qty}", "to_subscription_item_quantity:0", "subscription_item_name:#{@product_uuid.name}"])
        end
      end

      context "for a business" do
        test "rolls back the business seats" do
          org = create(:organization)
          business = create(:business, organizations: [org], seats: 50)
          plan_subscription = create(:billing_plan_subscription, :business_owned, customer: business.customer)

          ::Billing::CollectPaymentForUpgrade.rollback(plan_subscription, GitHub::Plan.business_plus, 10,
            org.admin)

          assert_equal 10, business.reload.seats
          assert_dogstats_increment(1, "billing.collect_payment_for_upgrade.rollback",
            tags: ["from_plan:business_plus", "from_seats:50", "to_plan:business_plus", "to_seats:10"])
        end

        test "rolls back the subscription item quantity" do
          business = create(:billing_plan_subscription, :business_owned).business
          owner = business.owners.first
          plan_subscription = business.plan_subscription
          quantity_to_rollback_to = 5
          failed_payment_quantity = 10
          subscription_item = create :billing_subscription_item, plan_subscription: plan_subscription, subscribable: @product_uuid, quantity: failed_payment_quantity
          assert_equal subscription_item.quantity, failed_payment_quantity

          ::Billing::CollectPaymentForUpgrade.rollback(plan_subscription, business.plan, business.seats, owner, subscription_item, quantity_to_rollback_to)
          assert_equal subscription_item.reload.quantity, quantity_to_rollback_to
          business.reload
          assert_equal business.plan.name, "business_plus"
          assert_equal business.seats, 100
          assert_dogstats_increment(1, "billing.collect_payment_for_upgrade.rollback",
            tags: ["from_plan:business_plus", "from_seats:#{business.seats}", "to_plan:business_plus", "to_seats:#{business.seats}", "from_subscription_item_quantity:#{failed_payment_quantity}", "to_subscription_item_quantity:#{quantity_to_rollback_to}", "subscription_item_name:#{@product_uuid.name}"])
        end

        test "rolls back and cancels a newly-created product uuid subscription item" do
          business = create(:billing_plan_subscription, :business_owned).business
          owner = business.owners.first
          plan_subscription = business.plan_subscription
          subscription_item_qty = 5
          subscription_item = create :billing_subscription_item, plan_subscription: plan_subscription, subscribable: @product_uuid, quantity: subscription_item_qty
          assert_equal business.active_subscription_items.sole, subscription_item

          events = subscribe("billing.subscription_item_cancelled")
          ::Billing::CollectPaymentForUpgrade.rollback(plan_subscription, business.plan, business.seats, owner, subscription_item, 0)

          expected_payload = {
            subscription_item_id: subscription_item.id,
            sender_id: owner.id,
            business_id: business.id,
            product_type: @product_uuid.product_type,
            billing_cycle: @product_uuid.billing_cycle,
            previous_quantity: subscription_item_qty
          }

          event = events.sole
          assert_equal "billing.subscription_item_cancelled", event.name
          assert_subset_hash expected_payload, event.payload
          assert_empty business.active_subscription_items
          assert_dogstats_increment(1, "billing.collect_payment_for_upgrade.rollback",
            tags: ["from_plan:business_plus", "from_seats:#{business.seats}", "to_plan:business_plus", "to_seats:#{business.seats}", "from_subscription_item_quantity:#{subscription_item_qty}", "to_subscription_item_quantity:0", "subscription_item_name:#{@product_uuid.name}"])
        end
      end
    end

    context "#send_failure_notification" do
      test "sends an email to the billable entity with the default message" do
        user = create(:user, :zuora, plan: "pro")
        plan_subscription = create(:billing_plan_subscription, :zuora, user: user)

        BillingNotificationsMailer.expects(:cc_failure).with(
          user,
          "There was an issue processing your payment method."
        ).returns(stub(deliver_later: nil))

        ::Billing::CollectPaymentForUpgrade.send_failure_notification(plan_subscription, GitHub::Plan.free, 0, user)
      end
    end
  end
end
