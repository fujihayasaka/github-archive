# typed: true
# frozen_string_literal: true

require "test_helper"

class AdvancedSecurity::Public::Subscription::OrganizationTest < GitHub::TestCase

  include AuditLog::IntegrationTestHelpers
  include DogstatsTestHelpers

  fixtures do
    @organization = create(:credit_card_org, plan: "business_plus")
    @user = create :user
    @organization.add_admin(@user)

    @billing_plan_subscription = create(:billing_plan_subscription, :business_owned)
    @child_org = create(:enterprise_linked_organization, admin: @owner, business: @billing_plan_subscription.business)

    @advanced_security_month_product_uuid = create(:billing_product_uuid, :advanced_security)
    @advanced_security_year_product_uuid = create(:billing_product_uuid, :advanced_security, :yearly)

    @advanced_security_monthly_product = AdvancedSecurity::Public::Subscription::ADVANCED_SECURITY_MONTHLY_PRODUCT
    @advanced_security_yearly_product = AdvancedSecurity::Public::Subscription::ADVANCED_SECURITY_YEARLY_PRODUCT
  end

  setup do
    @business = @billing_plan_subscription.business
    @owner = @business.owners.first
    enable_feature_flag(:ghas_self_serve_orgs, @organization)
  end

  context "#subscribe_to_advanced_security_trial?" do
    test "creates a trial subscription item with an organization" do
      jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")

      travel_to jan_1st do
        free_trial_end_date = GitHub::Billing.today + 31.days
        result = @organization.subscribe_to_advanced_security_trial(
          actor: @user,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        assert result.ok?
        assert result.value!.on_free_trial?
        assert @organization.advanced_security_purchased_for_entity?

        assert_equal 1, @organization.advanced_security_seats_for_entity

        # verify that a pending plan change to quantity 0, is scheduled for trial experation.
        assert_equal 1, @organization.pending_plan_changes.count
        pending_plan_change = @organization.pending_plan_changes.first
        assert_equal false, pending_plan_change.is_complete
        assert_equal free_trial_end_date, pending_plan_change.active_on
        assert_equal 1, pending_plan_change.pending_subscription_item_changes.count

        pending_subscription_item_change = pending_plan_change.pending_subscription_item_changes.first
        assert_equal 0, pending_subscription_item_change.quantity
        assert_equal true, pending_subscription_item_change.free_trial
      end
    end

    test "Does not audit organization.subscribe_to_advanced_security_trial because not implemented yet" do
      assert_performed_audit_entries(count: 0, only: "organization.advanced_security_trial_created") do
        result = @organization.subscribe_to_advanced_security_trial(
          actor: @user,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month
        )
        assert result.ok?
      end
      assert_dogstats_increment(1, "organization.advanced_security_trial_created")
    end

    test "fails when the ghas_self_serve_orgs flag is turned off" do
      disable_feature_flag(:ghas_self_serve_orgs, @organization)

      result = @organization.subscribe_to_advanced_security_trial(
        actor: @user,
        billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
      refute result.ok?
      assert_equal "GHAS is not currently enabled for organizations.", result.error.message
    end
  end

  context "#has_active_advanced_security_trial?" do
    test "returns false when the organization has no trial " do
      refute @organization.has_active_advanced_security_trial?
    end

    test "returns true when the organization has an active trial" do
      jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")

      travel_to jan_1st do
        result = @organization.subscribe_to_advanced_security_trial(
          actor: @user,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        assert result.ok?
        assert @organization.has_active_advanced_security_trial?
      end
    end

    test "returns false when the trial was cancelled" do
      jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")

      travel_to jan_1st do
        result = @organization.subscribe_to_advanced_security_trial(
          actor: @user,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        assert result.ok?
        assert_equal 1, @organization.pending_plan_changes.count
        @organization.pending_plan_changes.first.run
        refute @organization.has_active_advanced_security_trial?
      end
    end

    test "returns false when has active subscription" do
      jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")

      travel_to jan_1st do
        result = @organization.subscribe_to_advanced_security(
          actor: @user,
          seats: 1,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        assert result.ok?
        refute @organization.has_active_advanced_security_trial?
      end
    end
  end

  context "#has_advanced_security_trial_in_the_last_year?" do
    test "returns true when the organization has active trial" do
      jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")
      travel_to jan_1st do
        result = @organization.subscribe_to_advanced_security_trial(
          actor: @user,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        assert result.ok?
        assert @organization.has_advanced_security_trial_in_the_last_year?
      end
    end

    test "returns true when the organization has cancelled trial" do
      jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")
      travel_to jan_1st do
        result = @organization.subscribe_to_advanced_security_trial(
          actor: @user,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        assert result.ok?
        assert_equal 1, @organization.pending_plan_changes.count
        @organization.pending_plan_changes.first.run
        assert @organization.has_advanced_security_trial_in_the_last_year?
      end
    end

    test "returns true when the organization has had trial in last year" do
      june_1st_2022 = GitHub::Billing.date_in_timezone Date.parse("2022-06-01")
      jan_1st_2023 = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")
      july_1st_2023 = GitHub::Billing.date_in_timezone Date.parse("2023-07-01")
      travel_to june_1st_2022 do
        result = @organization.subscribe_to_advanced_security_trial(
          actor: @user,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        assert result.ok?
        assert_equal 1, @organization.pending_plan_changes.count
        @organization.pending_plan_changes.first.run
        assert @organization.has_advanced_security_trial_in_the_last_year?
      end
      travel_to jan_1st_2023 do
        assert @organization.has_advanced_security_trial_in_the_last_year?
      end
      travel_to july_1st_2023 do
        refute @organization.has_advanced_security_trial_in_the_last_year?
      end
    end
  end

  context "#subscribe_to_advanced_security" do
    test "successfully creates a ghas subscription item for an organization" do

      result = @organization.subscribe_to_advanced_security(seats: 5, actor: @user, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)

      assert result.ok?
      assert @organization.advanced_security_purchased_for_entity?
      assert_equal @organization.advanced_security_seats_for_entity, 5
    end

    test "Does not audit organization.advanced_security_subscribed because not implemented yet" do
      assert_performed_audit_entries(count: 0, only: "organization.advanced_security_subscribed") do
        result = @organization.subscribe_to_advanced_security(
          actor: @user,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month,
          seats: 8
        )
        assert result.ok?
      end
      assert_dogstats_increment(1, "organization.advanced_security_subscribed")
    end

    test "instruments failure" do
      error = AdvancedSecurity::Public::Subscription::UnprocessableError.new("GHAS is not currently enabled for purchase.")
      Organization.any_instance.stubs(:subscribe_to_product).returns(GitHub::Result.error(error))

      result = @organization.subscribe_to_advanced_security(
        actor: @user,
        billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month,
        seats: 8
      )

      refute_dogstats_increment("organization.advanced_security_subscribed")
      assert_dogstats_increment(1, "organization.advanced_security_subscribed.error")
    end

    test "fails when a user tries to add a new ghas subscription item" do
      @plan_subscription = create(:billing_plan_subscription, :zuora)
      @plan_user = @plan_subscription.user

      enable_feature_flag(:ghas_self_serve_orgs, @plan_user)

      error = assert_raises TypeError do
        @plan_user.subscribe_to_advanced_security(seats: 5, actor: @plan_user, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
      end

      refute @plan_user.subscribed_to_product?(@advanced_security_monthly_product)
    end

    test "fails when the org specific feature flag is turned off" do
      disable_feature_flag(:ghas_self_serve_orgs, @organization)

      result = @organization.subscribe_to_advanced_security(seats: 5, actor: @user, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)

      refute result.ok?
      assert_match result.error.message, "GHAS is not currently enabled for organizations."
    end

    test "creates a monthly subscription when the billing duration is monthly" do
      result = @organization.subscribe_to_advanced_security(seats: 5, actor: @user, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)

      assert result.ok?
      assert @organization.has_active_monthly_advanced_security_subscription?
    end

    test "creates a yearly subscription when the billing duration is yearly when the feature flag is enabled" do
      enable_feature_flag(:ghas_self_serve_post_mvp, @organization)
      result = @organization.subscribe_to_advanced_security(seats: 5, actor: @user, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Year)
      assert result.ok?
      assert @organization.has_active_yearly_advanced_security_subscription?
    end

    test "does not create a yearly subscription when the billing duration is yearly when the feature flag is disabled" do
      disable_feature_flag(:ghas_self_serve_post_mvp, @organization)

      result = @organization.subscribe_to_advanced_security(seats: 5, actor: @user, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Year)

      refute result.ok?
      refute @organization.has_active_yearly_advanced_security_subscription?
      refute @organization.has_active_monthly_advanced_security_subscription?
    end
  end

  context "#extend_advanced_security_trial" do
    test "can extend trial" do
      jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")
      disable_feature_flag(:skip_immediate_payment_collection_for_plan_or_seat_changes)

      travel_to jan_1st do
        free_trial_end_date = GitHub::Billing.today + 30.days
        result = @organization.subscribe_to_advanced_security_trial(
          actor: @user,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        assert result.ok?
        assert result.value!.on_free_trial?
        assert @organization.advanced_security_purchased_for_entity?
        assert_equal 1, @organization.pending_plan_changes.count

        assert @organization.has_active_advanced_security_trial?

        result = @organization.extend_advanced_security_trial(
          actor: @user,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month,
          days: 5
        )
        assert result.ok?

        item_id = @organization.advanced_security_subscription_item.id
        subscription_item = Billing::SubscriptionItem.find(item_id)
        assert subscription_item.present? && subscription_item.is_a?(Billing::SubscriptionItem)

        assert @organization.has_active_advanced_security_trial?
        assert_equal 1, @organization.pending_plan_changes.count
        assert_equal free_trial_end_date + 5.days + 1.day, @organization.pending_plan_changes.first.active_on
        assert_equal free_trial_end_date + 5.days, subscription_item.free_trial_ends_on
        assert_equal 1, @organization.pending_plan_changes.first.pending_subscription_item_changes.count
        assert_equal 0, @organization.pending_plan_changes.first.pending_subscription_item_changes.first.quantity
      end
    end

    test "Does not audit organization.advanced_security_trial_extended_in_stafftools because not implemented yet" do
      jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")
      disable_feature_flag(:skip_immediate_payment_collection_for_plan_or_seat_changes)

      travel_to jan_1st do
        free_trial_end_date = GitHub::Billing.today + 30.days
        result = @organization.subscribe_to_advanced_security_trial(
          actor: @user,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        assert result.ok?
        assert result.value!.on_free_trial?
        assert @organization.advanced_security_purchased_for_entity?
        assert_equal 1, @organization.pending_plan_changes.count

        assert @organization.has_active_advanced_security_trial?

        assert_performed_audit_entries(count: 0, only: "organization.advanced_security_trial_extended_in_stafftools") do
          result = @organization.extend_advanced_security_trial(
            actor: @user,
            billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month,
            days: 5
          )
          assert result.ok?
        end
        assert_dogstats_increment(1, "organization.advanced_security_trial_extended_in_stafftools")
      end
    end

    test "actor must be able to manage organization to extend trial" do
      jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")
      disable_feature_flag(:skip_immediate_payment_collection_for_plan_or_seat_changes)

      rando = create(:user)
      travel_to jan_1st do
        result = @organization.subscribe_to_advanced_security_trial(
          actor: @user,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        assert result.ok?
        assert result.value!.on_free_trial?
        assert @organization.advanced_security_purchased_for_entity?
        assert_equal 1, @organization.pending_plan_changes.count

        assert @organization.has_active_advanced_security_trial?

        result = @organization.extend_advanced_security_trial(
          actor: rando,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month,
          days: 5
        )
        refute result.ok?
        assert_equal "#{rando} does not have permission to manage this account (#{@organization})", result.error.message
      end
    end
  end

  context "#end_advanced_security_trial_without_purchasing_now" do
    test "can end a trial early without purchase" do
      jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")
      disable_feature_flag(:skip_immediate_payment_collection_for_plan_or_seat_changes)

      travel_to jan_1st do
        result = @organization.subscribe_to_advanced_security_trial(
          actor: @user,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        assert result.ok?
        assert result.value!.on_free_trial?
        assert @organization.advanced_security_purchased_for_entity?
        assert_equal 1, @organization.pending_plan_changes.count

        assert @organization.has_active_advanced_security_trial?
        assert @organization.has_advanced_security_trial_in_the_last_year?

        assert_enqueued_jobs(1, only: SynchronizePlanSubscriptionJob) do
          assert_enqueued_jobs(0, only: CollectPaymentForUpgradeJob) do
            result = @organization.end_advanced_security_trial_without_purchasing_now(
              actor: @user,
              billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month,
              is_stafftools_action: true
            )
            assert result.ok?
            refute result.value!.on_free_trial?
          end
        end

        refute @organization.has_active_advanced_security_trial?
        assert @organization.has_advanced_security_trial_in_the_last_year?
        assert_equal 0, @organization.advanced_security_seats_for_entity
      end
    end

    test "does not audit organization.advanced_security_trial_ended_immediately_in_stafftools because not implemented yet" do
      jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")
      disable_feature_flag(:skip_immediate_payment_collection_for_plan_or_seat_changes)

      travel_to jan_1st do
        free_trial_end_date = GitHub::Billing.today + 15.days
        result = @organization.subscribe_to_advanced_security_trial(
          actor: @user,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        assert result.ok?
        assert result.value!.on_free_trial?
        assert @organization.advanced_security_purchased_for_entity?
        assert_equal 1, @organization.pending_plan_changes.count

        assert @organization.has_active_advanced_security_trial?
        assert @organization.has_advanced_security_trial_in_the_last_year?

        assert_performed_audit_entries(count: 0, only: "organization.advanced_security_trial_ended_immediately_in_stafftools") do
          result = @organization.end_advanced_security_trial_without_purchasing_now(
            actor: @user,
            billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month,
            is_stafftools_action: true,
          )
          assert result.ok?
          refute result.value!.on_free_trial?
        end

        assert_dogstats_increment(1, "organization.advanced_security_trial_ended_immediately_in_stafftools")

        refute @organization.has_active_advanced_security_trial?
        assert @organization.has_advanced_security_trial_in_the_last_year?
        assert_equal 0, @organization.advanced_security_seats_for_entity
      end
    end
  end

  context "#advanced_security_subscription_change" do
    test "returns nil if there is no pending advanced security change" do
      assert_nil @organization.advanced_security_subscription_change
    end

    test "returns last ghas subscription change" do
      @advanced_security_product_uuid = create(:billing_product_uuid, :advanced_security)
      num_seats = 5
      @organization.subscribe_to_advanced_security(seats: num_seats, actor: @user, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
      @organization.set_advanced_security_seats_for_entity(seats: num_seats - 1, actor: @user)
      last_pending_change = @organization.pending_subscription_item_changes.last

      assert_equal "GitHub Advanced Security", last_pending_change.subscribable.name
      assert_equal last_pending_change, @organization.advanced_security_subscription_change
    end
  end

  context "#eligible_for_self_serve_advanced_security" do
    test "returns false because not implemented yet" do
      refute @organization.eligible_for_self_serve_advanced_security?
    end
  end

  context "#eligible_for_self_serve_advanced_security_trial" do
    test "returns false because not implemented yet" do
      refute @organization.eligible_for_self_serve_advanced_security_trial?
    end
  end

  context "#potentially_trial_or_purchase_advanced_security" do
    test "returns false because not implemented yet" do
      refute @organization.potentially_trial_or_purchase_advanced_security?
    end
  end

  context "#new_advanced_security_trial_days", skip_with_all_emus: true do
    test "returns 30 days if EA is purchased" do
      assert_equal 30, @organization.new_advanced_security_trial_days
    end
  end

  context "#show_advanced_security_onboarding?" do
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
        assert @child_org.show_advanced_security_onboarding?
      end
    end

    test "returns true if trial is recent" do
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
        assert @child_org.show_advanced_security_onboarding?
      end
      travel_to end_date_plus_seven do
        assert @business.show_advanced_security_onboarding?
        assert @child_org.show_advanced_security_onboarding?
      end
      travel_to end_date_plus_eight do
        refute @business.show_advanced_security_onboarding?
        refute @child_org.show_advanced_security_onboarding?
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
      refute @child_org.show_advanced_security_onboarding?
    end

    test "returns false if purchased" do
      @business.subscribe_to_advanced_security(seats: 3, actor: @owner, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)

      refute @business.has_active_advanced_security_trial?
      assert @business.has_self_serve_advanced_security?
      refute @business.show_advanced_security_onboarding?
      refute @child_org.show_advanced_security_onboarding?
    end

    test "returns false if organization does not belong to Business" do
      refute @child_org.show_advanced_security_onboarding?
    end
  end


  context "never_billed_for_self_serve_advanced_security?" do
    test "returns false with successful transaction" do
      result = @organization.subscribe_to_advanced_security(seats: 5, actor: @user, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)

      assert result.ok?
      assert @organization.advanced_security_purchased_for_entity?
      assert_equal @organization.advanced_security_seats_for_entity, 5


      transaction = create(:billing_transaction, user: @organization, amount_in_cents: 196_00)

      line_item = create(:billing_transaction_line_item,
        billing_transaction: transaction,
        subscribable: @advanced_security_month_product_uuid,
        amount_in_cents: 196_00,
        quantity: 4,
        description: "GitHub Advanced Security",
        subscribable_type: Billing::ProductUUID.name
      )
      refute @organization.never_billed_for_self_serve_advanced_security?
    end

    test "returns false with a failed transaction" do
      result = @organization.subscribe_to_advanced_security(seats: 5, actor: @user, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)

      assert result.ok?
      assert @organization.advanced_security_purchased_for_entity?
      assert_equal @organization.advanced_security_seats_for_entity, 5


      transaction = create(:billing_transaction, user: @organization, amount_in_cents: 196_00, last_status: :failed)

      line_item = create(:billing_transaction_line_item,
        billing_transaction: transaction,
        subscribable: @advanced_security_month_product_uuid,
        amount_in_cents: 196_00,
        quantity: 4,
        description: "GitHub Advanced Security",
        subscribable_type: Billing::ProductUUID.name
      )
      refute @organization.never_billed_for_self_serve_advanced_security?
    end

    test "returns true with no transactions" do
      result = @organization.subscribe_to_advanced_security(seats: 5, actor: @user, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)

      assert result.ok?
      assert @organization.advanced_security_purchased_for_entity?
      assert_equal @organization.advanced_security_seats_for_entity, 5

      assert @organization.never_billed_for_self_serve_advanced_security?
    end

    test "returns true with 0 transaction amount" do
      result = @organization.subscribe_to_advanced_security(seats: 5, actor: @user, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)

      assert result.ok?
      assert @organization.advanced_security_purchased_for_entity?
      assert_equal @organization.advanced_security_seats_for_entity, 5

      transaction = create(:billing_transaction, user: @organization, amount_in_cents: 0)

      line_item = create(:billing_transaction_line_item,
        billing_transaction: transaction,
        subscribable: @advanced_security_month_product_uuid,
        amount_in_cents: 0,
        quantity: 4,
        description: "GitHub Advanced Security",
        subscribable_type: Billing::ProductUUID.name
      )

      assert @organization.never_billed_for_self_serve_advanced_security?
    end
  end
end unless GitHub.enterprise?
