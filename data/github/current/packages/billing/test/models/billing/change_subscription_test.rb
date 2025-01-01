# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::ChangeSubscriptionTest < GitHub::BillingTestCase
  include GitHub::BrainTree::TestHelper
  include GitHub::ZuoraTestHelper

  test "change plan with an invalid user fails" do
    user = User.new plan: "free"
    refute user.valid?
    result = Billing::ChangeSubscription.perform user, plan: "micro", actor: user
    refute result.success?
    assert_match(/can't be blank/, result.error_message)
  end

  test "change plan with a nil plan and no other changes fails" do
    user = create :user, plan: "pro"
    result = Billing::ChangeSubscription.perform user, plan: "pro", actor: user
    refute result.success?
    assert_match(/Already on the .* plan/, result.error_message)
  end

  test "change plan_duration succeeds" do
    user = create :credit_card_user, plan: "pro"
    perform_enqueued_jobs(only: [RunPendingPlanChangeJob]) do
      result = Billing::ChangeSubscription.perform user, plan_duration: "year", actor: user
      assert result.success?
    end
    assert_equal GitHub::Plan.pro, user.reload.plan
    assert_equal "year", user.plan_duration
  end

  test "change plan with an invalid plan name fails" do
    user = create :user, plan: "free"
    assert_raises(GitHub::Plan::Error) { Billing::ChangeSubscription.perform user, plan: "foo", actor: user }
  end

  test "change plan from free to paid without a payment method fails" do
    user = create :no_credit_card_user, plan: "free"

    result = Billing::ChangeSubscription.perform user, plan: "pro", actor: user

    refute result.success?
    assert_equal "free", user.plan.name
    assert_match(/is required/, result.error_message)
  end

  test "change plan with a failed payment method update fails" do
    user = create :no_credit_card_user, plan: "free"

    result = Billing::ChangeSubscription.perform user, plan: "pro", actor: user,
      payment_details: encrypted_credit_card_params

    refute result.success?
    assert_equal "free", user.plan.name
  end

  test "change plan with a payment method should update payment method" do
    user = create :credit_card_user, plan: "free"
    cc_number = user.payment_method.truncated_number

    result = Billing::ChangeSubscription.perform user, plan: "pro", actor: user,
      payment_details: encrypted_credit_card_params
      .merge(zuora_payment_method_id: zuora_new_payment_method_id)

    assert result.success?
    assert_equal "pro", user.plan.name
    refute_equal cc_number, user.payment_method.truncated_number
  end

  test "change plan with full coupon coverage" do
    coupon = create :coupon, discount: 50
    user = create :credit_card_user
    user.redeem_coupon coupon
    user.update_attribute :plan, "free"

    result = Billing::ChangeSubscription.perform user, plan: "pro", actor: user

    assert result.success?
    assert_equal "pro", user.reload.plan.name
  end

  test "add seats with a coupon does not give away free seats" do
    org = create :organization, plan: "business", seats: 5

    coupon = create :coupon, discount: 50
    org.redeem_coupon coupon

    result = Billing::ChangeSubscription.perform org,
      actor: org,
      seats: 50,
      seat_delta: 45,
      plan_duration: "month"

    refute result.success?
    assert_equal 5, org.reload.seats
    assert_match(/A credit card or other payment method is required/, result.error_message.to_s)
  end

  test "change plan from free to paid with a billing date in the future" do
    user = create :credit_card_user, billed_on: GitHub::Billing.today + 1.week

    result = Billing::ChangeSubscription.perform user, plan: "pro", actor: user

    assert result.success?
    assert_equal "pro", user.reload.plan.name
    assert user.has_valid_payment_method?
    refute user.zuora_subscription?
  end

  test "change yearly plan from free to paid" do
    Timecop.freeze do
      subscription = create :billing_plan_subscription, :zuora
      create_zuora_subscription(
        zuora_subscription_number: subscription.zuora_subscription_number,
      )
      user = create(:credit_card_user,
                    plan_duration: "year", plan_subscription: subscription)

      result = Billing::ChangeSubscription.perform user,
        plan: "pro",
        actor: user,
        payment_details: encrypted_credit_card_params
        .merge(zuora_payment_method_id: zuora_new_payment_method_id)

      first_billing_date = user.reload.plan_subscription.zuora_subscription.next_billing_date

      assert result.success?
      assert_equal "pro", user.plan.name
      assert user.has_valid_payment_method?
      assert_equal GitHub::Billing.today, first_billing_date
    end
  end

  test "change plan from paid to paid with a payment method on file" do
    user = create :credit_card_user, plan: "free_with_addons"

    result = Billing::ChangeSubscription.perform user, plan: "pro", actor: user

    assert result.success?
    assert_equal "pro", user.reload.plan.name
  end

  test "org admins cannot change plan from per seat back to per repository" do
    org = create :credit_card_org, plan: "business", seats: 5

    result = Billing::ChangeSubscription.perform org, plan: "bronze", actor: org.admin

    refute result.success?
    assert_equal "business", org.plan.name
  end

  test "org admins cannot change from free to repository plans" do
    org = create :credit_card_org, plan: "free"

    result = Billing::ChangeSubscription.perform org, plan: "bronze", actor: org.admin

    refute result.success?
    assert_equal "free", org.plan.name
  end

  test "staff can change plan from per seat back to a repository plan" do
    org = create :credit_card_org, plan: "business", seats: 1

    staff = create(:staff_admin_user)

    result = Billing::ChangeSubscription.perform org, plan: "bronze", actor: staff

    assert result.success?
    assert_equal "bronze", org.reload.plan.name
  end

  test "change plan for a disabled account to a plan that accommodates repos enables account" do
    GitHub.flipper[:billing_strict_disable].disable
    user = create :no_credit_card_user, plan: "pro"
    create :private_repository, owner: user
    locked_repo = create :private_repository, owner: user
    locked_repo.lock_for_billing
    # disable account
    user.reload.update plan: "free"
    user.disable!
    assert user.reload.disabled?

    perform_enqueued_jobs(only: [UpdateLockedRepositoriesJob]) do
      result = Billing::ChangeSubscription.perform user, plan: "pro", actor: user,
        payment_details: encrypted_credit_card_params
        .merge(zuora_payment_method_id: zuora_new_payment_method_id)

      assert result.success?
    end

    refute user.reload.disabled?
    refute locked_repo.reload.locked
  end

  test "upgrading plan with successful payment details doesn't disable an account with prior billing attempts" do
    user = create :credit_card_user,
      plan: "free",
      billed_on: GitHub::Billing.today - 2.months,
      billing_attempts: User::BillingDependency::BILLING_ATTEMPTS_LIMIT

    assert_predicate user, :should_disable?

    result = Billing::ChangeSubscription.perform user, plan: "pro", actor: user

    assert_predicate result, :success?
    assert_predicate user.reload, :enabled?
  end

  test "prevent changing from a paid plan to one that is too small" do
    user = create :credit_card_user, plan: "small"
    create :billing_plan_subscription, :zuora, user: user
    6.times { create(:private_repository, owner: user) }
    user.reload

    result = Billing::ChangeSubscription.perform user, plan: "micro", actor: user

    refute result.success?
    refute user.reload.disabled?
  end

  test "change plan to free switches to free-with-addons plan if you have asset packs" do
    subscription = create :billing_plan_subscription, :zuora

    user = create :credit_card_user, plan: "free", plan_subscription: subscription

    Asset::Status.create! owner: user, asset_packs: 2
    create(:private_repository, owner: user)
    assert_equal 1, user.reload.private_repo_count_for_limit_check

    result = Billing::ChangeSubscription.perform user, plan: "free", actor: user

    user.reload
    assert result.success?, "Plan change should succeed"
    assert user.zuora_subscription?, "User should still have a zuora subscription"

    refute user.disabled?, "User repos should not disabled, as free users can have private repos"
    assert_equal "free_with_addons", user.plan.name
  end

  test "changes plan successfully for an invoiced organization as staff" do
    invoiced_organization = create :organization, \
      billing_type: "invoice",
      plan: "free"
    staff = create :staff_admin_user

    result = Billing::ChangeSubscription.perform \
      invoiced_organization,
      plan: "bronze",
      actor: staff

    assert result.success?
    assert_equal "bronze", invoiced_organization.reload.plan.to_s
  end

  test "cannot change plan for an invoiced organization" do
    invoiced_organization = create :organization, \
      billing_type: "invoice",
      plan: "business"

    admin = invoiced_organization.admins.first

    result = Billing::ChangeSubscription.perform \
      invoiced_organization,
      plan: "business_plus",
      actor: admin

    refute result.success?
    assert_equal "business", invoiced_organization.reload.plan.to_s
  end

  test "cannot cancel plan for an invoiced organization" do
    invoiced_organization = create :organization, \
      billing_type: "invoice",
      plan: "business"

    admin = invoiced_organization.admins.first

    result = Billing::ChangeSubscription.perform \
      invoiced_organization,
      plan: "free",
      actor: admin

    refute result.success?
    assert_equal "business", invoiced_organization.reload.plan.to_s
  end

  test "successfully adds seats" do
    organization = create :credit_card_org,
      plan: "business",
      seats: 100
    create :billing_plan_subscription, user: organization
    organization.reload

    result = Billing::ChangeSubscription.perform \
      organization,
      plan: organization.plan,
      actor: organization,
      seats: 120,
      seat_delta: 20
    assert result.success?
    assert_equal 120, organization.reload.seats
  end

  test "successfully adds seats when disabled due to plan limit" do
    organization = create :credit_card_org,
      plan: "business",
      seats: 100,
      disabled: true
    create :billing_plan_subscription, user: organization
    organization.reload
    Organization.any_instance.stubs(:over_plan_limit?).returns(true)

    result = Billing::ChangeSubscription.perform \
      organization,
      plan: organization.plan,
      actor: organization,
      seats: 120,
      seat_delta: 20
    assert result.success?
    assert_equal 120, organization.reload.seats
  end

  test "add seats on a trial should not change pending_plan_change to `business_plus`" do
    organization = create :credit_card_org,
      plan: "business",
      seats: 100
    create :billing_plan_subscription, user: organization
    Billing::EnterpriseCloudTrial.new(organization).create


    result = Billing::ChangeSubscription.perform organization,
      actor: organization,
      seats: 120,
      seat_delta: 20,
      plan_duration: "month"

    organization.reload

    assert result.success?
    assert_equal 120, organization.reload.seats
    assert_equal GitHub::Plan.business.name, organization.pending_plan_changes.last.plan.name
  end

  test "successful seat removal when user is spammy" do
    user = create(:user)
    organization = create :credit_card_org,
      plan: "business",
      seats: 100
    create :billing_plan_subscription, user: organization
    organization.reload
    organization.add_admin user
    organization.mark_as_spammy
    user.mark_as_spammy

    perform_enqueued_jobs(only: [RunPendingPlanChangeJob]) do
      result = Billing::ChangeSubscription.perform \
        organization,
        plan: organization.plan,
        actor: user,
        seats: 80,
        seat_delta: -20

      assert result.success?
    end

    assert_equal 80, organization.reload.seats
  end

  test "successful seat removal when org is disabled" do
    user = create(:user)
    organization = create :credit_card_org,
      plan: "business",
      seats: 100,
      disabled: true
    create :billing_plan_subscription, user: organization
    organization.reload
    organization.add_admin user

    perform_enqueued_jobs(only: [RunPendingPlanChangeJob]) do
      result = Billing::ChangeSubscription.perform \
        organization,
        plan: organization.plan,
        actor: user,
        seats: 80,
        seat_delta: -20

      assert result.success?
    end

    assert_equal 80, organization.reload.seats
  end

  test "remove seats on trial should not change pending_plan_change to `business_plus`" do
    organization = create :credit_card_org,
      plan: "business",
      seats: 100
    create :billing_plan_subscription, user: organization
    Billing::EnterpriseCloudTrial.new(organization).create

    perform_enqueued_jobs(only: [RunPendingPlanChangeJob]) do
      result = Billing::ChangeSubscription.perform \
        organization,
        plan: organization.plan,
        actor: organization,
        seats: 80,
        seat_delta: -20
      assert result.success?
    end

    assert_equal 80, organization.reload.seats
    assert_equal GitHub::Plan.business.name, organization.pending_plan_changes.first.plan.name
  end

  test "cannot add seats when user is spammy" do
    user = create(:user)
    organization = create :credit_card_org,
      plan: "business",
      seats: 100
    organization.add_admin user
    create :billing_plan_subscription, user: organization
    organization.reload
    user.mark_as_spammy

    result = Billing::ChangeSubscription.perform \
      organization,
      plan: organization.plan,
      actor: user,
      seats: 120,
      seat_delta: 20

    refute result.success?
    assert_match(/Your account is flagged and unable to make purchases/, result.error_message)
    assert_equal 100, organization.reload.seats
  end

  test "cannot add seats when org is spammy" do
    user = create(:user)
    organization = create :credit_card_org,
      plan: "business",
      seats: 100
    organization.add_admin user
    create :billing_plan_subscription, user: organization
    organization.reload
    organization.mark_as_spammy

    result = Billing::ChangeSubscription.perform \
      organization,
      plan: organization.plan,
      actor: user,
      seats: 120,
      seat_delta: 20

    refute result.success?
    assert_match(/Your account is flagged and unable to make purchases/, result.error_message)
    assert_equal 100, organization.reload.seats
  end

  test "cannot add seats when org is disabled due to a payment issue" do
    user = create(:user)
    organization = create :credit_card_org,
      plan: "business",
      seats: 100,
      disabled: true,
      billing_attempts: 3
    organization.add_admin user
    create :billing_plan_subscription, user: organization
    organization.reload

    result = Billing::ChangeSubscription.perform \
      organization,
      plan: organization.plan,
      actor: user,
      seats: 120,
      seat_delta: 20

    refute result.success?
    assert_match(/Your account is currently locked from purchases/, result.error_message)
    assert_equal 100, organization.reload.seats
  end

  test "cannot add seats when org has trade restrictions" do
    GitHub.flipper[:always_check_trade_restrictions_for_purchases].enable
    user = create(:user)
    organization = create :credit_card_org, :partially_trade_restricted,
      plan: "business",
      seats: 100
    organization.add_admin user
    create :billing_plan_subscription, user: organization
    organization.reload

    result = Billing::ChangeSubscription.perform \
      organization,
      plan: organization.plan,
      actor: user,
      seats: 120,
      seat_delta: 20

    refute result.success?
    assert_match(/Due to U.S. trade controls law restrictions, your GitHub account has been restricted/, result.error_message)
    assert_equal 100, organization.reload.seats
  end

  test "cannot change seats for invoiced orgs" do
    organization = create :credit_card_org,
      billing_type: "invoice",
      plan: "business",
      seats: 100
    create :billing_plan_subscription, user: organization
    organization.reload

    result = Billing::ChangeSubscription.perform \
      organization,
      plan: organization.plan,
      actor: organization,
      seats: 120,
      seat_delta: 20
    refute result.success?
    assert_equal 100, organization.reload.seats
  end

  test "tracks subscription item changes" do
    user = create :credit_card_user, plan: "pro",
      billed_on: GitHub::Billing.today

    assert_difference "Billing::PendingPlanChange.count", 1 do
      result = Billing::ChangeSubscription.perform user, plan_duration: "year", actor: user
      assert result.success?
    end

    change = user.pending_plan_changes.last
    assert_equal "year", change.plan_duration
    assert_equal user.billed_on, change.active_on
    assert_equal "month", user.plan_duration
  end

  test "creates a scheduled downgrade when lowering seat count" do
    org = create :credit_card_org, plan: GitHub::Plan.business, seats: 20,
      billed_on: GitHub::Billing.today + 1.month

    assert_difference "Billing::PendingPlanChange.count", 1 do
      result = Billing::ChangeSubscription.perform org, seats: 10, actor: org

      assert result.success?
    end

    change = org.pending_plan_changes.last
    assert_equal 10, change.seats
    assert_equal 20, org.reload.seats
    assert_equal org.billed_on, change.active_on
  end

  test "applies downgrade immediately for invoiced users" do
    org = create :organization, billing_type: "invoice", seats: 20

    assert_no_difference "Billing::PendingPlanChange.count" do
      result = Billing::ChangeSubscription.perform org, seats: 10, actor: org
      assert result.success?
    end

    assert_equal 10, org.reload.seats
  end

  test "delays cancelling a plan" do
    user = create :credit_card_user, plan: GitHub::Plan.pro,
      billed_on: GitHub::Billing.today + 1.month

    assert_difference "Billing::PendingPlanChange.count", 1 do
      result = Billing::ChangeSubscription.perform user, plan: "free", actor: user
      assert result.success?
    end

    change = user.pending_plan_changes.last
    assert_equal GitHub::Plan.free, change.plan
    assert_equal GitHub::Plan.pro, user.reload.plan
    assert_equal user.billed_on, change.active_on
  end

  test "delays cancelling a plan with addons for an org without a payment method" do
    user = create :credit_card_org, plan: GitHub::Plan.business_plus,
      billed_on: GitHub::Billing.today + 1.month
    plan_subscription = create(:billing_plan_subscription, user: user)
    create :billing_subscription_item, plan_subscription: plan_subscription
    user.reload

    user.payment_method.clear_payment_details(user)

    assert_difference "Billing::PendingPlanChange.count", 1 do
      result = Billing::ChangeSubscription.perform user, plan: "free", actor: user
      assert result.success?
    end

    user.reload
    change = user.pending_plan_changes.last
    assert_equal GitHub::Plan.free_with_addons, change.plan
    assert_equal GitHub::Plan.business_plus, user.reload.plan
    assert_equal user.billed_on, change.active_on
  end

  test "delays downgrading a plan" do
    user = create :credit_card_user, plan: GitHub::Plan.pro,
      billed_on: GitHub::Billing.today + 1.month

    assert_difference "Billing::PendingPlanChange.count", 1 do
      result = Billing::ChangeSubscription.perform user, plan: "free", actor: user
      assert result.success?
    end

    change = user.pending_plan_changes.last
    assert_equal GitHub::Plan.free, change.plan
    assert_equal GitHub::Plan.pro, user.reload.plan
    assert_equal user.billed_on, change.active_on
  end

  test "applies upgrading the seat count immeditately" do
    org = create :credit_card_org, plan: GitHub::Plan.business, seats: 20,
      billed_on: GitHub::Billing.today + 1.month

    assert_no_difference "Billing::PendingPlanChange.count" do
      result = Billing::ChangeSubscription.perform org, seats: 30, actor: org
      assert result.success?
    end

    assert_equal 30, org.reload.seats
  end

  test "creates a pending plan change when downgrading plan duration" do
    org = create :credit_card_org, plan: GitHub::Plan.business, seats: 20,
      plan_duration: "year", billed_on: GitHub::Billing.today + 1.month

    assert_difference "Billing::PendingPlanChange.count", 1 do
      result = Billing::ChangeSubscription.perform org, plan_duration: "month", actor: org
      assert result.success?
    end

    change = org.pending_plan_changes.last
    assert_equal "month", change.plan_duration
    assert_equal org.billed_on, change.active_on
    assert_equal "year", org.plan_duration
  end

  test "updates pending plan change when upgrading" do
    org = create :credit_card_org, plan: GitHub::Plan.silver, seats: 20,

      plan_duration: "year", billed_on: GitHub::Billing.today + 1.month

    #downgrade
    Billing::ChangeSubscription.perform org, plan: "bronze", actor: org, seats: 20
    assert_equal GitHub::Plan.bronze, org.reload.pending_cycle_change.plan
    assert_equal GitHub::Plan.silver, org.plan

    #upgrade
    Billing::ChangeSubscription.perform org, plan: "gold", actor: org, seats: 30
    assert_equal GitHub::Plan.gold, org.reload.pending_cycle_change.plan
    assert_equal 30, org.pending_cycle_change.seats
    assert_equal GitHub::Plan.gold, org.plan
    assert_equal 30, org.seats
  end

  test "creates a pending change when changing to yearly billing" do
    org = create :credit_card_org, plan: GitHub::Plan.business, seats: 20,
      plan_duration: "month", billed_on: GitHub::Billing.today + 2.weeks

    assert_difference "Billing::PendingPlanChange.count", 1 do
      result = Billing::ChangeSubscription.perform org, plan_duration: "year", actor: org
      assert result.success?
    end

    change = org.pending_plan_changes.last
    assert_equal "year", change.plan_duration
    assert_equal org.billed_on, change.active_on
    assert_equal "month", org.plan_duration
  end

  test "performs upgrade for non-seat plans" do
    org = create :credit_card_org, plan: GitHub::Plan.silver, seats: 20,
      plan_duration: "year", billed_on: GitHub::Billing.today + 1.month

    #downgrade
    Billing::ChangeSubscription.perform org, plan: "bronze", actor: org
    assert_equal GitHub::Plan.bronze, org.reload.pending_cycle_change.plan
    assert_equal GitHub::Plan.silver, org.plan

    #upgrade
    Billing::ChangeSubscription.perform org, plan: "gold", actor: org
    assert_equal GitHub::Plan.gold, org.reload.pending_cycle_change.plan
    assert_equal GitHub::Plan.gold, org.plan
  end

  test "schedules downgrade for users with 100% off coupon" do
    user = create :credit_card_user, plan: GitHub::Plan.pro,
      billed_on: GitHub::Billing.today + 1.month
    user.redeem_coupon create :coupon, discount: 1

    assert_difference "Billing::PendingPlanChange.count", 1 do
      result = Billing::ChangeSubscription.perform user, plan: "free", actor: user
      assert result.success?
    end

    change = user.pending_plan_changes.last
    assert_equal GitHub::Plan.free, change.plan
    assert_equal GitHub::Plan.pro, user.reload.plan
    assert_equal user.billed_on, change.active_on
  end

  context "can_perform?" do
    test "false for a target user moving to an organization plan even as a site admin" do
      user = create :user
      actor = create :staff_admin_user
      plan = GitHub::Plan.business

      service = Billing::ChangeSubscription.new(user, actor: actor, plan: plan)

      refute service.can_perform?
    end
  end

  context "synchronous payment collection" do
    test "change plan from free to paid with a provided payment method only synchronizes once" do
      GitHub.flipper[:skip_immediate_payment_collection_for_plan_or_seat_changes].disable

      events = subscribe "account.plan_change"
      subscription = create :billing_plan_subscription, :zuora

      create_zuora_subscription(
        zuora_subscription_number: subscription.zuora_subscription_number,
      )

      user = create :credit_card_user, plan: "free", plan_subscription: subscription

      assert_enqueued_jobs(0, only: SynchronizePlanSubscriptionJob) do
        assert_enqueued_jobs(1, only: CollectPaymentForUpgradeJob) do
          result = Billing::ChangeSubscription.perform user, plan: "pro", actor: user,
            payment_details: encrypted_credit_card_params
            .merge(zuora_payment_method_id: zuora_new_payment_method_id)

          assert result.success?
        end
      end

      assert_equal "pro", user.plan.name
      assert user.has_valid_payment_method?

      assert user.zuora_subscription?
      first_billing_date = user.plan_subscription.zuora_subscription.next_billing_date
      assert_equal GitHub::Billing.today, first_billing_date.to_date

      assert event = events.pop
      assert_equal "account.plan_change", event.name
    end

    test "change plan from business with coupon to business_plus only synchronizes once" do
      GitHub.flipper[:skip_immediate_payment_collection_for_plan_or_seat_changes].disable
      org = create(:credit_card_org, plan: "business", seats: 10)
      create(:billing_plan_subscription, :zuora, user: org)
      coupon = create(:coupon, discount: "$10")
      org.redeem_coupon(coupon)

      # Redeeming a coupon causes a synchronization to be scheduled, but we aren't testing that here.
      # Re-instantiate the org to reset @needs_subscription_synchronization to false.
      org = Organization.find(org.id)

      assert_enqueued_jobs(0, only: SynchronizePlanSubscriptionJob) do
        assert_enqueued_jobs(1, only: CollectPaymentForUpgradeJob) do
          result = Billing::ChangeSubscription.perform org, plan: "business_plus", actor: org
          assert result.success?
        end
      end

      assert_equal "business_plus", org.plan.name
    end

    test "does not synchronize when the user has no zuora account and the plan is fully covered by a coupon" do
      GitHub.flipper[:skip_immediate_payment_collection_for_plan_or_seat_changes].disable

      user = create(:user, plan: "free")
      coupon = create(:coupon, discount: "100%")
      user.coupon_redemptions.create(coupon: coupon)

      events = subscribe "account.plan_change"

      assert_enqueued_jobs(0, only: SynchronizePlanSubscriptionJob) do
        assert_enqueued_jobs(0, only: CollectPaymentForUpgradeJob) do
          result = Billing::ChangeSubscription.perform user, plan: "pro", actor: user
          assert result.success?
        end
      end

      assert_equal "pro", user.plan.name

      assert event = events.pop
      assert_equal "account.plan_change", event.name
    end

    test "does not collect payment synchronously when plan is fully covered by a coupon" do
      GitHub.flipper[:skip_immediate_payment_collection_for_plan_or_seat_changes].disable

      org = create(:credit_card_org, plan: "free")
      create(:billing_plan_subscription, :zuora)
      coupon = create(:coupon, discount: "$100")
      org.coupon_redemptions.create(coupon: coupon)

      events = subscribe "account.plan_change"

      assert_enqueued_jobs(1, only: SynchronizePlanSubscriptionJob) do
        assert_enqueued_jobs(0, only: CollectPaymentForUpgradeJob) do
          result = Billing::ChangeSubscription.perform org, plan: "business", seats: 1, actor: org.admin
          assert result.success?
        end
      end

      assert_equal "business", org.plan.name
      assert_equal 1, org.seats

      assert event = events.pop
      assert_equal "account.plan_change", event.name
    end

    test "does not collect payment synchronously for users if the customer requires a manual transaction (e.g. India RBI)" do
      GitHub.flipper[:skip_immediate_payment_collection_for_plan_or_seat_changes].disable

      user = create(:india_based_credit_card_user, plan: "free")

      events = subscribe "account.plan_change"

      assert_enqueued_jobs(1, only: SynchronizePlanSubscriptionJob) do
        assert_enqueued_jobs(0, only: CollectPaymentForUpgradeJob) do
          result = Billing::ChangeSubscription.perform user, plan: "pro", actor: user
          assert result.success?
        end
      end

      assert_equal "pro", user.plan.name

      assert event = events.pop
      assert_equal "account.plan_change", event.name
    end

    test "does not collect payment synchronously for orgs if the customer requires a manual transaction (e.g. India RBI)" do
      GitHub.flipper[:skip_immediate_payment_collection_for_plan_or_seat_changes].disable

      org = create(:india_based_credit_card_organization, plan: "business")
      org.add_admin(user = create(:user))

      events = subscribe "account.plan_change"

      assert_enqueued_jobs(1, only: SynchronizePlanSubscriptionJob) do
        assert_enqueued_jobs(0, only: CollectPaymentForUpgradeJob) do
          result = Billing::ChangeSubscription.perform org, plan: "business_plus", actor: user
          assert result.success?
        end
      end

      assert_equal "business_plus", org.plan.name

      assert event = events.pop
      assert_equal "account.plan_change", event.name
    end

    test "does not collect payment synchronously for orgs that are invoiced" do
      GitHub.flipper[:skip_immediate_payment_collection_for_plan_or_seat_changes].disable

      subscription = create(:billing_plan_subscription, :zuora)
      org = create(:invoiced_organization, plan: "business", plan_subscription: subscription)
      staff = create(:staff_admin_user)

      events = subscribe "account.plan_change"

      assert_enqueued_jobs(1, only: SynchronizePlanSubscriptionJob) do
        assert_enqueued_jobs(0, only: CollectPaymentForUpgradeJob) do
          result = Billing::ChangeSubscription.perform org, plan: "business_plus", actor: staff
          assert result.success?
        end
      end

      assert_equal "business_plus", org.plan.name

      assert event = events.pop
      assert_equal "account.plan_change", event.name
    end
  end
end
