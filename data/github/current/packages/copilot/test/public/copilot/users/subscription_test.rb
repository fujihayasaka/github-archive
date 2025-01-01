# typed: true
# frozen_string_literal: true

require "test_helper"

class CopilotSubscriptionTest < GitHub::TestCase
  include GitHub::LoggerHelper
  include CopilotTestHelper # automatically disables Copilot feature flags
  fixtures do
    @user = create(:user)
    @org = create(:organization)
    @org.add_member(@user)

    @public_repo = create(:public_repository, name: "public-repo-1", created_at: 2.months.ago, pushed_at: 2.years.ago, owner: @user)
    @other_public_repo = create(:public_repository, name: "public-repo-2", created_at: 2.months.ago, pushed_at: 2.years.ago, owner: @user)

    @educational_coupon = create(:coupon, code: "students-2022")
    @non_educational_coupon = create(:coupon, group: "internal")

    @copilot_monthly_product_uuid = create(:billing_product_uuid, :copilot, :monthly)
    @copilot_yearly_product_uuid = create(:billing_product_uuid, :copilot, :yearly)

    @copilot_monthly_product_identifier = Billing::Public::Product::ProductIdentifier.new(product_type: "github.copilot", product_key: "v0", billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month).freeze
    @copilot_yearly_product_identifier = Billing::Public::Product::ProductIdentifier.new(product_type: "github.copilot", product_key: "v0", billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Year).freeze

    @plan_subscription = create(:billing_plan_subscription, :zuora)
    @plan_user = @plan_subscription.user

    GitHub.flipper[:marketing_forms_api_integration_copilot_trial].disable
  end

  context "subscription_type" do
    test "default returns UNKNOWN string" do
      user = create(:user)

      copilot_user = Copilot::User.new(user)
      assert_equal :UNKNOWN, copilot_user.subscription_type
    end

    test "technical preview user after grace period" do
      Copilot::User.any_instance.stubs(:is_technical_preview_user?).returns(true)
      assert_equal :UNKNOWN, Copilot::User.new(@user).subscription_type
    end

    test "returns trial 30 monthly for copilot user" do
      copilot_monthly_product_uuid = create(:billing_product_uuid, :copilot, billing_cycle: :month)

      plan_subscription = create(:billing_plan_subscription, :zuora)
      user = plan_subscription.user

      create(:billing_subscription_item, :paid,
        plan_subscription: plan_subscription,
        subscribable: copilot_monthly_product_uuid,
        free_trial_ends_on: 30.days.from_now
      )

      copilot_user = Copilot::User.new(user)
      assert_equal :TRIAL_30_MONTHLY_SUBSCRIBER, copilot_user.subscription_type
    end

    test "returns trial yearly for copilot user" do
      copilot_yearly_product_uuid = create(:billing_product_uuid, :copilot, billing_cycle: :year)

      plan_subscription = create(:billing_plan_subscription, :zuora)
      user = plan_subscription.user

      create(:billing_subscription_item, :paid,
        plan_subscription: plan_subscription,
        subscribable: copilot_yearly_product_uuid,
        free_trial_ends_on: 10.days.from_now
      )

      copilot_user = Copilot::User.new(user)
      assert_equal :TRIAL_30_YEARLY_SUBSCRIBER, copilot_user.subscription_type
    end

    test "returns monthly for copilot user with other productUUID stuff" do
      marketplace_product_uuid = create(:billing_product_uuid, :marketplace_listing_plan)

      plan_subscription = create(:billing_plan_subscription, :zuora)
      user = plan_subscription.user

      create(:billing_subscription_item, :paid, plan_subscription: plan_subscription,  subscribable: marketplace_product_uuid, quantity: 1)

      copilot_monthly_product_uuid = create(:billing_product_uuid, :copilot, billing_cycle: :month)

      create(:billing_subscription_item, :paid, plan_subscription: plan_subscription, subscribable: copilot_monthly_product_uuid)
      copilot_user = Copilot::User.new(user)
      assert_equal :MONTHLY_SUBSCRIBER, copilot_user.subscription_type
    end

    test "returns monthly for copilot user" do
      copilot_monthly_product_uuid = create(:billing_product_uuid, :copilot, billing_cycle: :month)

      plan_subscription = create(:billing_plan_subscription, :zuora)
      user = plan_subscription.user

      create(:billing_subscription_item, :paid, plan_subscription: plan_subscription, subscribable: copilot_monthly_product_uuid)
      copilot_user = Copilot::User.new(user)
      assert_equal :MONTHLY_SUBSCRIBER, copilot_user.subscription_type
    end

    test "returns yearly for copilot user" do
      copilot_yearly_product_uuid = create(:billing_product_uuid, :copilot, billing_cycle: :year)

      plan_subscription = create(:billing_plan_subscription, :zuora)
      user = plan_subscription.user

      create(:billing_subscription_item, :paid, plan_subscription: plan_subscription, subscribable: copilot_yearly_product_uuid)

      copilot_user = Copilot::User.new(user)
      assert_equal :YEARLY_SUBSCRIBER, copilot_user.subscription_type
    end
  end

  context "#has_signed_up?" do
    test "returns true if it has an active monthly subscription" do
      create(:billing_subscription_item, :paid,
             plan_subscription: @plan_subscription,
             subscribable: @copilot_monthly_product_uuid
            )
      assert Copilot::User.new(@plan_user).has_signed_up?
    end

    test "returns true if it has an active yearly subscription" do
      create(:billing_subscription_item, :paid,
             plan_subscription: @plan_subscription,
             subscribable: @copilot_yearly_product_uuid
            )
      assert Copilot::User.new(@plan_user).has_signed_up?
    end

    test "returns true if it has an active monthly trial subscription" do
      create(:billing_subscription_item, :paid,
             plan_subscription: @plan_subscription,
             subscribable: @copilot_monthly_product_uuid,
             free_trial_ends_on: 10.days.from_now
            )
      assert Copilot::User.new(@plan_user).has_signed_up?
    end

    test "returns true if it has an active yearly trial subscription" do
      create(:billing_subscription_item, :paid,
             plan_subscription: @plan_subscription,
             subscribable: @copilot_yearly_product_uuid,
             free_trial_ends_on: 10.days.from_now
            )
      assert Copilot::User.new(@plan_user).has_signed_up?
    end

    test "returns true if free user is already subscribed" do
      user = create(:user)
      create(:copilot_free_user, user: user, subscribed: true, subscribed_at: Time.now)
      copilot_user = Copilot::User.new(user)
      Copilot::User.any_instance.stubs(:has_active_subscription?).returns(false)
      Copilot::User.any_instance.stubs(:has_trial_subscription?).returns(false)

      assert copilot_user.has_signed_up?
    end

    test "returns false if free user is not already subscribed" do
      user = create(:user)
      create(:copilot_free_user, user: user, subscribed: false)
      copilot_user = Copilot::User.new(user)
      Copilot::User.any_instance.stubs(:has_active_subscription?).returns(false)
      Copilot::User.any_instance.stubs(:has_trial_subscription?).returns(false)

      refute copilot_user.has_signed_up?
    end
  end

  context "#can_view_copilot_settings?" do
    test "returns true if it has an active subscription" do
      create(:billing_subscription_item, :paid,
             plan_subscription: @plan_subscription,
             subscribable: @copilot_monthly_product_uuid
            )
      assert Copilot::User.new(@plan_user).can_view_copilot_settings?
    end

    test "returns true if it has an active trial subscription" do
      create(:billing_subscription_item, :paid,
             plan_subscription: @plan_subscription,
             subscribable: @copilot_monthly_product_uuid,
             free_trial_ends_on: 10.days.from_now
            )
      assert Copilot::User.new(@plan_user).can_view_copilot_settings?
    end

    test "returns true if the user is assigned a seat" do
      create(:copilot_seat, organization: @org, assigned_user: @user)
      assert Copilot::User.new(@user).can_view_copilot_settings?
    end

    test "returns true if the user is part of a non-converted seat assignment" do
      create(:copilot_seat_assignment, :user, assignable: @user, organization: @org)
      assert Copilot::User.new(@user).can_view_copilot_settings?
    end

    test "returns false if free user is not already subscribed" do
      user = create(:user)
      create(:copilot_free_user, user: user, subscribed: false)
      copilot_user = Copilot::User.new(user)
      Copilot::User.any_instance.stubs(:has_active_subscription?).returns(false)
      Copilot::User.any_instance.stubs(:has_trial_subscription?).returns(false)

      refute copilot_user.can_view_copilot_settings?
    end
  end

  context "#can_modify_copilot_settings?" do
    test "returns true if it has an active subscription" do
      create(:billing_subscription_item, :paid,
             plan_subscription: @plan_subscription,
             subscribable: @copilot_monthly_product_uuid
            )
      assert Copilot::User.new(@plan_user).can_modify_copilot_settings?
    end

    test "returns true if it has an active trial subscription" do
      create(:billing_subscription_item, :paid,
             plan_subscription: @plan_subscription,
             subscribable: @copilot_monthly_product_uuid,
             free_trial_ends_on: 10.days.from_now
            )
      assert Copilot::User.new(@plan_user).can_modify_copilot_settings?
    end

    test "returns false if the user is assigned a seat" do
      create(:copilot_seat, organization: @org, assigned_user: @user)
      refute Copilot::User.new(@user).can_modify_copilot_settings?
    end

    test "returns false if free user is not already subscribed" do
      user = create(:user)
      create(:copilot_free_user, user: user, subscribed: false)
      copilot_user = Copilot::User.new(user)
      Copilot::User.any_instance.stubs(:has_active_subscription?).returns(false)
      Copilot::User.any_instance.stubs(:has_trial_subscription?).returns(false)

      refute copilot_user.can_modify_copilot_settings?
    end
  end

  context "can_signup_for_free?" do
    test "returns false if it has an active monthly subscription" do
      create(:billing_subscription_item, :paid,
             plan_subscription: @plan_subscription,
             subscribable: @copilot_monthly_product_uuid
            )
      refute Copilot::User.new(@plan_user).can_signup_for_free?
    end

    test "returns false if it has an active yearly subscription" do
      create(:billing_subscription_item, :paid,
             plan_subscription: @plan_subscription,
             subscribable: @copilot_yearly_product_uuid
            )
      refute Copilot::User.new(@plan_user).can_signup_for_free?
    end

    test "returns false if it has an active monthly trial subscription" do
      create(:billing_subscription_item, :paid,
             plan_subscription: @plan_subscription,
             subscribable: @copilot_monthly_product_uuid,
             free_trial_ends_on: 10.days.from_now
            )
      refute Copilot::User.new(@plan_user).can_signup_for_free?
    end

    test "returns false if it has an active yearly trial subscription" do
      create(:billing_subscription_item, :paid,
             plan_subscription: @plan_subscription,
             subscribable: @copilot_yearly_product_uuid,
             free_trial_ends_on: 10.days.from_now
            )
      refute Copilot::User.new(@plan_user).can_signup_for_free?
    end

    test "returns false if free user is already subscribed" do
      user = create(:user)
      create(:copilot_free_user, user: user, subscribed: true, subscribed_at: Time.now)
      copilot_user = Copilot::User.new(user)
      Copilot::User.any_instance.stubs(:has_active_subscription?).returns(false)
      Copilot::User.any_instance.stubs(:has_trial_subscription?).returns(false)

      refute copilot_user.can_signup_for_free?
    end

    test "returns true if free user is not already subscribed" do
      user = create(:user)
      free_user = create(:copilot_free_user, user: user, subscribed: false)
      copilot_user = Copilot::User.new(user)

      # these are the explicit checks that are being tested
      # ci has been failing so i want to know where it's failing
      refute copilot_user.has_active_subscription?, "User should not have an active subscription"
      refute copilot_user.has_trial_subscription?, "User should not have a trial subscription"
      assert free_user.present?, "Free User should already be present"
      refute free_user.subscribed?, "Free user should not be subscribed"

      Copilot::User.any_instance.stubs(:has_active_subscription?).returns(false)
      Copilot::User.any_instance.stubs(:has_trial_subscription?).returns(false)

      assert copilot_user.can_signup_for_free?
    end
  end

  context "has_subscription_ended?" do
    test "returns false if user has never had a subscription" do
      refute Copilot::User.new(@plan_user).has_subscription_ended?
    end

    test "returns false if user has an active subscription" do
      create(:billing_subscription_item, :paid,
             plan_subscription: @plan_subscription,
             subscribable: @copilot_monthly_product_uuid
            )
      assert Copilot::User.new(@plan_user).has_active_subscription?
      refute Copilot::User.new(@plan_user).has_subscription_ended?
    end

    test "returns false if user has a trial subscription" do
      create(:billing_subscription_item, :paid,
             plan_subscription: @plan_subscription,
             subscribable: @copilot_monthly_product_uuid,
             free_trial_ends_on: 10.days.from_now
            )

      assert Copilot::User.new(@plan_user).has_trial_subscription?
      refute Copilot::User.new(@plan_user).has_subscription_ended?
    end

    test "returns true if the user has a cancelled subscription" do
      create(:billing_subscription_item, :paid,
             plan_subscription: @plan_subscription,
             subscribable: @copilot_monthly_product_uuid,
             free_trial_ends_on: 10.days.ago,
             quantity: 0
            )
      assert Copilot::User.new(@plan_user).has_subscription_ended?
    end

    test "returns true even if the user has a non-Copilot active subscription" do
      create(:billing_subscription_item, :paid,
             plan_subscription: @plan_subscription,
             subscribable: @copilot_monthly_product_uuid,
             free_trial_ends_on: 10.days.ago,
             quantity: 0
            )


      listing_plan = create(:marketplace_listing_plan, :verified_listing)
      create(:billing_subscription_item, plan_subscription: @plan_subscription,
        subscribable: listing_plan, quantity: 1)

      assert Copilot::User.new(@plan_user).has_subscription_ended?
    end
  end

  context "eligible_for_trial?" do
    test "returns false if the user has already had a free trial" do
      create(:billing_subscription_item, :paid,
             plan_subscription: @plan_subscription,
             subscribable: @copilot_monthly_product_uuid,
             free_trial_ends_on: 10.days.ago,
             quantity: 0,
             created_at: 20.days.ago
            )
      copilot_plan_user = Copilot::User.new(@plan_user)
      assert copilot_plan_user.has_subscription_ended?
      refute copilot_plan_user.eligible_for_trial?
    end

    test "returns true if the user only had <2 days worth of a free trial" do
      GitHub::flipper[:copilot_allow_trial_resumption].enable

      subscription = create(:billing_subscription_item, :paid,
             plan_subscription: @plan_subscription,
             subscribable: @copilot_monthly_product_uuid,
             free_trial_ends_on: 10.days.ago,
             quantity: 0
            )
      subscription.update_attribute(:created_at, 10.days.ago)
      copilot_plan_user = Copilot::User.new(@plan_user)
      assert copilot_plan_user.has_subscription_ended?
      assert copilot_plan_user.eligible_for_trial?
    end

    test "returns true if the free trial date is somehow set for the future" do
      GitHub::flipper[:copilot_allow_trial_resumption].enable

      create(:billing_subscription_item, :paid,
        plan_subscription: @plan_subscription,
        subscribable: @copilot_monthly_product_uuid,
        free_trial_ends_on: 10.days.from_now,
        quantity: 0
      )
      copilot_plan_user = Copilot::User.new(@plan_user)
      assert copilot_plan_user.has_subscription_ended?
      assert copilot_plan_user.eligible_for_trial?
    end

    test "returns true if user is eligible for free trial" do
      user = create(:user)
      create(:copilot_free_user, user: user, subscribed: false)
      copilot_user = Copilot::User.new(user)
      Copilot::User.any_instance.stubs(:has_active_subscription?).returns(false)
      Copilot::User.any_instance.stubs(:has_trial_subscription?).returns(false)

      refute copilot_user.has_signed_up?
      assert copilot_user.eligible_for_trial?
    end

    test "returns false if user is disabled" do
      user = create(:user)
      create(:copilot_free_user, user: user, subscribed: false)
      copilot_user = Copilot::User.new(user)

      user.disable!

      Copilot::User.any_instance.stubs(:has_active_subscription?).returns(false)
      Copilot::User.any_instance.stubs(:has_trial_subscription?).returns(false)

      refute copilot_user.has_signed_up?
      refute copilot_user.eligible_for_trial?
    end

    test "returns false if user is in dunning" do
      user = create(:user)
      create(:copilot_free_user, user: user, subscribed: false)
      copilot_user = Copilot::User.new(user)

      user.increment_billing_attempts

      Copilot::User.any_instance.stubs(:has_active_subscription?).returns(false)
      Copilot::User.any_instance.stubs(:has_trial_subscription?).returns(false)

      refute copilot_user.has_signed_up?
      refute copilot_user.eligible_for_trial?
    end

    test "returns false if user is eligible for free trial if subscribed" do
      user = create(:user)
      create(:copilot_free_user, user: user, subscribed: false)
      copilot_user = Copilot::User.new(user)
      Copilot::User.any_instance.stubs(:has_active_subscription?).returns(true)
      Copilot::User.any_instance.stubs(:has_trial_subscription?).returns(false)

      assert copilot_user.has_signed_up?
      refute copilot_user.eligible_for_trial?
    end
  end

  context "had_personal_subscription?" do
    test "returns true if user has an active subscription" do
      create(:billing_subscription_item, :paid,
             plan_subscription: @plan_subscription,
             subscribable: @copilot_monthly_product_uuid
            )
      assert Copilot::User.new(@plan_user).has_active_subscription?
      assert Copilot::User.new(@plan_user).had_personal_subscription?
    end

    test "returns true if user has a trial subscription" do
      create(:billing_subscription_item, :paid,
             plan_subscription: @plan_subscription,
             subscribable: @copilot_monthly_product_uuid,
             free_trial_ends_on: 10.days.from_now
            )

      assert Copilot::User.new(@plan_user).has_trial_subscription?
      assert Copilot::User.new(@plan_user).had_personal_subscription?
    end

    test "returns true if the user has a cancelled subscription" do
      create(:billing_subscription_item, :paid,
             plan_subscription: @plan_subscription,
             subscribable: @copilot_monthly_product_uuid,
             free_trial_ends_on: 10.days.ago,
             quantity: 0
            )
      assert Copilot::User.new(@plan_user).had_personal_subscription?
    end
  end

  context "has_active_subscription?" do
    test "has_active_monthly_subscription? returns true" do
      create(:billing_subscription_item, :paid, plan_subscription: @plan_subscription, subscribable: @copilot_monthly_product_uuid)

      assert Copilot::User.new(@plan_user).has_active_subscription?
    end

    test "has_active_yearly_subscription? returns true" do
      create(:billing_subscription_item, :paid, plan_subscription: @plan_subscription, subscribable: @copilot_yearly_product_uuid)

      assert Copilot::User.new(@plan_user).has_active_subscription?
    end
  end

  context "has_active_monthly_subscription?" do
    test "returns false if it has no subscriptionitem" do
      refute Copilot::User.new(@user).has_active_monthly_subscription?
    end

    test "returns false if the monthly subscription has a trial" do
      Billing::Public::SubscriptionItem.create(
        product: @copilot_monthly_product_identifier,
        account: @plan_user,
        actor: @plan_user,
        free_trial_length: 10.days
      )

      refute Copilot::User.new(@plan_user).has_active_monthly_subscription?
    end

    test "returns true if the monthly subscription does not have a trial" do
      Billing::Public::SubscriptionItem.create(
        product: @copilot_monthly_product_identifier,
        account: @plan_user,
        actor: @plan_user,
        free_trial_length: 0.days
      )

      assert Copilot::User.new(@plan_user).has_active_monthly_subscription?
    end
  end

  context "has_active_yearly_subscription?" do
    test "returns false if it has no subscriptionitem" do
      refute Copilot::User.new(@plan_user).has_active_yearly_subscription?
    end

    test "returns false if the yearly subscription has a trial" do
      Billing::Public::SubscriptionItem.create(
        product: @copilot_yearly_product_identifier,
        account: @plan_user,
        actor: @plan_user,
        free_trial_length: 10.days
      )

      refute Copilot::User.new(@plan_user).has_active_yearly_subscription?
    end

    test "returns true if the yearly subscription does not have a trial" do
      Billing::Public::SubscriptionItem.create(
        product: @copilot_yearly_product_identifier,
        account: @plan_user,
        actor: @plan_user,
        free_trial_length: 0.days
      )

      assert Copilot::User.new(@plan_user).has_active_yearly_subscription?
    end
  end

  context "has_trial_subscription?" do
    test "returns false if it has an active yearly non-trial subscription" do
      Billing::Public::SubscriptionItem.create(
        product: @copilot_yearly_product_identifier,
        account: @plan_user,
        actor: @plan_user,
        free_trial_length: 0.days
      )

      refute Copilot::User.new(@plan_user).has_trial_subscription?
    end

    test "returns false if it has an active monthly non-trial subscription" do
      Billing::Public::SubscriptionItem.create(
        product: @copilot_monthly_product_identifier,
        account: @plan_user,
        actor: @plan_user,
        free_trial_length: 0.days
      )

      refute Copilot::User.new(@plan_user).has_trial_subscription?
    end

    test "returns true if it has an active yearly trial subscription" do
      Billing::Public::SubscriptionItem.create(
        product: @copilot_yearly_product_identifier,
        account: @plan_user,
        actor: @plan_user,
        free_trial_length: 10.days
      )

      assert Copilot::User.new(@plan_user).has_trial_subscription?
    end

    test "returns true if it has an active monthly trial subscription" do
      Billing::Public::SubscriptionItem.create(
        product: @copilot_monthly_product_identifier,
        account: @plan_user,
        actor: @plan_user,
        free_trial_length: 10.days
      )

      assert Copilot::User.new(@plan_user).has_trial_subscription?
    end

  end

  context "subscribe_free_user" do
    test "returns error if can_signup_for_free is false" do
      Copilot::User.any_instance.stubs(:can_signup_for_free?).returns(false)
      result = Copilot::User.new(@user).subscribe_free_user
      refute result.ok?
    end

    test "returns error if free user is already subscribed" do
      free_user = create(:copilot_free_user, user: @user, subscribed: true)
      copilot_user = Copilot::User.new(@user)

      # these are the explicit checks that are being tested
      # ci has been failing so i want to know where it's failing
      refute copilot_user.has_active_subscription?
      refute copilot_user.has_trial_subscription?
      assert free_user.present?
      assert free_user.subscribed?

      result = copilot_user.subscribe_free_user
      refute result.ok?
    end

    test "returns error if free user can't be updated" do
      create(:copilot_free_user, user: @user)
      Copilot::FreeUser.any_instance.stubs(:subscribe).raises(ActiveRecord::RecordInvalid)
      result = Copilot::User.new(@user).subscribe_free_user
      refute result.ok?
    end

    test "returns success if free user doesn't exist but user has coupon" do
      @user.redeem_coupon(@educational_coupon)
      copilot_user = Copilot::User.new(@user)

      result = copilot_user.subscribe_free_user
      assert result.ok?

      free_user = T.must(Copilot::FreeUser.find_for_copilot_user(copilot_user))
      assert free_user.subscribed?
      refute_nil free_user.subscribed_at
      assert_equal free_user.free_user_type, "Educational"
    end

    test "returns success if free user doesn't exist but user has engaged repo" do
      create(:copilot_engaged_oss_user, user: @user)
      copilot_user = Copilot::User.new(@user)
      assert copilot_user.can_signup_for_free?, "User should be able to sign up for free"
      refute copilot_user.has_active_subscription?, "User has active subscription and they shouldn't"
      refute copilot_user.has_trial_subscription?, "User has trial subscription and they shouldn't"

      result = copilot_user.subscribe_free_user
      assert result.ok?, result.error

      free_user = T.must(Copilot::FreeUser.find_for_copilot_user(copilot_user))
      assert free_user.subscribed?, "Free user should be subscribed"
      refute_nil free_user.subscribed_at
      assert_equal free_user.free_user_type, "EngagedOSS"
    end
  end

  context "subscribe" do
    test "returns error if free user" do
      Copilot::User.any_instance.stubs(:can_signup_for_free?).returns(true)
      create(:copilot_free_user, user: @user)
      copilot_user = Copilot::User.new(@user)
      result = copilot_user.subscribe(:month)
      refute result.ok?
      refute copilot_user.has_active_monthly_subscription?
    end

    test "returns error if call to create fails" do
      Copilot::User.any_instance.stubs(:can_signup_for_free?).returns(false)

      copilot_user = Copilot::User.new(@user)
      # this user does not have a plan subscription thing
      result = copilot_user.subscribe(:month)
      refute result.ok?
      refute copilot_user.has_active_monthly_subscription?
    end

    test "returns success if call to create works" do
      Copilot::User.any_instance.stubs(:can_signup_for_free?).returns(false)
      copilot_plan_user = Copilot::User.new(@plan_user)
      result = copilot_plan_user.subscribe(:month)
      assert result.ok?
      assert copilot_plan_user.has_trial_subscription?
      refute copilot_plan_user.has_active_monthly_subscription?
    end

    test "extends the trial if the user only had <2 days worth of a free trial" do
      GitHub::flipper[:copilot_allow_trial_resumption].enable

      subscription = create(:billing_subscription_item, :paid,
             plan_subscription: @plan_subscription,
             subscribable: @copilot_monthly_product_uuid,
             free_trial_ends_on: 10.days.ago,
             quantity: 0
            )
      subscription.update_attribute(:created_at, 10.days.ago)
      copilot_plan_user = Copilot::User.new(@plan_user)
      assert copilot_plan_user.has_subscription_ended?

      result = copilot_plan_user.subscribe(:month)
      assert result.ok?
      assert copilot_plan_user.has_trial_subscription?
      refute copilot_plan_user.has_active_monthly_subscription?
    end

    test "does not extend the trial if the user had >2 days worth of a free trial" do
      GitHub::flipper[:copilot_allow_trial_resumption].enable

      subscription = create(:billing_subscription_item, :paid,
             plan_subscription: @plan_subscription,
             subscribable: @copilot_monthly_product_uuid,
             free_trial_ends_on: 5.days.ago,
             quantity: 0
            )
      subscription.update_attribute(:created_at, 10.days.ago)
      copilot_plan_user = Copilot::User.new(@plan_user)
      assert copilot_plan_user.has_subscription_ended?

      result = copilot_plan_user.subscribe(:month)
      assert result.ok?
      refute copilot_plan_user.has_trial_subscription?
      assert copilot_plan_user.has_active_monthly_subscription?
    end

    test "triggers a SendEmailToEloquaJob when subscribing new users with a free trial " do
      Copilot::User.any_instance.stubs(:can_signup_for_free?).returns(false)
      post_request = stub_request(:post, Copilot::Users::Subscription::FREE_TRIAL_ELOQUA_URI)

      copilot_plan_user = Copilot::User.new(@plan_user)
      result = perform_enqueued_jobs only: ::Billing::SendEmailToEloquaJob do
        copilot_plan_user.subscribe(:month)
      end

      assert_performed_jobs 1
      assert_requested post_request
      assert result.ok?
      assert copilot_plan_user.has_trial_subscription?
      refute copilot_plan_user.has_active_monthly_subscription?
    end
  end

  context "#subscribe with in-app purchase" do
    test "resubscription for an in-app purchase does not use the reactivation flow" do
      # Do not worry about how trial eligibility is determined, we just want this to be true for this test.
      Copilot::User.any_instance.stubs(:eligible_for_trial?).returns(true)

      # Stub with a cancelled CfI subscription item that was previously purchased via IAP
      subscription_item = create(
        :billing_subscription_item,
        :iap,
        :cancelled,
        subscribable: @copilot_monthly_product_uuid,
        plan_subscription: @plan_subscription
      )

      copilot_user = Copilot::User.new(@plan_user)

      # Double check staged data
      assert subscription_item.cancelled?
      assert copilot_user.has_subscription_ended?
      assert copilot_user.eligible_for_trial?

      in_app_purchase = Billing::Public::InAppPurchase.apple(original_transaction_id: "mona-always-buys-in-app")

      # We want to ensure we do not call this for in-app purchased subscriptions
      ::Billing::Public::SubscriptionItem.expects(:reactivate).never

      # Now try to resubscribe
      result = copilot_user.subscribe(:month, in_app_purchase:)

      assert result.ok?

      # Ensure the subscription item is now re-activated and marked as an in-app purchase
      assert subscription_item.reload.active?
      assert subscription_item.reload.in_app_purchase?
    end

    test "creates billing subscription item identified as in-app purchased" do
      copilot_plan_user = Copilot::User.new(@plan_user)
      in_app_purchase = Billing::Public::InAppPurchase.apple(original_transaction_id: "mona-always-buys-in-app")

      copilot_plan_user.subscribe(:month, in_app_purchase:)

      product = copilot_plan_user.product_identifier
      actual_subscription_item = ::Billing::Public::SubscriptionItem.all_active(product:, account: @plan_user)
        .value { [] }
        .first

      assert actual_subscription_item.in_app_purchase?
    end

    test "sets free trial length to 0 days" do
      copilot_plan_user = Copilot::User.new(@plan_user)
      in_app_purchase = Billing::Public::InAppPurchase.apple(original_transaction_id: "mona-always-buys-in-app")

      # Ensure the user is eligible for a free trial period so we can test it is overridden properly.
      refute_equal 0.days, copilot_plan_user.available_trial_length

      copilot_plan_user.subscribe(:month, in_app_purchase:)

      product = copilot_plan_user.product_identifier
      actual_subscription_item = ::Billing::Public::SubscriptionItem.all_active(product:, account: @plan_user)
        .value { [] }
        .first

      assert_equal 0.days, actual_subscription_item.free_trial_length
    end

    test "prevents year durations" do
      copilot_plan_user = Copilot::User.new(@plan_user)
      in_app_purchase = Billing::Public::InAppPurchase.apple(original_transaction_id: "mona-always-buys-in-app")
      result = copilot_plan_user.subscribe(:year, in_app_purchase:)
      expected_error = Copilot::Errors::SignupError.new("Only monthly plans are currently supported for in-app purchasing.")

      refute result.ok?
      assert_equal expected_error, result.error
    end
  end

  context "#assigned_date" do
    test "returns date of earliest copilot seat for CfB user" do
      freeze_time do
        cfb_user = create(:user)
        cfb_org = create(:copilot_for_business_enabled_organization)
        cfb_org_2 = create(:copilot_for_business_enabled_organization)

        cfb_org.add_member(cfb_user)
        cfb_org_2.add_member(cfb_user)

        earlier_copilot_seat = create(:copilot_seat, organization: cfb_org, assigned_user: cfb_user)
        create(:copilot_seat, organization: cfb_org_2, assigned_user: cfb_user, created_at: 2.days.from_now)

        copilot_user = Copilot::User.new(cfb_user)
        assert_equal earlier_copilot_seat.created_at.iso8601, copilot_user.assigned_date
      end
    end

    test "returns date of free user creation for CfI free user" do
      free_user = create(:copilot_free_user, :y_combinator, user: @user, subscribed: true)

      copilot_user = Copilot::User.new(@user)
      assert_equal free_user.created_at.iso8601, copilot_user.assigned_date
    end

    test "returns date of subscription item creation for CfI paying subscriber" do
      subscription_item = create(:billing_subscription_item, :paid,
        plan_subscription: @plan_subscription,
        subscribable: @copilot_monthly_product_uuid,
      )

      copilot_user = Copilot::User.new(@user)
      assert subscription_item.created_at.iso8601, copilot_user.assigned_date
    end
  end

  context "cancel_and_refund_active_subscription" do
    test "does nothing when nothing to do" do
      copilot_user = Copilot::User.new(@user)
      logs = capture_logs do
        result = copilot_user.cancel_and_refund_active_subscription
        assert result.ok?
      end
      assert_match "Subscription Item Does Not Exist", logs
    end

    test "does not cancels and refunds the subscription with no seat" do
      Billing::Public::SubscriptionItem.create(
        product: @copilot_monthly_product_identifier,
        account: @plan_user,
        actor: @plan_user,
        free_trial_length: 0.days
      )

      Failbot.expects(:report).once
      copilot_user = Copilot::User.new(@plan_user)
      logs = capture_logs do
        result = copilot_user.cancel_and_refund_active_subscription(
          organization: @organization,
        )
        refute result.ok?
      end

      assert_match "No seat found for cancel and refund", logs
    end

    test "cancels and refunds the subscription with seat" do
      subscription_item = Billing::Public::SubscriptionItem.create(
        product: @copilot_monthly_product_identifier,
        account: @plan_user,
        actor: @plan_user,
        free_trial_length: 0.days
      ).value!

      organization = create(:copilot_for_business_enabled_organization)
      organization.add_member(@plan_user)

      seat = create(:copilot_seat, assigned_user: @plan_user, organization: organization)
      Failbot.expects(:report).never

      Copilot::Instrumenter.expects(:instrument_copilot_for_business_individual_seat_converted) do |user, item, user_seat|
        assert_equal @plan_user.id, user.id
        assert_equal subscription_item.id, item.id
        assert_equal seat.id, user_seat.id
      end

      copilot_user = Copilot::User.new(@plan_user)
      logs = capture_logs do
        result = copilot_user.cancel_and_refund_active_subscription(
          organization: organization,
        )
        assert result.ok?
      end

      assert_match "Cancelling and refunding", logs
    end

    test "cancels and refunds in-app purchased subscription with seat" do
      subscription_item = create(
        :billing_subscription_item,
        :iap,
        plan_subscription: @plan_subscription,
        subscribable: @copilot_monthly_product_uuid,
        quantity: 1
      )

      organization = create(:copilot_for_business_enabled_organization)
      organization.add_member(@plan_user)

      create(:copilot_seat, assigned_user: @plan_user, organization: organization)

      copilot_user = Copilot::User.new(@plan_user)

      copilot_user.cancel_and_refund_active_subscription(
        organization: organization,
      )

      perform_enqueued_jobs(only: [Billing::CancelAndRefundSubscriptionItemJob])

      # Assert the original in-app purchased subscription item is now cancelled
      assert subscription_item.reload.cancelled?

      # Copilot should now recognize no active subscription.
      refute Copilot::User.new(@plan_user).copilot_active_subscription_item
    end

    test "logs a message when a seat exists but can't be cancelled" do
      Billing::Public::SubscriptionItem.create(
        product: @copilot_monthly_product_identifier,
        account: @plan_user,
        actor: @plan_user,
        free_trial_length: 0.days
      ).value!

      organization = create(:copilot_for_business_enabled_organization)
      organization.add_member(@plan_user)

      create(:copilot_seat, assigned_user: @plan_user, organization: organization)
      copilot_user = Copilot::User.new(@plan_user)
      # call this first to cache the results. We want to stub GitHub::Result below
      # but this method also creates an instance of a Result
      copilot_user.copilot_active_subscription_item

      logs = capture_logs do
        GitHub::Result.any_instance.stubs(:ok?).returns(false)
        copilot_user.cancel_and_refund_active_subscription(
          organization: organization,
        )
      end

      assert_match "Subscription exists, but could not be cancelled", logs
    end
  end

  context "async_copilot_active_subscription_item" do
    test "it ges the active subscription item" do
      expected_item = Billing::Public::SubscriptionItem.create(
        product: @copilot_yearly_product_identifier,
        account: @plan_user,
        actor: @plan_user,
        free_trial_length: 10.days
      ).value!

      result = Copilot::User.new(@plan_user).async_copilot_active_subscription_item.sync
      assert_equal expected_item.id, result.id
    end

    test "no errors" do
      result = Copilot::User.new(@plan_user).async_copilot_active_subscription_item.sync
      refute result
    end
  end

  context "subscription_ended_due_to_billing_trouble?" do
    test "returns true if copilot subscription downgraded due to billing attempt exhaustion" do
      @plan_user.update(billing_attempts: 3)
      @plan_subscription.update(balance_in_cents: 1000)

      transaction_for_plan_user = create(:billing_transaction,
                                         plan_name: "free_with_addons",
                                         user: @plan_user,
                                         last_status: :processor_declined,
                                        )

      create(
        :billing_transaction_line_item,
        subscribable: @copilot_monthly_product_uuid,
        billing_transaction: transaction_for_plan_user
      )

      create(
        :billing_subscription_item,
        subscribable: @copilot_monthly_product_uuid,
        plan_subscription: @plan_subscription,
        quantity: 0
      )

      assert Copilot::User.new(@plan_user).subscription_ended_due_to_billing_trouble?
    end
  end

  context "#free_user" do
    test "returns nil when no free user exists" do
      assert_nil Copilot::User.new(@user).free_user
    end

    test "returns the free user when it exists" do
      free_user = create(:copilot_free_user, user: @user)
      assert_equal free_user, Copilot::User.new(@user).free_user
    end
  end

  context "#days_left_on_trial" do
    test "returns" do
      travel_to(Time.zone.local(2020, 1, 1, 10, 0, 0)) do
        item = Billing::Public::SubscriptionItem.create(
          product: @copilot_yearly_product_identifier,
          account: @plan_user,
          actor: @plan_user,
          free_trial_length: 10.days
        )
        assert_equal 10, item.value!.free_trial_length

        assert Copilot::User.new(@plan_user).has_trial_subscription?
      end

      # next day
      travel_to(Time.zone.local(2020, 1, 2, 10, 0, 0)) do
        assert_equal 9, Copilot::User.new(@plan_user).days_left_on_trial
      end
    end
  end

  context "trial_only_subscription?" do
    test "returns true if there is no paid subscription" do
      create(:billing_subscription_item,
        plan_subscription: @plan_subscription,
        subscribable: @copilot_monthly_product_uuid,
        free_trial_ends_on: 10.days.ago,
        quantity: 0
      )

      assert Copilot::User.new(@plan_user).trial_only_subscription?
    end

    test "returns false if there is no trial" do
      refute Copilot::User.new(@plan_user).trial_only_subscription?
    end

    test "returns false if there is a paid subscription" do
      create(:billing_subscription_item,
        plan_subscription: @plan_subscription,
        subscribable: @copilot_monthly_product_uuid,
        free_trial_ends_on: 10.days.ago,
        quantity: 0
      )
      billing_transaction = create(:billing_transaction, user: @plan_user, amount_in_cents: 1000)
      create(:billing_transaction_line_item, billing_transaction: billing_transaction, subscribable: @copilot_monthly_product_uuid)

      refute Copilot::User.new(@plan_user).trial_only_subscription?
    end
  end
end if GitHub.copilot_enabled?
