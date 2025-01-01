# typed: true
# frozen_string_literal: true

require "test_helper"

module UserBillingSubscriptionSharedTests
  extend T::Helpers

  requires_ancestor { GitHub::BillingTestCase }

  def test_billed_through_azure_subscription_returns_false_for_both_orgs_and_users_since_they_are_not_setup_to_be_billed_through_azure
    refute_predicate @organization, :billed_through_azure_subscription?
    refute_predicate @user, :billed_through_azure_subscription?
  end

  def test_linked_azure_subscription_returns_false_for_both_orgs_and_users_since_they_do_not_have_an_option_to_link_azure_subscriptions
    refute_predicate @organization, :linked_azure_subscription?
    refute_predicate @user, :linked_azure_subscription?
  end
end

module UserBillingDependencySharedTests
  extend T::Helpers

  requires_ancestor { GitHub::BillingTestCase }

  def test_expected_plan_for_a_user
    assert_equal @expected_user_plan, @user.plan
  end

  def test_current_metered_billing_cycle_starts_at_returns_the_business_metered_cycle_when_business_owned_organization
    business_current_metered_billing_cycle_starts_at = GitHub::Billing.timezone.local(2021, 1, 20, 12, 12, 12)
    @business.stubs(:current_metered_billing_cycle_starts_at).returns(business_current_metered_billing_cycle_starts_at)
    organization = Organization.new(business: @business, billed_on: (business_current_metered_billing_cycle_starts_at + 3.days).to_date)

    assert_equal business_current_metered_billing_cycle_starts_at, organization.current_metered_billing_cycle_starts_at
  end

  def test_next_metered_billing_cycle_starts_at_delegates_to_the_business_if_there_is_one
    time = Time.find_zone("UTC").local(2019, 11, 12, 1, 2, 3)
    @business.expects(:next_metered_billing_cycle_starts_at).returns(time)
    organization = Organization.new(business: @business)
    assert_equal time, organization.next_metered_billing_cycle_starts_at
  end
end

class UserBillingDependencyTest < GitHub::BillingTestCase
  include UserBillingSubscriptionSharedTests
  include UserBillingDependencySharedTests

  include AuditLog::IntegrationTestHelpers
  include GitHub::Billing::CurrencyTestHelper
  include GitHub::ZuoraTestHelper
  include HydroTestHelpers
  include GitHub::LoggerHelper

  fixtures do
    @organization = create(:organization)
    @free_org = create(:free_org)
    @user = create(:user)
    @credit_card_user = create(:credit_card_user)
    @non_trusted_user = create(:credit_card_user)
    @non_trusted_user.settings.set!(:trust_tier, 2)
    @trusted_user = create(:credit_card_user)
    @trusted_user.settings.set!(:trust_tier, 1)
    @invoiced_organization = create(:invoiced_organization)
    @product_uuid = create(:billing_product_uuid, :copilot)
    create(:billing_product_uuid, :advanced_security)

    @plan_subscription = create(:billing_plan_subscription)

    unless GitHub.single_business_environment?
      @business = create(:business)
      @emu_business = create(:business, :enterprise_managed)
      @emu_user = create(:emu, business: @emu_business)
      @emu_org = create(:organization, business: @emu_business)
      @guest_collaborator = create(:emu, :guest_collaborator, business: @emu_business)
      @emu_team = create(:team, organization: @emu_org)
      @emu_team.add_member(@guest_collaborator)
    end
  end

  setup do
    @expected_user_plan = GitHub::Plan.find(GitHub.default_plan_name, account: @user)
    ActionMailer::Base.deliveries.clear
    GitHub::Experiment.raise_on_mismatches = false
    setup_currency_exchange
  end

  context "#change_billing_duration_message" do
    test "returns switch to yearly billing if current duration is monthly" do
      @organization.assign_attributes(plan_duration: User::BillingDependency::MONTHLY_PLAN, plan: "business")

      assert_equal "Switch to yearly billing", @organization.change_billing_duration_message
    end

    test "returns switch to monthly billing if current duration is yearly" do
      @organization.assign_attributes(plan_duration: User::BillingDependency::YEARLY_PLAN, plan: "business")

      assert_equal "Switch to monthly billing", @organization.change_billing_duration_message
    end
  end

  context "#plan_trial_active?" do
    test "returns true when there is an active trial for the user and plan specified" do
      create(:billing_plan_trial, :active, user: @user, plan: "business_plus")
      assert @user.plan_trial_active?("business_plus")
    end

    test "defaults to checking the user's current plan when no plan is specified" do
      @user.update!(plan: "business_plus")
      refute_predicate @user, :plan_trial_active?

      create(:billing_plan_trial, :active, user: @user, plan: "business_plus")
      assert_predicate @user.reload, :plan_trial_active?
    end

    test "returns false when there is an inactive trial for the user and plan specified" do
      create(:billing_plan_trial, :expired, user: @user, plan: "business_plus")
      refute @user.plan_trial_active?("business_plus")
    end

    test "returns false when there is no trial for the user and plan specified" do
      refute @user.plan_trial_active?("some random plan")
    end

    test "returns false when the pending plan change has been deleted" do
      plan_trial = create(:billing_plan_trial, :active, user: @user, plan: "business_plus")
      plan_trial.pending_plan_change.destroy
      refute @user.plan_trial_active?("business_plus")
    end

    test "can be batch loaded for multiple users efficiently" do
      plan_name = "business_plus"
      user_on_trial1, user_on_trial2 = create_pair(:billing_plan_trial, :active, plan: plan_name).map(&:user)
      user_not_on_trial1, user_not_on_trial2 = create_pair(:user, plan: plan_name)
      user_not_on_plan1, user_not_on_plan2 = create_pair(:user)
      expired_user_on_trial1, expired_user_on_trial2 = create_pair(:billing_plan_trial, :expired, plan: plan_name)
        .map(&:user)

      users = [user_on_trial1, user_on_trial2, user_not_on_trial1, user_not_on_trial2, user_not_on_plan1,
        user_not_on_plan2, expired_user_on_trial1, expired_user_on_trial2]

      assert_query_count(2) do
        GitHub::PrefillAssociations.prefill_batch_method(users, :plan_trial_active?, plan_name)
      end

      assert_query_count(0) do
        assert user_on_trial1.plan_trial_active?(plan_name)
        assert user_on_trial2.plan_trial_active?(plan_name)
        refute user_not_on_trial1.plan_trial_active?(plan_name)
        refute user_not_on_trial2.plan_trial_active?(plan_name)
        refute user_not_on_plan1.plan_trial_active?(plan_name)
        refute user_not_on_plan2.plan_trial_active?(plan_name)
        refute expired_user_on_trial1.plan_trial_active?(plan_name)
        refute expired_user_on_trial2.plan_trial_active?(plan_name)
      end
    end
  end

  context "billing_locked?" do
    test "returns true if the user is disabled" do
      @credit_card_user.customer.lock_billing
      assert @credit_card_user.billing_locked?
    end

    test "can be batch loaded for multiple users efficiently" do
      non_customer_users = [@user, @free_org]
      customer_users = [@credit_card_user, @trusted_user, @non_trusted_user]
      @non_trusted_user.disable!

      assert_query_count(2) do
        GitHub::PrefillAssociations.prefill_batch_method(non_customer_users + customer_users, :billing_locked?)
      end

      assert_query_count(0) do
        refute @user.customer&.billing_locked?
        refute @free_org.customer&.billing_locked?
        refute @credit_card_user.customer&.billing_locked?
        refute @trusted_user.customer&.billing_locked?
        assert @non_trusted_user.customer&.billing_locked?
      end
    end
  end

  context "#munich_seats_manageable_by?" do
    test "returns true if manage_munich_seats is enabled" do
      org_admin = @user
      munich_paid_org = create(:business_org, seats: 5, admin: org_admin)
      assert munich_paid_org.munich_seats_manageable_by?(org_admin)
    end

    test "returns true if current_user is billing manager" do
      billing_manager = @user
      munich_paid_org = create(:business_org, seats: 5)
      munich_paid_org.billing.add_manager(billing_manager, actor: munich_paid_org.admins.first)
      assert munich_paid_org.munich_seats_manageable_by?(billing_manager)
    end

    test "returns false if current_user is not an admin or billing manager" do
      rando = @user
      munich_paid_org = create(:business_org, seats: 5)
      refute munich_paid_org.munich_seats_manageable_by?(rando)
    end

    test "returns false if target is not an organization" do
      refute @user.munich_seats_manageable_by?(@user)
    end

    test "returns false if org is not on per_seat plan" do
      org = create(:free_org)
      refute org.munich_seats_manageable_by?(org.admins.first)
    end

    test "returns false if manage_munich_seats is enabled but the organization is part of a business", skip_enterprise: true do
      munich_paid_org = create(:business_org, seats: 5)
      create(:business, organizations: [munich_paid_org])
      refute munich_paid_org.reload.munich_seats_manageable_by?(munich_paid_org.admins.first)
    end
  end

  context "#remove_gated_features" do
    test "unpublishes pages of private repos" do
      disable_feature_flag(:pages_soft_deletion)
      user = create :user, :zuora, plan: "pro"
      repo = create(:private_repository, owner: user)

      create(:page, repository: repo)
      user.reload

      assert repo.page

      user.update(plan: "free")

      user.remove_gated_features
      assert_nil repo.reload.page
    end

    test "does not remove gated features for users migrating to a non free plan" do
      user = create :user, :zuora, plan: "pro"
      repo = create(:private_repository, owner: user)

      create(:page, repository: repo)
      create(:protected_branch, repository: repo, creator: user)

      assert repo.page
      assert repo.private?

      perform_enqueued_jobs only: DestroyPrivatePageJob do
        user.remove_gated_features
      end

      repo.reload
      assert repo.page
    end

    test "does not remove protected branches and downgrading to a free plan" do
      user = create :user, :zuora, plan: "free"
      repo = create(:private_repository, owner: user)

      create(:page, repository: repo)
      create(:protected_branch, repository: repo, creator: user)
      user.reload

      user.remove_gated_features

      repo.reload
      refute_empty repo.protected_branches
    end
  end

  context "#plan_supports_unlimited_private_repos?" do
    test "returns true for a free user account" do
      @user.assign_attributes(plan: GitHub::Plan.free)
      assert_predicate @user, :plan_supports_unlimited_private_repos?
    end

    test "returns false for org account on a legacy plan" do
      assert_predicate @organization.plan, :legacy?
      refute_predicate @organization, :plan_supports_unlimited_private_repos?
    end

    test "returns true for free org account" do
      @organization.assign_attributes(plan: GitHub::Plan.free)
      assert_predicate @organization, :plan_supports_unlimited_private_repos?
    end

    test "returns true for business plus org account" do
      @organization.assign_attributes(plan: GitHub::Plan.business_plus)
      assert_predicate @organization, :plan_supports_unlimited_private_repos?
    end
  end

  context "#manual_payment_due_date" do
    test "returns nil if the user is not in manual dunning" do
      assert_nil @user.manual_dunning_period
      assert_nil @user.manual_payment_due_date
    end

    test "returns the manual dunning due date when the user has a corresponding record" do
      manual_dunning_record = create(:manual_dunning_period, user: @user)
      assert_equal manual_dunning_record.due_date, @user.manual_payment_due_date
    end
  end

  context "#subscription_items_adminable_by?" do
    test "true for an org for a sponsorship by an org's billing manager" do
      org = @organization
      billing_manager = @user
      org.billing.add_manager(billing_manager, actor: org.admins.first)

      assert org.subscription_items_adminable_by?(billing_manager,
        subscribable_type: "SponsorsTier")
    end

    test "false for an org for an unspecified subscribable by an org's billing manager" do
      org = @organization
      billing_manager = @user
      org.billing.add_manager(billing_manager, actor: org.admins.first)

      refute org.subscription_items_adminable_by?(billing_manager, subscribable_type: nil)
    end

    test "true for a Sponsors-invoiced org for a sponsorship by a staff user" do
      invoiced_org = create(:invoiced_organization, :sponsors_invoiced)
      staff = create(:staff_admin_user)

      assert invoiced_org.subscription_items_adminable_by?(staff, subscribable_type: "SponsorsTier")
    end

    test "false for an org for a Marketplace purchase by an org's billing manager" do
      org = @organization
      billing_manager = @user
      org.billing.add_manager(billing_manager, actor: org.admins.first)

      refute org.subscription_items_adminable_by?(billing_manager,
        subscribable_type: "Marketplace::ListingPlan")
    end

    test "true for a self-serve EA org for a Marketplace purchase by an EA owner + org admin" do
      business = create :business, :with_self_serve_payment
      org = create :organization, business: business
      user = org.admins.first
      org.terms_of_service.update(type: "Corporate", actor: user)
      create :marketplace_listing_plan, :paid, :verified_listing
      business.add_owner(user, actor: nil)

      assert org.subscription_items_adminable_by?(user,
        subscribable_type: "Marketplace::ListingPlan")
    end

    test "false for a self-serve EA org for a Marketplace purchase by an org admin that is not an EA owner" do
      business = create :business, :with_self_serve_payment
      org = create :organization, business: business
      user = org.admins.first
      org.terms_of_service.update(type: "Corporate", actor: user)
      create :marketplace_listing_plan, :paid, :verified_listing

      refute org.subscription_items_adminable_by?(user,
        subscribable_type: "Marketplace::ListingPlan")
    end
  end

  context "#current_metered_billing_cycle_starts_at", skip_enterprise: true do
    test "returns the start of the day (in the billing time zone) on the first of the current month for free plans" do
      travel_to GitHub::Billing.timezone.local(2019, 10, 16, 12, 12, 12) do
        user = User.new(plan: "free")
        assert_equal GitHub::Billing.timezone.local(2019, 10, 1), user.current_metered_billing_cycle_starts_at
      end
    end

    test "returns the beginning of the day (in the billing time zone) on the most recent day-of-month that the user is billed on for monthly plans" do
      travel_to GitHub::Billing.timezone.local(2018, 12, 20, 12, 12, 12) do
        user = create(:user, :zuora, plan: "pro", plan_duration: User::BillingDependency::MONTHLY_PLAN, billed_on: Date.new(2019, 1, 15))
        assert_equal GitHub::Billing.timezone.local(2018, 12, 15), user.current_metered_billing_cycle_starts_at
      end
    end

    test "returns the beginning of the day (in the billing time zone) on the most recent day-of-month that the user is billed on for yearly plans" do
      travel_to GitHub::Billing.timezone.local(2018, 12, 20, 12, 12, 12) do
        user = create(:user, :zuora, plan: "pro", plan_duration: User::BillingDependency::YEARLY_PLAN, billed_on: Date.new(2019, 1, 12))
        assert_equal GitHub::Billing.timezone.local(2018, 12, 12), user.current_metered_billing_cycle_starts_at
      end
    end

    test "returns the beginning of the day (in the billing time zone) on the most recent day-of-month that the user is billed on even if that was in a previous calendar month" do
      travel_to GitHub::Billing.timezone.local(2018, 12, 20, 12, 12, 12) do
        user = create(:user, :zuora, plan: "pro", plan_duration: User::BillingDependency::YEARLY_PLAN, billed_on: Date.new(2019, 1, 28))
        assert_equal GitHub::Billing.timezone.local(2018, 11, 28), user.current_metered_billing_cycle_starts_at
      end
    end

    test "returns the beginning of the day (in the billing time zone) on the last day of the month if the day-of-month that the user is billed on is greater than the days in the current month" do
      travel_to GitHub::Billing.timezone.local(2019, 3, 2, 12, 12, 12) do
        user = create(:user, :zuora, plan: "pro", plan_duration: User::BillingDependency::YEARLY_PLAN, billed_on: Date.new(2019, 7, 30))
        assert_equal GitHub::Billing.timezone.local(2019, 2, 28), user.current_metered_billing_cycle_starts_at
      end
    end

    test "returns the beginning of the day (in the billing time zone) on the last day of the month if it is the last day of the month and the bcd > last day of the month" do
      travel_to GitHub::Billing.timezone.local(2019, 2, 28, 12, 12, 12) do
        user = create(:user, :zuora, plan: "pro", plan_duration: User::BillingDependency::YEARLY_PLAN, billed_on: Date.new(2019, 7, 30))
        assert_equal GitHub::Billing.timezone.local(2019, 2, 28), user.current_metered_billing_cycle_starts_at
      end
    end

    test "returns the first of the current month (based on UTC, not the billing timezone) when an organization is metered via azure" do
      travel_to GitHub::Billing.timezone.local(2019, 9, 30, 23, 59, 59) do
        org = @organization
        org.customer = create(:customer, metered_via_azure: true, azure_subscription_id: SecureRandom.uuid)
        assert_equal Time.find_zone("UTC").local(2019, 10, 1), org.current_metered_billing_cycle_starts_at
      end
    end

    test "returns the first of the current month (based on UTC, not the billing timezone) when an organization is billed through billing platform" do
      travel_to GitHub::Billing.timezone.local(2019, 9, 30, 23, 59, 59) do
        org = @organization
        org.customer = create(:customer, billed_via_billing_platform: true)
        assert_equal Time.find_zone("UTC").local(2019, 10, 1), org.current_metered_billing_cycle_starts_at
      end
    end
  end

  context "#next_metered_billing_cycle_starts_at" do
    test "returns correct date for free plans" do
      moment = GitHub::Billing.timezone.local(2018, 12, 20, 12, 12)
      travel_to moment do
        user = @user
        assert_equal GitHub::Billing.timezone.local(2019, 1, 1), user.next_metered_billing_cycle_starts_at
      end
    end

    test "returns correct date for monthly plans" do
      moment = GitHub::Billing.timezone.local(2018, 12, 20, 12, 12)
      travel_to moment do
        user = create(:user, :zuora, plan: "business", plan_duration: User::BillingDependency::MONTHLY_PLAN, billed_on: Date.new(2019, 1, 15))
        assert_equal GitHub::Billing.timezone.local(2019, 1, 15), user.next_metered_billing_cycle_starts_at
      end
    end

    test "returns correct date for yearly plans" do
      moment = GitHub::Billing.timezone.local(2018, 12, 20, 12, 12)
      travel_to moment do
        user = create(:user, :zuora, plan: "business", plan_duration: User::BillingDependency::YEARLY_PLAN, billed_on: Date.new(2019, 6, 12))
        assert_equal GitHub::Billing.timezone.local(2019, 1, 12), user.next_metered_billing_cycle_starts_at
      end
    end

    test "returns next month for annual plans if billing day is later in current month" do
      moment = GitHub::Billing.timezone.local(2018, 12, 20, 12, 12)
      travel_to moment do
        user = create(:user, :zuora, plan: "business", plan_duration: User::BillingDependency::YEARLY_PLAN, billed_on: Date.new(2018, 6, 28)) # billing many months in the past

        assert_equal GitHub::Billing.timezone.local(2018, 12, 28), user.next_metered_billing_cycle_starts_at # same day number as last billing but at end of the month
      end
    end

    test "returns previous month if previous billing day is greater than last day of the month" do
      moment = GitHub::Billing.timezone.local(2019, 2, 2, 12, 12)
      travel_to moment do
        user = create(:user, :zuora, plan: "business", plan_duration: User::BillingDependency::YEARLY_PLAN, billed_on: Date.new(2020, 1, 15)) # Billed on date not in February

        # First day in next metered cycle, should be February 15th
        assert_equal GitHub::Billing.timezone.local(2019, 2, 15), user.next_metered_billing_cycle_starts_at # same day number as last billing but in next month
      end
    end

    test "returns the last day of the month if the Bill Cycle Day is greater than the month's days" do
      moment = GitHub::Billing.timezone.local(2019, 2, 2, 12, 12)
      travel_to moment do
        user = create(
          :user,
          :zuora,
          plan: "business",
          plan_duration: User::BillingDependency::YEARLY_PLAN, billed_on: Date.new(2019, 7, 30)
        ) # Billed on date not in February

        # Bill Cycle Day is end of month
        assert_equal GitHub::Billing.timezone.local(2019, 2, 28), user.next_metered_billing_cycle_starts_at
      end
    end

    test "returns correct date when when current month has more days than previous month" do
      dates = %w[2020-03-30 2020-03-31 2020-05-31 2020-07-31 2020-10-31 2020-12-31]
      dates.each do |d|
        date = Date.parse(d)
        time = GitHub::Billing.date_in_timezone(date, hours: 12, minutes: 12)
        travel_to time - 1.day do
          user = create(:user, :zuora, plan: "business", plan_duration: User::BillingDependency::YEARLY_PLAN, billed_on: date)
          refute_equal user.next_metered_billing_cycle_starts_at, (user.current_metered_billing_cycle_starts_at + 1.month)
          assert_equal time.beginning_of_day, user.next_metered_billing_cycle_starts_at
        end
      end
    end

    test "returns the first of the next month (based on UTC, not the billing timezone) when an enterprise is metered via azure" do
      travel_to GitHub::Billing.timezone.local(2019, 9, 30, 23, 59, 59) do
        org = @organization
        org.customer = create(:customer, metered_via_azure: true, azure_subscription_id: SecureRandom.uuid)
        assert_equal Time.find_zone("UTC").local(2019, 11, 1), org.next_metered_billing_cycle_starts_at
      end
    end

    test "returns the first of the next month (based on UTC, not the billing timezone) when an organization is billed through billing platform" do
      travel_to GitHub::Billing.timezone.local(2019, 9, 30, 23, 59, 59) do
        org = @organization
        org.customer = create(:customer, billed_via_billing_platform: true)
        assert_equal Time.find_zone("UTC").local(2019, 11, 1), org.next_metered_billing_cycle_starts_at
      end
    end
  end

  context "#disable!" do
    context "past due" do
      test "cancels sponsors subscription items" do
        item = create :sponsors_subscription_item

        create(:billing_product_uuid, :sponsors_listing, listing: item.subscribable.listing)
        plan_subscription = item.plan_subscription
        user = plan_subscription.user

        past_due_ids = [item.active_product_rate_plan_charge_id].to_set
        Billing::SubscriptionItem.any_instance.stubs(:past_service_period?).returns(true)
        Billing::CancelPastDueProductsJob.any_instance.stubs(:past_due_product_rate_plan_charge_ids).returns(past_due_ids)

        assert_equal 1, user.reload.active_subscription_items.count

        only = [Billing::CancelPastDueProductsJob]
        perform_enqueued_jobs(only: only) do
          user.disable!
        end

        assert_equal 0, user.reload.active_subscription_items.count
      end

      test "cancels subscription items" do
        plan_subscription = create(:billing_plan_subscription, :zuora)
        user = plan_subscription.user
        item1 = create :billing_subscription_item, :product_uuid_link, plan_subscription: plan_subscription
        item2 = create :billing_subscription_item, :with_product_uuid, plan_subscription: plan_subscription

        past_due_ids = [item1.active_product_rate_plan_charge_id, item2.active_product_rate_plan_charge_id].to_set
        Billing::SubscriptionItem.any_instance.stubs(:past_service_period?).returns(true)
        Billing::CancelPastDueProductsJob.any_instance.stubs(:past_due_product_rate_plan_charge_ids).returns(past_due_ids)

        assert_equal 2, user.reload.active_subscription_items.count

        only = [Billing::CancelPastDueProductsJob]
        perform_enqueued_jobs(only: only) do
          user.disable!
        end

        assert_equal 0, user.reload.active_subscription_items.count
      end

      test "cancels all paid subscription items and all product uuid pending subscription item changes" do
        plan_subscription = create(:billing_plan_subscription, :zuora)
        user = plan_subscription.user
        listing_plan = create(:marketplace_listing_plan, :published, :product_uuid_link)
        item1 = create :billing_subscription_item, subscribable: listing_plan, plan_subscription: plan_subscription
        item2 = create :billing_subscription_item, subscribable: @product_uuid, plan_subscription: plan_subscription

        past_due_ids = [item1.active_product_rate_plan_charge_id, item2.active_product_rate_plan_charge_id].to_set
        Billing::SubscriptionItem.any_instance.stubs(:past_service_period?).returns(true)
        Billing::CancelPastDueProductsJob.any_instance.stubs(:past_due_product_rate_plan_charge_ids).returns(past_due_ids)


        pending_plan_change = create(:billing_pending_plan_change, user: user)
        create :billing_pending_subscription_item_change, :cancellation, subscribable: @product_uuid, pending_plan_change: pending_plan_change
        create :billing_pending_subscription_item_change, pending_plan_change: pending_plan_change, subscribable: listing_plan, quantity: 3

        assert_equal 2, user.reload.active_subscription_items.count
        assert_equal 2, user.pending_subscription_item_changes.count

        perform_enqueued_jobs(only: [Billing::CancelPastDueProductsJob]) do
          user.disable!
        end

        assert_equal 1, user.reload.pending_subscription_item_changes.count
        assert_equal 0, user.active_subscription_items.count
        assert_empty user.pending_subscription_item_changes.select { |item| item.subscribable == @product_uuid }
      end

      test "does not cancel in-app purchases" do
        plan_subscription = @plan_subscription
        user = plan_subscription.user
        listing_plan = create(:marketplace_listing_plan, :published, :product_uuid_link)

        non_iap_sub = create(:billing_subscription_item, subscribable: listing_plan, plan_subscription: plan_subscription)
        iap_sub = create(:billing_subscription_item, :iap, subscribable: @product_uuid, plan_subscription: plan_subscription)

        past_due_ids = [non_iap_sub.active_product_rate_plan_charge_id].to_set
        Billing::SubscriptionItem.any_instance.stubs(:past_service_period?).returns(true)
        Billing::CancelPastDueProductsJob.any_instance.stubs(:past_due_product_rate_plan_charge_ids).returns(past_due_ids)

        assert_predicate non_iap_sub, :active?
        assert_predicate iap_sub, :active?

        perform_enqueued_jobs only: [Billing::CancelPastDueProductsJob] do
          user.disable!
        end

        assert_predicate user.reload, :disabled?
        refute_predicate non_iap_sub.reload, :active?
        assert_predicate iap_sub.reload, :active?
      end
    end

    test "disables the user and notes the reason for the failure if provided" do
      plan_subscription = create(:billing_plan_subscription, :zuora)
      user = plan_subscription.user.reload

      user.disable!(reason: Billing::Public::BillingDisabledReasons::AuthorizationFailure)
      assert user.reload.disabled?
      assert user.disabled_reasons.include?(Billing::Public::BillingDisabledReasons::AuthorizationFailure.serialize)
    end

    test "clears all disabled reasons when the user is enabled" do
      plan_subscription = create(:billing_plan_subscription, :zuora)
      user = plan_subscription.user.reload

      user.disable!(reason: Billing::Public::BillingDisabledReasons::AuthorizationFailure)
      assert user.reload.disabled?
      assert user.disabled_reasons.include?(Billing::Public::BillingDisabledReasons::AuthorizationFailure.serialize)

      user.enable!
      assert user.reload.disabled_reasons.empty?
    end

    test "disables billing for a Business-owned organization, even if owned by an enabled Business" do
      org = create(:credit_card_org)
      user = @user
      business = create :business, owners: [user], organizations: [org]

      refute_predicate org, :disabled?

      org.disable!

      assert_predicate org, :disabled?
      assert_predicate business, :enabled?  # Business' billing is unaffected
    end

    test "enqueues CancelPastDueProductsJob when disabled" do
      assert_enqueued_jobs(1, only: [Billing::CancelPastDueProductsJob]) do
        @user.disable!
      end
    end
  end

  context "#orgs_linked_to_billing_contact" do
    test "returns all orgs that have a linked contact to this user" do
      user = @credit_card_user
      contact = create(:billing_contact, customer: user.customer)
      org1 = create(:credit_card_org, admin: user)
      enable_feature_flag(:read_billing_information_from_contacts, org1)
      org2 = create(:credit_card_org, admin: user)
      enable_feature_flag(:read_billing_information_from_contacts, org2)
      org3 = create(:credit_card_org, admin: user)
      enable_feature_flag(:read_billing_information_from_contacts, org3)
      create(:credit_card_org, admin: user)
      org1.billing_contact_link.update(id: contact.id)
      org2.billing_contact_link.update(id: contact.id)
      org3.billing_contact_link.update(id: contact.id)

      assert_predicate user.orgs_linked_to_billing_contact, :any?
      assert_equal 3, user.orgs_linked_to_billing_contact.count
    end

    test "returns empty list when there are no linked orgs to this user" do
      user = @credit_card_user
      create(:billing_contact, customer: user.customer)
      create(:credit_card_org, admin: user)

      refute_nil user.orgs_linked_to_billing_contact
      assert_predicate user.orgs_linked_to_billing_contact, :empty?
    end

    test "returns empty list when it's not a user" do
      user = @credit_card_user
      create(:billing_contact, customer: user.customer)
      org = create(:credit_card_org, admin: user)

      refute_nil org.orgs_linked_to_billing_contact
      assert_predicate org.orgs_linked_to_billing_contact, :empty?
    end

    test "returns empty list when user doesn't have a customer" do
      user = @user
      create(:credit_card_org, admin: user)

      refute_nil user.orgs_linked_to_billing_contact
      assert_predicate user.orgs_linked_to_billing_contact, :empty?
    end

    test "returns empty list when user doesn't have a billing contact" do
      user = @credit_card_user
      create(:shipping_contact, customer: user.customer)
      create(:credit_card_org, admin: user)

      refute_nil user.orgs_linked_to_billing_contact
      assert_predicate user.orgs_linked_to_billing_contact, :empty?
    end
  end

  context "#unlink_contact_from_all_linked_orgs" do
    test "unlinks all orgs associated with the user's billing contact" do
      contact = create(:billing_contact, customer: @credit_card_user.customer)
      org1 = create(:credit_card_org, admin: @credit_card_user)
      org2 = create(:credit_card_org, admin: @credit_card_user)
      org3 = create(:credit_card_org, admin: @credit_card_user)
      create(:credit_card_org, admin: @credit_card_user)
      enable_feature_flag(:read_billing_information_from_contacts, org1)
      enable_feature_flag(:read_billing_information_from_contacts, org2)
      enable_feature_flag(:read_billing_information_from_contacts, org3)
      assert org1.link_billing_contact(actor: @credit_card_user)
      assert org2.link_billing_contact(actor: @credit_card_user)
      assert org3.link_billing_contact(actor: @credit_card_user)
      assert_predicate org1, :has_linked_billing_contact?
      assert_predicate org2, :has_linked_billing_contact?
      assert_predicate org3, :has_linked_billing_contact?

      @credit_card_user.unlink_contact_from_all_linked_orgs

      refute_predicate org1.reload, :has_linked_billing_contact?
      refute_predicate org2.reload, :has_linked_billing_contact?
      refute_predicate org3.reload, :has_linked_billing_contact?
    end

    test "does nothing when it's called by an org" do
      create(:billing_contact, customer: @credit_card_user.customer)
      org = create(:credit_card_org, admin: @credit_card_user)
      assert org.link_billing_contact(actor: @credit_card_user)
      unless org.feature_enabled?(:read_billing_information_from_contacts)
        create :account_screening_profile, owner: @credit_card_user
        assert @credit_card_user.link_trade_screening_record_to_org(organization: org)
      end
      assert_predicate org, :has_linked_billing_contact?

      org.unlink_contact_from_all_linked_orgs

      assert_predicate org, :has_linked_billing_contact?
    end
  end

  context "#eligible_for_free_trial_on?" do
    test "returns false if the user has paid for any plan in the listing" do
      subscription_item = create(:billing_subscription_item, plan_subscription: @plan_subscription)
      marketplace_listing = subscription_item.listing

      refute @plan_subscription.user.reload.eligible_for_free_trial_on?(product: marketplace_listing)
    end

    test "returns false if the user is currently on a free trial" do
      subscription_item = create(:billing_subscription_item, :free_trial, plan_subscription: @plan_subscription)
      marketplace_listing = subscription_item.listing

      refute @plan_subscription.user.reload.eligible_for_free_trial_on?(product: marketplace_listing)
    end

    test "returns true if the user has never used a paid on the listing" do
      create(:billing_subscription_item, :free, plan_subscription: @plan_subscription)
      free_trial_plan = create(:marketplace_listing_plan, :free_trial)
      marketplace_listing = free_trial_plan.listing

      assert @plan_subscription.user.eligible_for_free_trial_on?(product: marketplace_listing)
    end

    test "returns true if the user does not have a plan subscription" do
      marketplace_listing = create(:marketplace_listing_plan, :free_trial).listing

      assert @user.eligible_for_free_trial_on?(product: marketplace_listing)
    end
  end

  context "#show_custom_role_downgrade_warning?" do
    test "false for user" do
      refute_predicate @user, :show_custom_role_downgrade_warning?
    end

    test "true for Enterprise plan with custom roles" do
      org = create(:business_plus_organization)
      Role.create!(name: "foo", owner_id: org.id, owner_type: "Organization", base_role_id: Role.triage_role.id)

      assert_predicate org, :show_custom_role_downgrade_warning?
    end

    test "false for Enterprise plan without custom roles" do
      org = create(:business_plus_organization)

      refute_predicate org, :show_custom_role_downgrade_warning?
    end

    test "true for Enterprise plan with custom org roles" do
      org = create(:business_plus_organization)
      create(:custom_organization_role, owner_id: org.id)
      assert_predicate org, :show_custom_role_downgrade_warning?
    end
  end

  context "#apple_iap_subscription?" do
    test "returns false for a user without a subscription" do
      refute @user.apple_iap_subscription?
    end

    test "returns true for a user with an apple_receipt_id and apple_transaction_id" do
      user = create(:billing_plan_subscription, :apple_iap).user
      assert user.apple_iap_subscription?
    end
  end

  context "#gift_type_description" do
    test "describes a user with a teacher gift account" do
      assert_equal "Teacher/student group", build(:user, billing_type: "teacher").gift_type_description
    end

    test "describes a user with a gift account" do
      assert_equal "Gift", build(:user, billing_type: "gift").gift_type_description
    end

    test "describes a user with a non-gift account" do
      assert_equal "Normal account", build(:user, billing_type: "card").gift_type_description
    end
  end

  context "#teacher_gift?" do
    test "returns true for user with billing_type=teacher" do
      assert_predicate build(:user, billing_type: "teacher"), :teacher_gift?
    end

    test "returns false for user without billing_type=teacher" do
      refute_predicate build(:user, billing_type: "card"), :teacher_gift?
    end
  end

  context "#next_free_trial_end_date" do
    test "returns the date of the free trial ending soonest" do
      travel_to(GitHub::Billing.timezone.parse("October 25 2017")) do
        ending_in_1_week = create(:billing_subscription_item, :free_trial)
        ending_in_1_week.update_attribute(:free_trial_ends_on, 1.week.from_now)
        user = ending_in_1_week.user.reload

        ending_in_3_days = create :billing_subscription_item, :free_trial, plan_subscription: user.plan_subscription
        ending_in_3_days.update_attribute(:free_trial_ends_on, 3.days.from_now)

        assert_equal ending_in_3_days.reload.free_trial_ends_on, user.reload.next_free_trial_end_date
      end
    end

    test "returns nil if free trials have been run" do
      trial = create(:billing_subscription_item, :free_trial)
      user = trial.user

      pending_change = create :billing_pending_plan_change,
        active_on: GitHub::Billing.today + 4.days,
        plan: nil,
        user: user,
        actor: user
      create :billing_pending_subscription_item_change,
        subscribable: trial.subscribable,
        free_trial: true,
        pending_plan_change: pending_change,
        quantity: 4
      pending_change.run

      assert_nil user.next_free_trial_end_date
    end
  end

  test "next_payment_due_on returns the next time the user will need to pay" do
    travel_to(GitHub::Billing.timezone.parse("October 25 2017")) do
      user = @plan_subscription.user
      user.update(billed_on: GitHub::Billing.today + 3.weeks)
      free_trial = create :billing_subscription_item,
        :free_trial,
        plan_subscription: @plan_subscription

      assert_equal free_trial.reload.free_trial_ends_on, user.next_payment_due_on
    end
  end

  context "#user_ids_with_private_repo_access" do
    test "is empty when the record hasn't yet been saved" do
      repo = create(:private_repository)
      repo.add_members([@user])
      assert_equal @organization.user_ids_with_private_repo_access, []
    end
  end

  context "#private_repo_non_collaborator_invitee_ids" do
    test "does not include outside collaboratos or org members with repository invitations" do
      org = create(:organization, seats: 5, plan: "business")
      repo = create(:private_repository, owner: org)
      outside_collaborator = create(:user)
      invitation = create(:repository_invitation, repository: repo, invitee: outside_collaborator)
      invitation.accept!
      org_member = create(:user)
      org.add_member(org_member, adder: org.admins.first)

      another_repo = create(:private_repository, owner: org)
      new_user = create(:user)
      create(:repository_invitation, repository: another_repo, invitee: org_member)
      create(:repository_invitation, repository: another_repo, invitee: outside_collaborator)
      create(:repository_invitation, repository: another_repo, invitee: new_user)

      ids = org.private_repo_non_collaborator_invitee_ids
      assert_equal 1, ids.count
      assert_includes ids, new_user.id
    end
  end

  context "#default_seats" do
    test "returns seats when seats are greater than plan base units and org plan is not free" do
      org = create(:organization, seats: 10, plan: "business")

      # Business plan base units is 5
      assert_equal 10, org.default_seats
    end

    test "returns all seated member ids count when it's greater than seats and base units and org plan is not free" do
      org = create(:organization, seats: 5, plan: "business")
      repo = create(:private_repository, owner: org)
      7.times do
        create(:repository_invitation, repository: repo, invitee: create(:user))
      end

      # 7 repo invites + 1 repo owner = 8
      assert_equal 8, org.default_seats
    end

    test "ignores org seats when org is free" do
      org = create(:organization, seats: 99, plan: "free")

      # 1 for repo owner
      assert_equal 1, org.default_seats
    end

    test "returns seats when seats are greater than plan base units and the new plan is not free" do
      org = create(:organization, seats: 10, plan: "business")

      default_seats = org.default_seats(new_plan: GitHub::Plan.business_plus)

      # Business plan base units is 5
      assert_equal 10, default_seats
    end

    test "returns plan base units when base units are greater than org seats and the new plan is not free" do
      org = build(:organization, seats: 3, plan: "free")
      org.save(validate: false)

      default_seats = org.default_seats(new_plan: GitHub::Plan.business)

      # Business plan base units is 1
      assert_equal 1, default_seats
    end

    test "ignores org seats when org plan is free and new plan is not" do
      org = create(:organization, seats: 99, plan: "free")

      default_seats = org.default_seats(new_plan: GitHub::Plan.business)

      # Business plan base units is 1
      assert_equal 1, default_seats
    end
  end

  context "#seats_needed_for_collaborators_on" do
    test "returns needed seats accounting for current and pending outside contributors" do
      org = create :organization, seats: 5, plan: "business"
      3.times { org.add_member(create(:user)) }
      existing_email = "existing@example.com"
      org.invite(email: existing_email, inviter: org.admins.first)
      repo = create(:repository, owner: org)
      repo.add_member(create(:user))
      create :repository_invitation, repository: repo, invitee: create(:user), email: nil
      create :repository_invitation, repository: repo, invitee: nil, email: "invitee@example.com"
      create :repository_invitation, repository: repo, invitee: nil, email: existing_email.capitalize

      assert_equal 3, org.seats_needed_for_collaborators_on(repo)
    end

    test "returns 0 for existing private repositories" do
      org = create :organization, seats: 5, plan: "business"
      members = create_list(:user, 5)
      members.each { |member| org.add_member(member) }

      repo = create(:private_repository, owner: org)
      repo.add_member members[0]
      repo.add_member members[1]

      assert_equal 0, org.seats_needed_for_collaborators_on(repo)
    end

    test "accounts for current members as pending invitees to repository" do
      org = create :organization, seats: 5, plan: "business"
      invitee = create(:user)
      4.times { org.add_member(create(:user)) }
      org.add_member(invitee)
      repo = create(:repository, owner: org)
      # this invitation won't be counted since invitee is a member
      create :repository_invitation, repository: repo, invitee: invitee
      # this one will need an extra seat
      create :repository_invitation, repository: repo

      assert_equal 1, org.seats_needed_for_collaborators_on(repo)
    end

    test "always returns zero when billing is delegated to the enterprise and the enterprise does not change" do
      business = create :business, seats: 1

      org = create :enterprise_linked_organization, business: business

      repo = create(:repository, owner: org)
      create :repository_invitation, repository: repo
      create :repository_invitation, repository: repo

      target_repo_org = create :enterprise_linked_organization, business: business

      assert_equal 0, target_repo_org.seats_needed_for_collaborators_on(repo)
    end

    test "returns the repository's filled seats when called on a user with a private repo" do
      repo = create(:private_repository)
      repo.add_member(create(:user))

      assert_equal 1, @user.seats_needed_for_collaborators_on(repo)
    end

    test "takes into account users already associated with the business when calculating required seats" do
      business = create(:business, seats: 1)
      organization = create(:organization, business: business, seats: 1)
      Business.find(business.id) # make business aware of new organization

      repository = create(:private_repository)
      repository.add_member(create(:user))
      repository.add_member(organization.admins.first)

      assert_equal 1, organization.seats_needed_for_collaborators_on(repository)
    end

    test "returns needed seats account for current and pending outside contributers and a pending plan change" do
      org = create :organization, seats: 7, plan: "business"
      5.times { org.add_member(create(:user)) }
      repo = create(:repository, owner: org)
      repo.add_member(create(:user))
      create :repository_invitation, repository: repo
      Billing::PendingPlanChange.create!(user: org, seats: 5, active_on: 1.month.from_now)

      assert_equal 2, org.seats_needed_for_collaborators_on(repo, pending_cycle: true)
    end
  end

  context "plan=" do
    test "writes the plan attribute" do
      assert_equal GitHub::Plan.free, @user.plan

      @user.plan = "pro"

      assert_equal GitHub::Plan.pro, @user.plan
    end
  end

  context "#billed_organizations_for_marketplace_listing" do
    test "does not include organization the user does not admin" do
      @organization.add_member(@user, action: :read)
      listing = create(:marketplace_listing)
      listing_plan = create(:marketplace_listing_plan, :published, listing: listing)
      plan_subscription = create(:billing_plan_subscription, user: @organization)
      create(:billing_subscription_item, plan_subscription: plan_subscription,
                                     subscribable: listing_plan)

      assert_empty @user.billed_organizations_for_marketplace_listing(listing.id)
    end

    test "includes organization the user admins that has an active subscription" do
      @organization.add_member(@user, action: :admin)
      listing = create(:marketplace_listing)
      listing_plan = create(:marketplace_listing_plan, :published, listing: listing)
      plan_subscription = create(:billing_plan_subscription, user: @organization)
      create(:billing_subscription_item, plan_subscription: plan_subscription,
             subscribable: listing_plan)

      assert_equal [@organization], @user.billed_organizations_for_marketplace_listing(listing.id)
    end

    test "does not include organization that has a cancelled subscription" do
      @organization.add_member(@user, action: :admin)
      listing = create(:marketplace_listing)
      listing_plan = create(:marketplace_listing_plan, :published, listing: listing)
      plan_subscription = create(:billing_plan_subscription, user: @organization)
      create(:billing_subscription_item, :cancelled, plan_subscription: plan_subscription,
                                     subscribable: listing_plan)

      assert_empty @user.billed_organizations_for_marketplace_listing(listing.id)
    end

    test "does not include organization that does not subscribe to the given listing" do
      @organization.add_member(@user, action: :admin)
      listing = create(:marketplace_listing)
      listing_plan = create(:marketplace_listing_plan, :published, listing: listing)
      plan_subscription = create(:billing_plan_subscription, user: @organization)
      create(:billing_subscription_item, plan_subscription: plan_subscription,
                                     subscribable: listing_plan)
      other_listing = create(:marketplace_listing)

      assert_empty @user.billed_organizations_for_marketplace_listing(other_listing.id)
    end

    test "does not include organization that does not subscribe to any listing" do
      @organization.add_member(@user, action: :admin)
      listing = create(:marketplace_listing)

      assert_empty @user.billed_organizations_for_marketplace_listing(listing.id)
    end
  end

  context "#subscription_item_for_marketplace_listing" do
    test "returns nil when user has no subscription for any Marketplace listing" do
      listing = create(:marketplace_listing)

      assert_nil @user.subscription_item_for_marketplace_listing(listing.id)
    end

    test "returns nil when user has no subscription for the given Marketplace listing" do
      listing = create(:marketplace_listing)
      listing_plan = create(:marketplace_listing_plan, :published, listing: listing)
      plan_subscription = create(:billing_plan_subscription, user: @user)
      create(:billing_subscription_item, plan_subscription: plan_subscription,
                                     subscribable: listing_plan)
      other_listing = create(:marketplace_listing)

      assert_nil @user.subscription_item_for_marketplace_listing(other_listing.id)
    end

    test "returns a subscription item when user has an active subscription to the given listing" do
      listing = create(:marketplace_listing)
      listing_plan = create(:marketplace_listing_plan, :published, listing: listing)
      plan_subscription = create(:billing_plan_subscription, user: @user)
      subscription_item = create(:billing_subscription_item, plan_subscription: plan_subscription,
                                                         subscribable: listing_plan)

      assert_equal subscription_item, @user.subscription_item_for_marketplace_listing(listing.id)
    end

    test "returns nil when user has a cancelled subscription to the given Marketplace listing" do
      listing = create(:marketplace_listing)
      listing_plan = create(:marketplace_listing_plan, :published, listing: listing)
      plan_subscription = create(:billing_plan_subscription, user: @user)
      create(:billing_subscription_item, :cancelled, plan_subscription: plan_subscription,
                                     subscribable: listing_plan)

      assert_nil @user.subscription_item_for_marketplace_listing(listing.id)
    end
  end

  context "plan subscription" do
    test "destroyed when the user is destroyed" do
      plan_subscription = create(:billing_plan_subscription, :zuora)
      plan_subscription.user.reload
      plan_subscription.user.destroy

      assert_raises ActiveRecord::RecordNotFound do
        plan_subscription.reload
      end
    end

    test "create when external subscription not present" do
      only = [SynchronizePlanSubscriptionJob, TradeControls::ComplianceCheckJob, ProcessEmailDomainForReputationDataJob]
      user = create(:user, :zuora, plan: :pro)
      create(:billing_plan_subscription, user: user)

      perform_enqueued_jobs(only: only) do
        Billing::PlanSubscription::Synchronizer.expects(:create).once

        user.create_or_update_external_subscription!(force: true)
      end
    end

    test "enqueues job to synchronize general-purpose plan subscription when one doesn't exist" do
      user = create(:credit_card_user)
      assert_nil user.plan_subscription
      refute_predicate user, :external_subscription?

      assert_enqueued_with(
        job: SynchronizePlanSubscriptionJob,
        args: [{ user_id: user.id, plan_name: user.plan_name, purpose: "general" }, user: user]
      ) do
        user.create_or_update_external_subscription!(force: true)
      end
    end

    test "synchronized with plan changes and zuora subscription" do
      synchronize_github_products_to_zuora
      org = @free_org

      zuora_successful_customer_account_creation(org)
      org.reload

      only = [SynchronizePlanSubscriptionJob, UpdateLockedRepositoriesJob]
      perform_enqueued_jobs(only: only) do
        with_live_zuora("zuora_subscription/success_subscription_upgrade_legacy_to_per_seat") do
          diamond_plan = GitHub::Plan.find!("diamond")

          org.plan = diamond_plan
          org.save!
          Billing::PlanSubscription::Transition.activate(org)
          org.reload

          assert org.plan_subscription.present?
          assert org.plan_subscription.zuora_subscription.present?
          zuora_subscription = org.plan_subscription.zuora_subscription
          assert_equal 1, zuora_subscription.active_rate_plans.count
          diamond_plan_rate_plan = zuora_subscription.active_rate_plans.detect do |rate_plan|
            rate_plan[:productName] == diamond_plan.zuora_product_name
          end
          assert diamond_plan_rate_plan

          org.update(plan: GitHub::Plan.business.to_s)
          org.reload
          zuora_subscription = org.plan_subscription.reload.zuora_subscription
          # Non legacy plans support metered products so we see the bump in active rate plans
          assert_equal 7, zuora_subscription.active_rate_plans.count
          team_plan_rate_plan = zuora_subscription.active_rate_plans.detect do |rate_plan|
            rate_plan[:productName] == GitHub::Plan.business.zuora_product_name
          end
          assert team_plan_rate_plan
        end
      end
    end

    test "synchronized with seat changes and zuora subscription" do
      synchronize_github_products_to_zuora
      org = @free_org

      zuora_successful_customer_account_creation(org)
      org.reload

      only = [SynchronizePlanSubscriptionJob, UpdateLockedRepositoriesJob]
      perform_enqueued_jobs(only: only) do
        with_live_zuora("zuora_subscription/success_subscription_upgrade_seats") do
          org.update!(plan: GitHub::Plan.business, seats: 5)
          Billing::PlanSubscription::Transition.activate(org)
          org.reload

          assert org.plan_subscription.present?
          assert org.plan_subscription.zuora_subscription.present?
          zuora_subscription = org.plan_subscription.zuora_subscription
          assert_equal 7, zuora_subscription.active_rate_plans.count
          team_rate_plan = zuora_subscription.active_rate_plans.detect do |rate_plan|
            rate_plan[:productName] == GitHub::Plan.business.zuora_product_name
          end
          assert team_rate_plan
          assert_equal 2, team_rate_plan[:ratePlanCharges].count
          assert_equal 5, team_rate_plan[:ratePlanCharges].sum { |charge| charge[:quantity] }

          org.update(seats: 15)
          zuora_subscription = org.plan_subscription.reload.zuora_subscription
          assert_equal 7, zuora_subscription.active_rate_plans.count
          team_rate_plan = zuora_subscription.active_rate_plans.detect do |rate_plan|
            rate_plan[:productName] == GitHub::Plan.business.zuora_product_name
          end
          assert team_rate_plan
          assert_equal 2, team_rate_plan[:ratePlanCharges].count
          assert_equal 15, team_rate_plan[:ratePlanCharges].sum { |charge| charge[:quantity] }
        end
      end
    end

    test "does not sync subscription when organization belongs to a business but billing hasn't been cleared" do
      org = create(:business_plus_org)
      create(:billing_plan_subscription, :zuora, user: org)

      business = create(:business)
      business.add_organization(org)

      perform_enqueued_jobs only: SynchronizePlanSubscriptionJob  do
        Billing::PlanSubscription::Synchronizer.expects(:update).never
        org.update(seats: 40)
      end
    end

    test "does not update braintree during transform" do
      plan_subscription = @plan_subscription
      user = plan_subscription.user
      user.seats = 10 # ensure we are checking for transformation
      assert_enqueued_jobs 0 do
        Organization.start_transform(user)
        user.update_external_subscription!
      end
    end

    test "does update braintree after transform" do
      owner = @user
      user = create(:user, :zuora, plan: "small")
      create(:billing_plan_subscription, :zuora, user: user)
      user.seats = 10 # ensure we are checking for transformation
      user.reload

      assert_enqueued_with job: SynchronizePlanSubscriptionJob do
        Organization.transform!(user, owner, { plan: "gold" })
      end
    end

    test "synchronized with plan duration changes" do
      user = create(:user, :zuora, plan: GitHub::Plan.pro, plan_duration: User::BillingDependency::MONTHLY_PLAN)
      plan_sub = create(:billing_plan_subscription, :zuora, user: user)

      assert_enqueued_with(
        job: SynchronizePlanSubscriptionJob,
        args: [{ user_id: user.id, plan_name: user.plan.name, purpose: plan_sub.purpose }, user: user]
      ) do
        user.update_attribute(:plan_duration, User::BillingDependency::YEARLY_PLAN)
      end
    end

    test "not sychronized when there are no plan changes" do
      user = create(:user, :zuora, plan: GitHub::Plan.pro)
      create(:billing_plan_subscription, :zuora, user: user)

      assert_enqueued_jobs 0, only: SynchronizePlanSubscriptionJob do
        user.update_attribute(:billing_extra, "nothing much")
      end
    end

    test "not synchronized when skip_update_external_subscription is set to true" do
      org = create(:organization, :zuora, plan: GitHub::Plan.free)
      create(:billing_plan_subscription, :zuora, user: org)

      assert_enqueued_jobs 0, only: SynchronizePlanSubscriptionJob do
        org.skip_update_external_subscription = true
        org.update_attribute(:plan, GitHub::Plan.business)
      end

      assert_enqueued_jobs 1, only: SynchronizePlanSubscriptionJob do
        org.skip_update_external_subscription = false
        org.update_attribute(:plan, GitHub::Plan.business_plus)
      end
    end
  end

  context "#process_zero_charge_transaction" do
    test "moves the billed_on date according to the bill cycle day if it's set" do
      travel_to Date.new(2021, 3, 26) do
        create(:customer_account, user: @user, bill_cycle_day: 25)
        @user.reload

        @user.process_zero_charge_transaction

        assert_equal @user.reload.billed_on, Date.new(2021, 4, 25)
      end
    end

    test "handles moving the billed on date for months that have less days than the bill cycle day" do
      travel_to Date.new(2021, 4, 20) do
        create(:customer_account, user: @user, bill_cycle_day: 31)
        @user.reload

        @user.process_zero_charge_transaction

        assert_equal @user.reload.billed_on, Date.new(2021, 4, 30)
      end
    end

    test "enables account if it should not be disabled" do
      @user.disable!
      refute @user.should_disable?

      @user.process_zero_charge_transaction

      assert @user.reload.enabled?, "User should be enabled"
    end

    test "does not enable account if it should be disabled" do
      create(:customer_account, user: @user)
      @user.disable!(reason: Billing::Public::BillingDisabledReasons::AuthorizationFailure)
      assert @user.reload.should_disable?

      @user.process_zero_charge_transaction

      refute @user.reload.enabled?, "User should still be disabled"
    end

    test "updates the customer's bill cycle day if a customer exists and has no bill cycle day set" do
      create(:customer_account, user: @user)
      @user.reload
      @user.customer.update!(bill_cycle_day: 0)

      @user.process_zero_charge_transaction

      @user.reload
      assert_equal @user.billed_on.day, @user.customer.bill_cycle_day
    end
  end

  context "#days_remaining_in_lfs_cycle" do
    test "is correct for paid monthly plan" do
      Timecop.freeze(GitHub::Billing.timezone.local(2020, 1, 17)) do
        billed_on_date = GitHub::Billing.today + 13.days
        user = create :user, plan: "business", plan_duration: User::BillingDependency::MONTHLY_PLAN, billed_on: billed_on_date

        assert_equal 12, user.days_remaining_in_lfs_cycle
      end
    end

    test "is correct for paid yearly plan" do
      Timecop.freeze(GitHub::Billing.timezone.local(2020, 1, 17)) do
        billed_on_date = GitHub::Billing.today + 45.days
        user = create :user, plan: "business", plan_duration: User::BillingDependency::YEARLY_PLAN, billed_on: billed_on_date

        assert_equal 44, user.days_remaining_in_lfs_cycle
      end
    end

    test "is correct for free plan" do
      Timecop.freeze(GitHub::Billing.timezone.local(2020, 1, 17)) do
        user = @user
        user.build_asset_status!
        asset_created_at = 14.days.ago
        Asset::Status.update_all(created_at: asset_created_at)

        #31 days in month - 14 days used so far
        assert_equal 17, user.days_remaining_in_lfs_cycle
      end
    end

    test "is correct for free users that use the created_at of the status to base reset date calculations" do
      # The state needed to trip this test is as follows:
      #
      # Free plan
      # Have the `day` of the date the asset status was created be greater than todays day
      # Have the date built with todays date, substituting the `day` from above - 1.month be less than the
      #   created_at timestamp on the asset status.
      #
      # Previously a helper method returned a TimeWithZone object in this scenario, which does not support
      # subtracting a date.
      travel_to(::GitHub::Billing.timezone.local(2020, 2, 25)) do
        user = @user
        user.build_asset_status!
        Asset::Status.update_all(created_at: DateTime.new(2020, 01, 31, 10, 22, 44))

        # Days until the end of Feb in this leap year
        assert_equal 4, user.days_remaining_in_lfs_cycle
      end
    end
  end

  context "#first_day_in_lfs_cycle" do
    test "is nil if user has no Asset::Status and doesn't pay" do
      assert_nil @user.first_day_in_lfs_cycle
    end

    test "is based on Asset::Status created_at if on free plan" do
      travel_to(Time.zone.now) do
        user = @user
        user.new_or_asset_status.save!
        user.reload

        assert_equal user.new_or_asset_status.created_at.in_billing_timezone.to_date, user.first_day_in_lfs_cycle
      end
    end

    test "first_day_in_lfs_cycle with invalid date" do
      user = @user
      user.build_asset_status!
      Asset::Status.update_all(created_at: Time.local(2014, 10, 31))

      travel_to(Time.local(2015, 11)) do
        assert_match /\A2015-10-30T/, user.first_day_in_lfs_cycle.xmlschema
      end
    end

    test "first_day_in_lfs_cycle with recent invalid date" do
      user = @user
      user.build_asset_status!
      Asset::Status.update_all(created_at: GitHub::Billing.timezone.local(2015, 10, 31))

      travel_to(GitHub::Billing.timezone.local(2015, 11)) do
        assert_match /\A2015-10-31T/, user.first_day_in_lfs_cycle.xmlschema
      end
    end

    test "is correct for paid monthly plan" do
      travel_to(Time.local(2015, 11)) do
        billed_on_date = Date.new(2018, 1, 1)
        user = create :user, plan: "business", plan_duration: User::BillingDependency::MONTHLY_PLAN, billed_on: billed_on_date
        assert_equal billed_on_date - 1.month, user.first_day_in_lfs_cycle
      end
    end

    test "is correct for paid yearly plan" do
      travel_to(Time.local(2015, 11)) do
        billed_on_date = Date.new(2018, 1, 1)
        user = create :user, plan: "business", plan_duration: User::BillingDependency::YEARLY_PLAN, billed_on: billed_on_date
        assert_equal billed_on_date - 1.year, user.first_day_in_lfs_cycle
      end
    end

    test "is based on start date if invoiced and current month is before start date month" do
      billing_start_date = Date.new(1995, 9, 15)
      expected = Date.new(2017, 9, 15)
      travel_to(Time.local(2018, 1, 31)) do
        user = create :user, plan: "business", plan_duration: User::BillingDependency::YEARLY_PLAN, billing_type: "invoice"
        create(:billing_plan_subscription, user: user, billing_start_date: billing_start_date)
        assert_equal expected, user.first_day_in_lfs_cycle
      end
    end

    test "is based on start date if invoiced and current month is after start date month" do
      billing_start_date = Date.new(1995, 9, 15)
      expected = Date.new(2018, 9, 15)
      travel_to(Time.local(2018, 12, 31)) do
        user = create :user, plan: "business", plan_duration: User::BillingDependency::YEARLY_PLAN, billing_type: "invoice"
        create(:billing_plan_subscription, user: user, billing_start_date: billing_start_date)
        assert_equal expected, user.first_day_in_lfs_cycle
      end
    end

    test "is based on start date if invoiced and first day of cycle" do
      billing_start_date = Date.new(1995, 9, 15)
      expected = Date.new(2018, 9, 15)
      travel_to(GitHub::Billing.timezone.local(2018, 9, 15)) do
        user = create :user, plan: "business", plan_duration: User::BillingDependency::YEARLY_PLAN, billing_type: "invoice"
        create(:billing_plan_subscription, user: user, billing_start_date: billing_start_date)
        assert_equal expected, user.first_day_in_lfs_cycle
      end
    end

    test "is based on start date if invoiced and last day of cycle" do
      billing_start_date = Date.new(1995, 9, 15)
      expected = Date.new(2017, 9, 15)
      travel_to(Time.local(2018, 9, 14)) do
        user = create :user, plan: "business", plan_duration: User::BillingDependency::YEARLY_PLAN, billing_type: "invoice"
        create(:billing_plan_subscription, user: user, billing_start_date: billing_start_date)
        assert_equal expected, user.first_day_in_lfs_cycle
      end
    end

    test "falls back to yearly plan calculation if invoiced without billing start date" do
      travel_to(Time.local(2015, 11)) do
        billed_on_date = Date.new(2018, 1, 1)
        user = create(:user, plan: "business", plan_duration: User::BillingDependency::YEARLY_PLAN,
                      billed_on: billed_on_date, billing_type: "invoice")
        assert_equal billed_on_date - 1.year, user.first_day_in_lfs_cycle
      end
    end
  end

  context "#reset_data_packs" do
    test "resets data pack count to zero, if user has an asset status" do
      user = create :user, plan: "small"
      Asset::Status.create! owner: user, asset_packs: 3
      user.reset_data_packs

      assert_equal 0, user.data_packs
    end

    test "doesn't explode if user has no asset status" do
      user = create :user, plan: "small"
      assert_nil user.asset_status
      user.reset_data_packs
    end
  end

  context "#update_plan_with_data_packs" do
    test "creates a external subscription for user without one" do
      user = create(:user, plan: GitHub::Plan.free)
      create(:asset_status, owner: user, asset_packs: 1)

      Billing::PlanSubscription::Transition.expects(:activate).with(user, purpose: :general)

      user.update_plan_with_data_packs

      assert_equal "free_with_addons", user.plan.name
    end

    test "schedules a subscription synchronization for user who already has one" do
      plan_subscription = create(:billing_plan_subscription, :zuora, user: create(:user, plan: GitHub::Plan.pro))
      user = plan_subscription.user
      create(:asset_status, owner: user, asset_packs: 3)

      assert_enqueued_with(
        job: SynchronizePlanSubscriptionJob,
        args: [{ user_id: user.id, plan_name: user.plan.name, purpose: plan_subscription.purpose }, user: user],
      ) do
        user.update_plan_with_data_packs
      end
    end

    test "downgrades the plan to free if user is removing all data packs, there are no subscription items, and the current plan is on free_with_addons" do
      plan_subscription = create(:billing_plan_subscription, :zuora, user: create(:user, plan: GitHub::Plan.free_with_addons))
      user = plan_subscription.user
      create(:asset_status, owner: user, asset_packs: 0)

      assert_enqueued_with(
        job: SynchronizePlanSubscriptionJob,
        args: [{ user_id: user.id, plan_name: "free", purpose: plan_subscription.purpose }, user: user],
      ) do
        user.update_plan_with_data_packs
      end

      assert_equal GitHub::Plan.free, user.plan
    end

    test "does not create zuora subscription if entire plan is covered by coupon" do
      synchronize_github_products_to_zuora
      user = create :credit_card_user, plan: "small"
      create :asset_status, owner: user, asset_packs: 1
      user.redeem_coupon create :coupon, discount: 20, duration: 365

      user.update_plan_with_data_packs
      refute user.reload.zuora_subscription?, "User should not have a zuora subscription"
    end
  end

  context "#move_billed_on" do
    test "yearly 2 to today plus a year with old billed_on" do
      Time.use_zone "Australia/Melbourne" do
        user = create :user, plan: "small", plan_duration: User::BillingDependency::YEARLY_PLAN, billed_on: GitHub::Billing.today
        assert_equal GitHub::Billing.today + 1.year, move_billed_on(user, GitHub::Billing.now)
      end
    end
  end

  test "card_expired? is true for expiration dates in the past, false otherwise" do
    user = create :credit_card_user
    today = GitHub::Billing.today

    one_year_from_now = today + 1.year
    user.payment_method.expiration_month = one_year_from_now.month
    user.payment_method.expiration_year = one_year_from_now.year
    refute user.card_expired?

    user.payment_method.expiration_month = today.month
    user.payment_method.expiration_year = today.year
    refute user.card_expired?

    one_month_ago = today - 1.month
    user.payment_method.expiration_month = one_month_ago.month
    user.payment_method.expiration_year = one_month_ago.year
    assert user.card_expired?
  end

  context "#card_expiring_in_less_than_three_weeks?" do
    test "true when credit card is expiring in less than three weeks" do
      @credit_card_user.payment_method.update \
        expiration_month: 7,
        expiration_year: 2016

      travel_to(GitHub::Billing.timezone.parse("June 15 2016")) do
        assert @credit_card_user.card_expiring_in_less_than_three_weeks?
      end
    end

    test "false when payment method is paypal" do
      user = create(:paypal_user)

      refute user.card_expiring_in_less_than_three_weeks?
    end
  end

  context "#new_billed_on" do
    test "monthly defaults to today plus a month" do
      on_date(2014, 8, 30) do
        # Please `/page kasima it's happening` if this test fails for you in CI. He is on-call
        # for this test.
        # This test will currently fail if the local date differs from the date in the
        # Pacific timezone.
        assert_equal GitHub::Billing.today + 1.month, new_billed_on(@user, Date.today)
      end
    end

    test "yearly defaults to today plus a year" do
      @user.assign_attributes(plan_duration: User::BillingDependency::YEARLY_PLAN)
      assert_equal GitHub::Billing.today + 1.year, new_billed_on(@user, GitHub::Billing.today)
    end

    test "beginning of the month" do
      assert_equal Date.new(2014, 2, 1), new_billed_on(@user, Date.new(2014, 1, 1))
    end

    test "middle of the month" do
      assert_equal Date.new(2014, 2, 15), new_billed_on(@user, Date.new(2014, 1, 15))
    end

    test "end of the month, long -> long" do
      assert_equal Date.new(2014, 8, 31), new_billed_on(@user, Date.new(2014, 7, 31))
    end

    test "end of the month, long -> long across years" do
      assert_equal Date.new(2014, 1, 31), new_billed_on(@user, Date.new(2013, 12, 31))
    end

    test "end of the month, feb -> long" do
      assert_equal Date.new(2014, 3, 28), new_billed_on(@user, Date.new(2014, 2, 28))
    end

    test "end of the month, short -> long" do
      assert_equal Date.new(2014, 5, 30), new_billed_on(@user, Date.new(2014, 4, 30))
    end

    test "end of the month, long -> feb" do
      assert_equal Date.new(2014, 2, 28), new_billed_on(@user, Date.new(2014, 1, 29))
      assert_equal Date.new(2014, 2, 28), new_billed_on(@user, Date.new(2014, 1, 30))
      assert_equal Date.new(2014, 2, 28), new_billed_on(@user, Date.new(2014, 1, 31))
    end

    test "end of the month, long -> leap year" do
      assert_equal Date.new(2016, 3, 28), new_billed_on(@user, Date.new(2016, 2, 28))
      assert_equal Date.new(2016, 3, 29), new_billed_on(@user, Date.new(2016, 2, 29))
    end
  end

  context "#update_customer" do
    test "does not run the job if username is not changed" do
      assert_enqueued_jobs 0, only: UpdateExternalCustomerJob do
        create :customer_account
      end
    end

    test "updates the customer first_name in braintree" do
      account = create :customer_account
      assert_enqueued_with(job: UpdateExternalCustomerJob, args: [account.customer]) do
        account.user.update_attribute :login, "foobar"
      end
    end

    test "updates the customer first_name in zuora" do
      account = create :customer_account, :zuora
      assert_enqueued_with(job: UpdateExternalCustomerJob, args: [account.customer]) do
        account.user.update_attribute :login, "foobar"
      end
    end
  end

  context "#billing_users" do
    test "returns an array of self for a user" do
      user = create :user, plan: "small"
      assert_equal [user], user.billing_users
    end

    test "returns an array of self for an organization" do
      assert_empty @organization.billing_managers
      assert_equal [@organization], @organization.billing_users
    end
  end

  context "#next_charge_amount" do
    test "returns payment amount less balance when a credit balance exists" do
      plan_subscription = create(
        :billing_plan_subscription,
        :zuora,
        balance_in_cents: -10_00,
        user: create(:user, :zuora, plan: GitHub::Plan.small),
      )
      user = plan_subscription.user

      assert_equal 2, user.next_charge_amount
    end

    test "returns the past-due balance when a subscription is past-due" do
      plan_subscription = create(
        :billing_plan_subscription,
        :zuora,
        balance_in_cents: 12_00,
        user: create(:user, :zuora, plan: GitHub::Plan.small, billing_attempts: 1, billed_on: GitHub::Billing.today - 2.days),
      )
      user = plan_subscription.user
      user.plan_subscription.stubs(:active?).returns(true)

      assert_equal 12, user.next_charge_amount
    end

    test "never returns negative" do
      plan_subscription = create(
        :billing_plan_subscription,
        :zuora,
        balance_in_cents: -10_00,
        user: create(:user, :zuora, plan: GitHub::Plan.micro),
      )
      user = plan_subscription.user

      assert_equal 0, user.next_charge_amount
    end

    test "returns balance if user has an active subscription" do
      synchronize_github_products_to_zuora
      with_live_zuora("zuora/use_balance_when_active_subscription") do
        user = create(
          :user, plan: "pro",
          plan_duration: User::BillingDependency::MONTHLY_PLAN
        )

        zuora_successful_customer_account_creation(user)
        user.reload

        plan_subscription = user.plan_subscription

        Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription).create

        assert plan_subscription.active?
        assert_equal user.balance, user.next_charge_amount
        assert_equal 0, user.next_charge_amount
      end
    end

    test "returns payment amount if user doesn't have an active subscription" do
      user = create(
        :user, plan: "pro",
        plan_duration: User::BillingDependency::MONTHLY_PLAN
      )

      plan_subscription = Billing::PlanSubscription.create \
        customer: user.customer,
        user: user,
        zuora_subscription_number: nil

      refute plan_subscription.active?
      refute user.payment_amount.zero?

      assert_equal user.payment_amount, user.next_charge_amount
      assert_equal user.plan.cost, user.next_charge_amount
    end
  end

  context "#per_seat_plan_only" do
    test "returns true for free organization" do
      assert @free_org.per_seat_plan_only?
    end

    test "returns false for organizations on per repo" do
      assert_predicate @organization.plan, :per_repository?
      refute @organization.per_seat_plan_only?
    end

    test "returns true for organizations on per seat" do
      org = create :organization, plan: GitHub::Plan.business
      assert org.per_seat_plan_only?
    end

    test "returns false for users" do
      refute @user.per_seat_plan_only?
    end
  end

  test "can change_plan_to?" do
    user = @user
    Billing::ChangeSubscription.expects(:can_perform?).with(user, plan: "pro", actor: user).returns(true)
    assert user.can_change_plan_to? "pro"

    somebody = create(:user)
    Billing::ChangeSubscription.expects(:can_perform?).with(user, plan: "pro", actor: somebody).returns(false)
    refute user.can_change_plan_to? "pro", actor: somebody
  end

  test "can dun_subscription with message" do
    Billing::DunSubscription.expects(:perform).with(@user, message: "stoppp")
    @user.dun_subscription "stoppp"
  end

  context "#has_unlimited_seats?" do
    context "coupons" do
      test "ordinary org doesn't have unlimited seats" do
        org = create(:organization, plan: :business, seats: 5)
        refute org.has_unlimited_seats?
      end

      test "dollar off coupon org doesn't have unlimited seats" do
        org = create(:organization, plan: :business, seats: 5)
        org.redeem_coupon create :coupon, discount: 25, duration: 365
        refute org.has_unlimited_seats?
      end

      test "50% off org doesn't have unlimited seats" do
        org = create(:organization, plan: :business, seats: 5)
        org.redeem_coupon create :coupon, discount: 0.5, duration: 365
        refute org.has_unlimited_seats?
      end

      test "100% off org has unlimited seats" do
        org = create(:organization, plan: :business, seats: 5)
        org.redeem_coupon create :coupon, discount: 1, duration: 365
        assert org.has_unlimited_seats?
      end
    end

    context "business organizations" do
      test "returns false if the organization is not part of a business" do
        refute @organization.has_unlimited_seats?
      end

      test "returns false if the organization is part of a business but the business is not unlimited" do
        @business.add_organization(@organization)
        refute @organization.has_unlimited_seats?
      end

      test "returns false if the organization is part of a business on a trial" do
        @business.add_organization(@organization)
        @business.customer.update! metered_ghe: true
        @business.update!(trial_expires_at: 1.day.from_now)
        @organization.reload

        assert_predicate @business, :metered_plan?
        assert_predicate @business, :trial?

        refute @organization.has_unlimited_seats?
      end

      test "returns true if the organization is part of a metered plan business" do
        @business.add_organization(@organization)
        @business.customer.update! metered_ghe: true
        @organization.reload

        assert_predicate @business, :metered_plan?
        refute_predicate @business, :trial?

        assert @organization.has_unlimited_seats?
      end
    end
  end

  context "#next_billing_date" do
    test "returns billed_on if billed_on is after today" do
      @credit_card_user.update_attribute :billed_on, GitHub::Billing.timezone.local(2016, 8, 10).to_billing_date

      travel_to(GitHub::Billing.timezone.local(2016, 7, 10)) do
        # NB: using billing_dependency's version, defaults to today with no subscription
        assert_equal "2016-08-10", @credit_card_user.next_billing_date.strftime("%F")
      end
    end

    test "returns today if billed_on is in the past" do
      @credit_card_user.update_attribute :billed_on, GitHub::Billing.timezone.local(2015, 5, 5).to_billing_date

      travel_to(GitHub::Billing.timezone.local(2016, 7, 10)) do
        # NB: using billing_dependency's version, defaults to today with no subscription
        assert_equal "2016-07-10", @credit_card_user.next_billing_date.strftime("%F")
      end
    end

    test "returns today if billed_on is nil" do
      @credit_card_user.update_attribute :billed_on, nil

      travel_to(GitHub::Billing.timezone.local(2016, 7, 10)) do
        # NB: using billing_dependency's version, defaults to today with no subscription
        assert_equal "2016-07-10", @credit_card_user.next_billing_date.strftime("%F")
      end
    end
  end

  context "#next_billing_date(with_dunning: true)" do
    test "returns the upcoming billing date if not past due" do
      travel_to("2016-10-01 12:00:00 PDT") do
        user = create :user, plan: "business"
        user.billed_on = GitHub::Billing.today + 1.week

        assert_equal Date.new(2016, 10, 8), user.next_billing_date(with_dunning: true)
      end
    end

    test "returns a week from the billing date if a billing attempt has been made" do
      travel_to("2016-10-01 12:00:00 PDT") do
        user = create :user, plan: "business"
        user.billed_on = GitHub::Billing.today
        user.billing_attempts = 1

        assert_equal Date.new(2016, 10, 8), user.next_billing_date(with_dunning: true)
      end
    end

    test "returns fifteen days from the billing date if two billing attempts have been made" do
      travel_to("2016-10-01 12:00:00 PDT") do
        user = create :user, plan: "business"
        user.billed_on = GitHub::Billing.today
        user.billing_attempts = 2

        assert_equal Date.new(2016, 10, 16), user.next_billing_date(with_dunning: true)
      end
    end

    test "returns nil if three billing attempts have been made" do
      travel_to("2016-10-01 12:00:00 PDT") do
        user = create :user, plan: "business"
        user.billed_on = Date.today
        user.billing_attempts = 3

        assert_nil user.next_billing_date(with_dunning: true)
      end
    end
  end

  context "#github_plan_next_billing_date" do
    test "returns the next_billing_date when an external subscription is not present" do
      travel_to("2023-08-01 12:00:00 PDT") do
        user = create(:user, plan: "pro", billed_on: Date.today + 1.week)

        refute user.external_subscription?
        assert_equal user.next_billing_date, user.github_plan_next_billing_date
      end
    end

    test "returns next billing date for the pro plan from the external subscription" do
      synchronize_github_products_to_zuora
      travel_to("2023-08-01 12:00:00 PDT") do
        pro = GitHub::Plan.pro
        user = create(:user, plan: pro, billed_on: Date.today)
        create(
          :billing_plan_subscription,
          user: user,
          zuora_subscription_number: "A123456789",
          zuora_subscription_id: "1234567"
        )

        next_billing_date = "2024-08-01"

        uuid = pro.product_uuid(user.plan_duration)

        zuora_sub = attributes_for(:zuora_subscription, :active, ratePlans: [{
          ratePlanCharges: [
            {
              productRatePlanChargeId: uuid.zuora_product_rate_plan_charge_ids[:flat],
              chargedThroughDate: next_billing_date
            }
          ],
        }])
        GitHub.zuorest_client.stubs(:get_subscription).returns(zuora_sub)

        assert user.external_subscription?
        assert_equal Date.parse(next_billing_date), user.github_plan_next_billing_date
      end
    end

    test "returns the correct next billing date for the team plan" do
      synchronize_github_products_to_zuora
      travel_to("2023-08-01 12:00:00 PDT") do
        plan = GitHub::Plan.business
        user = create(:user, plan: plan, billed_on: Date.today)
        create(:billing_plan_subscription, user: user, zuora_subscription_number: "A123456789")

        next_billing_date = "2024-08-01"

        uuid = plan.product_uuid(user.plan_duration)

        zuora_sub = attributes_for(:zuora_subscription, :active, ratePlans: [{
          ratePlanCharges: [
            {
              productRatePlanChargeId: uuid.zuora_product_rate_plan_charge_ids[:unit],
              chargedThroughDate: next_billing_date
            }
          ],
        }])
        GitHub.zuorest_client.stubs(:get_subscription).returns(zuora_sub)

        assert user.external_subscription?
        assert_equal Date.parse(next_billing_date), user.github_plan_next_billing_date
      end
    end

    test "returns the next billing date for the team plan from the cache when available" do
      synchronize_github_products_to_zuora
      travel_to("2023-08-01 12:00:00 PDT") do
        plan = GitHub::Plan.business
        user = create(:user, plan: plan, billed_on: Date.today)
        uuid = plan.product_uuid(user.plan_duration)

        charge_id = uuid.zuora_product_rate_plan_charge_ids[:unit]
        next_billing_date = "2024-08-01"

        rate_plan_charge = attributes_for(
          :zuora_rate_plan_charge,
          productRatePlanChargeId: charge_id,
          chargedThroughDate: next_billing_date
        )
        plan_subscription = create(:billing_plan_subscription, user: user, zuora_subscription_number: "A123456789",
          zuora_rate_plan_charges: { charge_id => { charged_through_date: Date.parse(next_billing_date) } })
        create(:plan_subscription_zuora_rate_plan_charge, plan_subscription: plan_subscription, payload: rate_plan_charge)

        plan_subscription.expects(:external_subscription).never

        assert user.external_subscription?
        assert_equal Date.parse(next_billing_date), user.github_plan_next_billing_date
      end

    end

    test "returns the correct next billing date for the free plan with external subscription" do
      travel_to("2023-08-01 12:00:00 PDT") do
        user = create(:user, plan: "free", billed_on: Date.today)
        create(:billing_plan_subscription, user: user, zuora_subscription_number: "A123456789")

        charge_id = "2c92a0ff60c505db0160d75cba8a331a"
        next_billing_date = "2024-08-01"

        zuora_sub = attributes_for(:zuora_subscription, :active, ratePlans: [{
          ratePlanCharges: [
            { productRatePlanChargeId: charge_id, chargedThroughDate: next_billing_date }
          ],
        }])
        GitHub.zuorest_client.stubs(:get_subscription).returns(zuora_sub)

        assert user.external_subscription?
        assert_equal GitHub::Billing.today, user.github_plan_next_billing_date
      end
    end
  end

  context "#previous_billing_date" do
    test "returns the previous billed_on for monthly plan" do
      billed_on      = GitHub::Billing.timezone.local(2016, 10, 10).to_billing_date
      last_billed_on = billed_on - 1.month
      user = create :credit_card_user, plan_duration: "month"
      user.update_attribute :billed_on, billed_on

      assert_equal last_billed_on, user.previous_billing_date
    end

    test "returns the previous billed_on for yearly plan" do
      billed_on      = GitHub::Billing.timezone.local(2016, 10, 10).to_billing_date
      last_billed_on = billed_on - 1.year
      user = create :credit_card_user, plan_duration: "year"
      user.update_attribute :billed_on, billed_on

      assert_equal last_billed_on, user.previous_billing_date
    end

    test "returns one cycle from today if no billed_on exists" do
      travel_to(Date.new(2016, 5, 1)) do
        user = create :credit_card_user, plan_duration: "month"
        user.update_attribute :billed_on, nil

        assert_equal GitHub::Billing.today - 1.month, user.previous_billing_date
      end
    end

    test "returns 2 cycles before" do
      billed_on      = GitHub::Billing.timezone.local(2016, 10, 10).to_billing_date
      last_billed_on = billed_on - 2.months
      user = create :credit_card_user, plan_duration: "month"
      user.update_attribute :billed_on, billed_on

      assert_equal last_billed_on, user.previous_billing_date(cycles: 2)
    end
  end

  context "#advanced_metered_cycle_reset_date" do
    test "builds the estimated metered cycle reset date" do
      travel_to(GitHub::Billing.timezone.local(2019, 12, 23)) do
        billed_on = (GitHub::Billing.today - 12.days)
        user = create(:credit_card_user, plan_duration: "month", billed_on: billed_on)
        config = create(:billing_budget, :enforce, owner: user)

        user.expects(:save!).never

        estimated_date = user.advanced_metered_cycle_reset_date
        expected_date = Date.new(2020, 01, user.customer.bill_cycle_day)

        assert_equal expected_date, estimated_date
      end
    end

    test "handles Zuora accounts without a billCycleDay" do
      travel_to(GitHub::Billing.timezone.local(2019, 12, 23)) do
        billed_on = (GitHub::Billing.today - 12.days)
        user = create(:credit_card_user, plan_duration: "month", billed_on: billed_on)
        config = create(:billing_budget, :enforce, owner: user)

        zuora_account = Zuorest::Model::Account.new(billingAndPayment: { billCycleDay: 0 })
        user.stubs(:zuora_account).returns(zuora_account)
        user.customer.update_columns(bill_cycle_day: nil)

        # Lets set the date far in the past, so that we can make sure we're not
        # just "adding a month" to the created_at
        config.update(created_at: GitHub::Billing.today - 62.days)
        created_at = config.created_at

        user.expects(:save!).never

        estimated_date = user.advanced_metered_cycle_reset_date
        expected_date = Date.new(2020, 01, created_at.day)

        assert_equal expected_date, estimated_date
      end
    end
  end

  context "#advance_metered_cycle_reset_date!" do
    test "returns early without changing date, if has a billed_on in future" do
      travel_to(GitHub::Billing.timezone.local(2019, 12, 23)) do
        billed_on = (GitHub::Billing.today + 1.week)
        user = create(:credit_card_user, plan_duration: "month", billed_on: billed_on)

        assert_no_changes -> { user.billed_on } do
          user.advance_metered_cycle_reset_date!
        end
      end
    end

    test "uses zuora subscription charged_through_date if present and have active rate plans" do
      synchronize_github_products_to_zuora

      travel_to(GitHub::Billing.timezone.local(2017, 9, 25)) do
        FakeZuora.mock
        zuora_user = create(:credit_card_user, plan: :pro, plan_duration: "year", billed_on: GitHub::Billing.today - 1.day)
        # Setting the bill cycle day here to match expectation. Because the charged through date is 23rd of the month
        # We can assume the bill cycle date is that date
        zuora_user.customer.update(bill_cycle_day: 23)
        create(:billing_plan_subscription, user: zuora_user)
        product = GitHub::Plan.pro.product_uuid("year")

        raw_zuora_sub = attributes_for(:zuora_subscription, :active, ratePlans: [{
          productId: product.zuora_product_id,
          productRatePlanId: product.zuora_product_rate_plan_id,
          productName: "GitHub Developer Plan",
          ratePlanCharges: [
            attributes_for(:zuora_rate_plan_charge, effectiveEndDate: nil, chargedThroughDate: nil),
            attributes_for(:zuora_rate_plan_charge, effectiveEndDate: nil, chargedThroughDate: "2018-03-23", billingPeriod: "Annual"),
          ],
        }])

        GitHub.zuorest_client.expects(:get_subscription).with("test").returns(raw_zuora_sub)
        zuora_sub = Billing::Zuora::Subscription.find("test")

        ::Billing::PlanSubscription.any_instance.expects(:zuora_subscription).returns(zuora_sub)
        zuora_user.advance_metered_cycle_reset_date!

        # A yearly user, but the next "billed_on" for metered_billing will
        # be in the upcoming month, with the same day as the charged through date
        assert_equal Date.new(2018, 03, 23), zuora_user.billed_on
        assert_equal GitHub::Billing.timezone.local(2017, 10, 23), zuora_user.next_metered_billing_cycle_starts_at
      end
    end

    test "uses the zuora account's bill cycle in current month if in future and if no active rate plans" do
      travel_to(GitHub::Billing.timezone.local(2019, 04, 10)) do
        user = create(:credit_card_user, plan_duration: "month", billed_on: GitHub::Billing.timezone.local(2019, 03, 31).to_billing_date)
        zuora_successful_customer_account_creation(user)
        user.reload
        user.customer.update(bill_cycle_day: user.billed_on.day)
        with_live_zuora("zuora/advance_metered_cycle_with_zuora_account") do
          external_account = user.zuora_account

          user.advance_metered_cycle_reset_date!
          user.reload

          assert_equal 30, external_account[:billingAndPayment][:billCycleDay]
          assert_equal Date.new(2019, 04, 30), user.billed_on
          assert_equal GitHub::Billing.timezone.local(2019, 04, 30), user.next_metered_billing_cycle_starts_at
        end
      end
    end

    test "uses the zuora account's bill cycle day in next month if day has passed and if no active rate plans" do
      travel_to(GitHub::Billing.timezone.local(2019, 01, 31)) do
        user = create(:credit_card_user, plan_duration: "month", billed_on: GitHub::Billing.today - 1.day)
        zuora_successful_customer_account_creation(user)
        user.reload
        user.customer.update(bill_cycle_day: user.billed_on.day)
        with_live_zuora("zuora/advance_metered_cycle_with_zuora_account") do
          external_account = user.zuora_account

          user.advance_metered_cycle_reset_date!
          user.reload

          assert_equal 30, external_account[:billingAndPayment][:billCycleDay]
          assert_equal Date.new(2019, 02, 28), user.billed_on
          assert_equal GitHub::Billing.timezone.local(2019, 02, 28), user.next_metered_billing_cycle_starts_at
        end
      end
    end

    test "uses the budget.created_at if no zuora account or active rate plans" do
      travel_to(GitHub::Billing.timezone.local(2019, 12, 23)) do
        billed_on = (GitHub::Billing.today - 12.days)
        user = create(:credit_card_user, plan_duration: "month", billed_on: billed_on)
        user.customer.update_columns(bill_cycle_day: nil)
        config = create(:billing_budget, :enforce, owner: user)

        # Lets set the date far in the past, so that we can make sure we're not
        # just "adding a month" to the created_at
        config.update(created_at: GitHub::Billing.today - 62.days)
        created_at = config.created_at

        user.advance_metered_cycle_reset_date!

        refute_equal 23, created_at.day
        refute_equal 23, user.billed_on.day

        assert_equal Date.new(2020, 01, created_at.day), user.reload.billed_on
      end
    end

    test "does not error if the advanced date falls outside last day of month" do
      travel_to(GitHub::Billing.timezone.local(2019, 1, 30)) do
        user = create(:credit_card_user, plan_duration: "month", billed_on: GitHub::Billing.today - 1.week)
        create(:billing_budget, owner: user, created_at: GitHub::Billing.timezone.local(2018, 01, 29))

        user.advance_metered_cycle_reset_date!

        assert_equal Date.new(2019, 2, user.customer.bill_cycle_day), user.reload.billed_on
      end
    end
  end

  context "#cancel_billing" do
    test "enqueues CloseOutZuoraSubscriptionJob for the plan subscription" do
      plan_subscription = create(:billing_plan_subscription, :zuora)
      user = plan_subscription.user

      assert_enqueued_with(job: CloseOutZuoraSubscriptionJob) do
        user.cancel_billing
      end
    end

    test "cancels all pending plan changes for the business" do
      plan_subscription = create(:billing_plan_subscription, :zuora)
      user = plan_subscription.user
      pending_plan_change = create(:billing_pending_plan_change, :active, user: user)

      user.cancel_billing

      assert pending_plan_change.reload.is_complete?
    end
  end

  context "#suspend_billing" do
    test "enqueues the SuspendPlanSubscriptionJob to suspend the plan subscription" do
      plan_subscription = create(:billing_plan_subscription, :zuora)
      user = plan_subscription.user

      assert_enqueued_with(job: SuspendPlanSubscriptionJob, args: [plan_subscription]) do
        user.suspend_billing
      end
    end
  end

  context "#resume_billing" do
    test "enqueues the ResumePlanSubscriptionJob to unsuspend the plan subscription" do
      plan_subscription = create(:billing_plan_subscription, :zuora)
      user = plan_subscription.user

      assert_enqueued_with(job: ResumePlanSubscriptionJob, args: [plan_subscription]) do
        user.resume_billing
      end
    end
  end

  def new_billed_on(user, transaction_date)
    user.send :new_billed_on, transaction_date
  end

  def move_billed_on(user, transaction_created_at)
    user.send :move_billed_on, create(:billing_transaction, created_at: transaction_created_at)
    user.billed_on
  end

  test "a user is billable?" do
    user = User.new
    assert user.billable?
  end

  context "#past_due" do
    test "returns false if on the free plan" do
      user = @user

      assert_predicate user.plan, :free?
      refute user.past_due?
    end

    test "returns true if the billed on is nil" do
      @user.assign_attributes(billed_on: nil, plan: GitHub::Plan.micro)
      assert @user.past_due?
    end

    test "returns true if the billed on is in the past or today" do
      @user.assign_attributes(plan: GitHub::Plan.micro)
      # yesterday
      @user.assign_attributes(billed_on: GitHub::Billing.today - 1.day)
      assert @user.past_due?

      # today
      @user.assign_attributes(billed_on: GitHub::Billing.today)
      assert @user.past_due?
    end
  end

  test "#vat_code returns customer.vat_code if it exists" do
    create :customer_account, user: @user
    @user.reload.customer.update_attribute(:vat_code, "LU12345678")
    assert_equal "LU12345678", @user.vat_code
  end

  test "#vat_code falls back to billing_extra if it parses as a vat code" do
    @user.update!(billing_extra: "LU12345678")
    create :customer_account, user: @user
    assert_equal "LU12345678", @user.vat_code
  end

  test "#vat_code is nil when customer.billing_extra does not parse as a vat code" do
    @user.update!(billing_extra: "867-5309")
    create :customer_account, user: @user
    assert_nil @user.vat_code
  end

  context "#has_linked_billing_contact?" do
    test "returns true for linked trade screening record when read billing contact flag disabled" do
      admin = create(:user, :verified)
      create(:account_screening_profile, owner: admin)
      org = create(:organization, admin: admin)
      disable_feature_flag(:read_billing_information_from_contacts, org)
      admin.link_trade_screening_record_to_org(organization: org)

      assert_predicate org, :has_linked_billing_contact?
    end

    test "returns true when org has a linked contact" do
      create :billing_contact, customer: @credit_card_user.customer
      org = create :credit_card_org, admin: @credit_card_user
      assert org.link_billing_contact(actor: @credit_card_user)
      unless org.feature_enabled?(:read_billing_information_from_contacts)
        create :account_screening_profile, owner: @credit_card_user
        assert @credit_card_user.link_trade_screening_record_to_org(organization: org)
      end

      assert_predicate org, :has_linked_billing_contact?
    end

    test "returns true and memoizes result when org has a linked contact" do
      create :billing_contact, customer: @credit_card_user.customer
      org = create :credit_card_org, admin: @credit_card_user
      assert org.link_billing_contact(actor: @credit_card_user)
      unless org.feature_enabled?(:read_billing_information_from_contacts)
        create :account_screening_profile, owner: @credit_card_user
        assert @credit_card_user.link_trade_screening_record_to_org(organization: org)
      end

      assert_predicate org, :has_linked_billing_contact?

      assert_no_queries do
        assert_predicate org, :has_linked_billing_contact?
        assert_predicate org, :has_linked_billing_contact?
      end
    end

    test "returns false when owner is a user" do
      create :billing_contact, customer: @credit_card_user.customer

      refute_predicate @credit_card_user, :has_linked_billing_contact?

      assert_no_queries do
        refute_predicate @credit_card_user, :has_linked_billing_contact?
        refute_predicate @credit_card_user, :has_linked_billing_contact?
      end
    end

    test "returns false when org does not have a linked contact" do
      create :billing_contact, customer: @credit_card_user.customer
      org = create :credit_card_org, admin: @credit_card_user

      refute_predicate org, :has_linked_billing_contact?
    end

    test "returns false and memoizes result when org does not have a linked contact" do
      create :billing_contact, customer: @credit_card_user.customer
      org = create :credit_card_org, admin: @credit_card_user

      refute_predicate org, :has_linked_billing_contact?

      assert_no_queries do
        refute_predicate org, :has_linked_billing_contact?
        refute_predicate org, :has_linked_billing_contact?
      end
    end

    test "returns false and memoizes result when org does not have a customer" do
      create :billing_contact, customer: @credit_card_user.customer
      org = create :organization, admin: @credit_card_user

      refute_predicate org, :has_linked_billing_contact?

      assert_no_queries do
        refute_predicate org, :has_linked_billing_contact?
        refute_predicate org, :has_linked_billing_contact?
      end
    end
  end

  context "#has_linked_billing_contact_to_actor?" do
    test "returns true when trade screening record is linked to org and read billing contact flag disabled" do
      admin = create(:user, :verified)
      create(:account_screening_profile, owner: admin)
      org = create(:organization, admin: admin)
      disable_feature_flag(:read_billing_information_from_contacts, org)
      admin.link_trade_screening_record_to_org(organization: org)

      assert org.has_linked_billing_contact_to_actor?(actor: admin)
    end

    test "does not compare user trade screening record to org billing contact when org has flag enabled but not user" do
      create :billing_contact, customer: @credit_card_user.customer
      create(:account_screening_profile, owner: @credit_card_user)
      org = create(:organization, admin: @credit_card_user)
      enable_feature_flag(:read_billing_information_from_contacts, org)
      disable_feature_flag(:read_billing_information_from_contacts, @credit_card_user)
      assert @credit_card_user.link_trade_screening_record_to_org(organization: org)
      assert org.link_billing_contact(actor: @credit_card_user)
      AccountScreeningProfile.any_instance.expects(:id).never

      assert org.has_linked_billing_contact_to_actor?(actor: @credit_card_user)
    end

    test "returns true when contact is linked to org" do
      create :billing_contact, customer: @credit_card_user.customer
      org = create :credit_card_org, admin: @credit_card_user
      assert org.link_billing_contact(actor: @credit_card_user)
      unless org.feature_enabled?(:read_billing_information_from_contacts)
        create :account_screening_profile, owner: @credit_card_user
        assert @credit_card_user.link_trade_screening_record_to_org(organization: org)
      end

      assert org.has_linked_billing_contact_to_actor?(actor: @credit_card_user)
    end

    test "returns false when contact is not linked to org" do
      create :billing_contact, customer: @credit_card_user.customer
      org = create :credit_card_org, admin: @credit_card_user

      refute org.has_linked_billing_contact_to_actor?(actor: @credit_card_user)
    end

    test "returns false when contact is not persisted" do
      org = create :credit_card_org, admin: @credit_card_user

      refute org.has_linked_billing_contact_to_actor?(actor: @credit_card_user)
    end

    test "returns false when org doesn't have a customer" do
      org = create :organization, admin: @credit_card_user

      refute org.has_linked_billing_contact_to_actor?(actor: @credit_card_user)
    end

    test "returns false when another's contact is linked to org" do
      user2 = create(:credit_card_user)
      create :billing_contact, customer: @credit_card_user.customer
      create :billing_contact, customer: user2.customer
      org = create :credit_card_org, admin: user2

      refute org.has_linked_billing_contact_to_actor?(actor: @credit_card_user)
    end
  end

  context "#link_billing_contact" do
    test "returns true after linking user billing contact to org" do
      create :billing_contact, customer: @credit_card_user.customer
      org = create :credit_card_org, admin: @credit_card_user
      enable_feature_flag(:read_billing_information_from_contacts, org)

      assert org.link_billing_contact(actor: @credit_card_user)

      assert_predicate org, :has_linked_billing_contact?
    end

    test "returns true and resets memoization after linking user billing contact to org" do
      create :billing_contact, customer: @credit_card_user.customer
      org = create :credit_card_org, admin: @credit_card_user

      refute org.has_linked_billing_contact_to_actor?(actor: @credit_card_user)
      assert_query_count(1) do
        refute_predicate org, :has_linked_billing_contact?
        refute_predicate org, :has_linked_billing_contact?
        refute_predicate org, :has_linked_billing_contact?
      end

      assert org.link_billing_contact(actor: @credit_card_user)
      unless org.feature_enabled?(:read_billing_information_from_contacts)
        create :account_screening_profile, owner: @credit_card_user
        assert @credit_card_user.link_trade_screening_record_to_org(organization: org)
      end

      assert org.has_linked_billing_contact_to_actor?(actor: @credit_card_user)
      assert_query_count(org.feature_enabled?(:read_billing_information_from_contacts) ? 2 : 4) do
        assert_predicate org, :has_linked_billing_contact?
        assert_predicate org, :has_linked_billing_contact?
        assert_predicate org, :has_linked_billing_contact?
      end
    end

    test "returns true after creating an org customer and linking user billing contact to org" do
      create :billing_contact, customer: @credit_card_user.customer
      org = create :organization, admin: @credit_card_user
      enable_feature_flag(:read_billing_information_from_contacts, org)
      refute_predicate org.customer, :present?

      assert org.link_billing_contact(actor: @credit_card_user)

      assert_predicate org.customer, :present?
      assert_predicate org, :has_linked_billing_contact?
      assert org.has_linked_billing_contact_to_actor?(actor: @credit_card_user)
    end

    test "returns true after unlinking admin1s billing contact and linking admin2s billing contact to org" do
      admin2 = create :credit_card_user
      create :billing_contact, customer: @credit_card_user.customer
      create :billing_contact, customer: admin2.customer
      org = create :credit_card_org, admin: @credit_card_user
      org.add_admin admin2
      enable_feature_flag(:read_billing_information_from_contacts, org)

      # link first admin's billing contact to org
      assert org.link_billing_contact(actor: @credit_card_user)

      assert_predicate org, :has_linked_billing_contact?
      assert org.has_linked_billing_contact_to_actor?(actor: @credit_card_user)

      # link second admin's billing contact to org
      assert org.link_billing_contact(actor: admin2)

      assert_predicate org, :has_linked_billing_contact?
      assert org.has_linked_billing_contact_to_actor?(actor: admin2)
    end

    test "returns false if linking user billing contact fails" do
      user = create :user
      org = create :organization
      enable_feature_flag(:read_billing_information_from_contacts, org)

      refute org.link_billing_contact(actor: user)

      refute_predicate org, :has_linked_billing_contact?
    end

    test "returns false if user attempts to link billing contact to another user" do
      refute @credit_card_user.link_billing_contact(actor: @credit_card_user)
    end

    test "returns false if corporate terms org attempts to link billing contact" do
      create :billing_contact, customer: @credit_card_user.customer
      org = create :credit_card_org, :with_corporate_terms, admin: @credit_card_user
      enable_feature_flag(:read_billing_information_from_contacts, org)

      refute org.link_billing_contact(actor: @credit_card_user)
    end
  end

  context "#unlink_billing_contact" do
    test "returns true after unlinking user's own billing contact from org" do
      admin2 = create :credit_card_user
      create :billing_contact, customer: @credit_card_user.customer
      org = create :credit_card_org, admin: @credit_card_user
      org.add_admin admin2
      enable_feature_flag(:read_billing_information_from_contacts, org)
      assert org.link_billing_contact(actor: @credit_card_user)
      assert_predicate org, :has_linked_billing_contact?
      org.remove_member! @credit_card_user

      assert org.unlink_billing_contact(actor: @credit_card_user)

      refute_predicate org, :has_linked_billing_contact?
      refute org.has_linked_billing_contact_to_actor?(actor: @credit_card_user)
    end

    test "returns true after admin1 unlinks admin2s billing contact from org" do
      admin2 = create :credit_card_user
      create :billing_contact, customer: @credit_card_user.customer
      create :billing_contact, customer: admin2.customer
      org = create :organization, admin: @credit_card_user
      org.add_admin admin2
      enable_feature_flag(:read_billing_information_from_contacts, org)

      # link first admin's billing contact to org
      assert org.link_billing_contact(actor: @credit_card_user)
      assert_predicate org, :has_linked_billing_contact?
      assert org.has_linked_billing_contact_to_actor?(actor: @credit_card_user)

      assert org.unlink_billing_contact(actor: admin2)

      refute_predicate org, :has_linked_billing_contact?
      refute org.has_linked_billing_contact_to_actor?(actor: @credit_card_user)
    end

    test "returns true after billing manager unlinks admin's billing contact from org" do
      user = create :credit_card_user
      create :billing_contact, customer: @credit_card_user.customer
      create :billing_contact, customer: user.customer
      org = create :organization, admin: @credit_card_user
      org.billing.add_manager(user, actor: org.admin)
      enable_feature_flag(:read_billing_information_from_contacts, org)

      # link first admin's billing contact to org
      assert org.link_billing_contact(actor: @credit_card_user)
      assert_predicate org, :has_linked_billing_contact?
      assert org.has_linked_billing_contact_to_actor?(actor: @credit_card_user)

      assert org.unlink_billing_contact(actor: user)

      refute_predicate org, :has_linked_billing_contact?
      refute org.has_linked_billing_contact_to_actor?(actor: @credit_card_user)
    end

    test "returns false if unlinking user billing contact fails" do
      create :billing_contact, customer: @credit_card_user.customer
      org = create :credit_card_org, admin: @credit_card_user
      assert org.link_billing_contact(actor: @credit_card_user)
      unless org.feature_enabled?(:read_billing_information_from_contacts)
        create :account_screening_profile, owner: @credit_card_user
        assert @credit_card_user.link_trade_screening_record_to_org(organization: org)
      end
      Billing::ContactLinkManager.stubs(:unlink_contact_from_org).returns(false)

      refute org.unlink_billing_contact(actor: @credit_card_user)

      assert_predicate org, :has_linked_billing_contact?
    end

    test "returns false if user calls unlink_billing_contact" do
      user = create :user

      refute user.unlink_billing_contact(actor: user)
    end
  end

  test "#billing_extra is nil if the column stores a VAT code" do
    @user.update!(billing_extra: "LU12345678")
    create :customer_account, user: @user
    assert_equal "LU12345678", @user.vat_code
    assert_nil @user.billing_extra
  end

  test "#billing_extra can hold things other than a VAT code" do
    @user.update!(billing_extra: "not a vat")
    create :customer_account, user: @user
    assert_nil @user.vat_code
    assert_equal "not a vat", @user.billing_extra
  end

  context "#business_plus?" do
    test "returns true if any org is on business_plus plan" do
      user = create(:organization, plan: "business_plus").user

      assert user.business_plus?
    end

    test "returns false if no orgs are on the business_plus plan" do
      user = create(:organization, plan: "business").user

      refute user.business_plus?
    end

    test "returns true if organization is on the business_plus plan" do
      org = create(:organization, plan: "business_plus")

      assert org.business_plus?
    end

    test "returns true if the user is a billing manager for an org on the business_plus plan" do
      org     = create(:organization, plan: "business_plus")
      billing = Organization::BillingManagement.new(org)
      billing.add_manager(@user, actor: org.admin)

      assert @user.business_plus?
    end

    test "returns true if the user is an outside collaborator in a private repo for an org on the business_plus plan" do
      org  = create(:organization, plan: "business_plus", seats: 10)
      repo = create(:private_repository, owner: org)
      repo.add_member(@user)

      assert @user.business_plus?
    end

    test "business_plus check does not consider orphaned repos" do
      org  = create(:organization, plan: "business_plus", seats: 10)
      repo = create(:private_repository, owner: org)
      repo.add_member(@user)

      # adding an orphaned repo
      repo1 = create(:private_repository)
      repo1.add_member(@user)
      repo1.owner.delete

      assert @user.business_plus?
    end

    test "returns false if the user is an outside collaborator in a public repo for an org on the business_plus plan" do
      org  = create(:organization, plan: "business_plus", seats: 10)
      repo = create(:public_repository, owner: org)
      repo.add_member(@user)

      refute @user.business_plus?
    end

    test "returns false if the user is a guest collaborator in an org on the business_plus plan" do
      repo = create(:private_repository, owner: @emu_org)
      repo.add_team(@emu_team, action: :write)

      assert @guest_collaborator.business_plus?
      refute @guest_collaborator.business_plus_collaborator?
    end unless GitHub.single_business_environment?

    test "returns true if the user is a member of an org on the business_plus plan" do
      org  = create(:organization, plan: "business_plus")
      org.add_member(@user)

      assert @user.business_plus?
    end

    test "returns true if the user is an Enterprise Account owner" do
      owner = @user
      @business.add_owner(owner, actor: @business.owners.first)

      assert owner.business_plus?
    end

    test "returns true if the user is an Enterprise Account billing manager" do
      manager = @user
      @business.billing.add_manager(manager, actor: @business.owners.first)

      assert manager.business_plus?
    end
  end

  context "#owned_accounts" do
    test "includes owned organizations" do
      organization = create(:organization, admin: @user)

      assert_includes @user.owned_accounts, organization
    end

    test "includes user account" do
      assert_same_elements [@user], @user.owned_accounts
    end
  end

  context "#async_adminable_account_has_purchased_app?" do
    test "returns true when user has active subscription to OAuth app" do
      listing = create(:marketplace_listing, :verified)
      listing_plan = create(:marketplace_listing_plan, :published, listing: listing)
      subscription_item = create(:billing_subscription_item, subscribable: listing_plan)
      user = subscription_item.plan_subscription.user

      assert user.async_adminable_account_has_purchased_app?(listing.listable).sync
    end

    test "returns true when user has active subscription to integration" do
      listing = create(:marketplace_listing, :verified, :integration)
      listing_plan = create(:marketplace_listing_plan, :published, listing: listing)
      subscription_item = create(:billing_subscription_item, subscribable: listing_plan)
      user = subscription_item.plan_subscription.user

      assert user.async_adminable_account_has_purchased_app?(listing.listable).sync
    end

    test "returns true when user has canceled subscription to OAuth app" do
      listing = create(:marketplace_listing, :verified)
      listing_plan = create(:marketplace_listing_plan, :published, listing: listing)
      subscription_item = create(:billing_subscription_item, subscribable: listing_plan)
      subscription_item.update_attribute(:quantity, 0)
      user = subscription_item.plan_subscription.user

      assert user.async_adminable_account_has_purchased_app?(listing.listable).sync
    end

    test "returns true when user has canceled subscription to integration" do
      listing = create(:marketplace_listing, :verified, :integration)
      listing_plan = create(:marketplace_listing_plan, :published, listing: listing)
      subscription_item = create(:billing_subscription_item, subscribable: listing_plan)
      subscription_item.update_attribute(:quantity, 0)
      user = subscription_item.plan_subscription.user

      assert user.async_adminable_account_has_purchased_app?(listing.listable).sync
    end

    test "returns true when org has purchased app" do
      plan_subscription = create(:billing_plan_subscription, user: @organization)
      listing = create(:marketplace_listing, :verified, :integration)
      listing_plan = create(:marketplace_listing_plan, :published, listing: listing)
      create(:billing_subscription_item, subscribable: listing_plan, plan_subscription: plan_subscription)

      assert @organization.async_adminable_account_has_purchased_app?(listing.listable).sync
    end

    test "returns true when user is an admin of org that has purchased app" do
      admin = @organization.admin
      plan_subscription = create(:billing_plan_subscription, user: @organization)
      listing = create(:marketplace_listing, :verified, :integration)
      listing_plan = create(:marketplace_listing_plan, :published, listing: listing)
      create(:billing_subscription_item, subscribable: listing_plan, plan_subscription: plan_subscription)

      assert admin.async_adminable_account_has_purchased_app?(listing.listable).sync
    end

    test "returns true when Marketplace listing is delisted after user purchases subscription" do
      listing = create(:marketplace_listing, :verified, :integration)
      listing_plan = create(:marketplace_listing_plan, :published, listing: listing)
      subscription_item = create(:billing_subscription_item, subscribable: listing_plan)
      listing.delist!
      user = subscription_item.plan_subscription.user

      assert user.async_adminable_account_has_purchased_app?(listing.listable).sync
    end

    test "returns false when user is not an admin of org that has purchased app" do
      team = create(:team)
      org = team.organization
      team.add_member(@user)
      plan_subscription = create(:billing_plan_subscription, user: org)
      listing = create(:marketplace_listing, :verified, :integration)
      listing_plan = create(:marketplace_listing_plan, :published, listing: listing)
      create(:billing_subscription_item, subscribable: listing_plan, plan_subscription: plan_subscription)

      refute @user.async_adminable_account_has_purchased_app?(listing.listable).sync
    end

    test "returns false when user does not have subscription to OAuth app" do
      listing = create(:marketplace_listing, :verified)
      listing_plan = create(:marketplace_listing_plan, :published)
      user = @plan_subscription.user
      create(:billing_subscription_item, subscribable: listing_plan)

      refute user.async_adminable_account_has_purchased_app?(listing.listable).sync
    end

    test "returns false when user does not have subscription to integration" do
      listing = create(:marketplace_listing, :verified, :integration)
      listing_plan = create(:marketplace_listing_plan, :published, listing: listing)
      user = @plan_subscription.user
      create(:billing_subscription_item, subscribable: listing_plan)

      refute user.async_adminable_account_has_purchased_app?(listing.listable).sync
    end

    test "returns false when OAuth app is not listed in GitHub Marketplace" do
      purchased_oauth_app = create :oauth_application
      listing = create(:marketplace_listing, :verified, listable: purchased_oauth_app)
      listing_plan = create(:marketplace_listing_plan, :published, listing: listing)
      oauth_app = create(:oauth_application)
      plan_subscription = @plan_subscription
      user = plan_subscription.user
      create(:billing_subscription_item, subscribable: listing_plan, plan_subscription: plan_subscription)

      refute user.async_adminable_account_has_purchased_app?(oauth_app).sync
    end

    test "returns false when integration is not listed in GitHub Marketplace" do
      purchased_integration = create(:integration)
      listing = create(:marketplace_listing, :verified, listable: purchased_integration)
      listing_plan = create(:marketplace_listing_plan, :published, listing: listing)
      integration = create(:integration)
      user = @plan_subscription.user
      create(:billing_subscription_item, subscribable: listing_plan, plan_subscription: @plan_subscription)

      refute user.async_adminable_account_has_purchased_app?(integration).sync
    end
  end

  context "#has_active_subscription_item_for?" do
    test "returns true if user has an active subscription item" do
      plan_subscription = create :billing_plan_subscription, user: @user
      subscription_item = create(:billing_subscription_item,
                                 plan_subscription: plan_subscription,
                                )

      assert @user.reload.has_active_subscription_item_for?([subscription_item.subscribable.id])
    end

    test "returns false if user has no active subscription items" do
      plan = create(:marketplace_listing_plan, :published)
      create(:billing_subscription_item,
        plan_subscription_id: @plan_subscription.id,
        subscribable: plan,
      )
      user = @plan_subscription.user
      other_plan = create(:marketplace_listing_plan, :published)

      refute user.has_active_subscription_item_for?([other_plan.id])
    end
  end

  context "subscription_items relation" do
    test "includes marketplace and Sponsors subscription items whether active or cancelled" do
      sub_item = create(:billing_subscription_item, account: @user)
      sponsors_sub_item = create(:sponsors_subscription_item, :cancelled, account: @user)

      assert_predicate sub_item, :active?
      assert_predicate sponsors_sub_item, :cancelled?

      assert_same_elements [sub_item, sponsors_sub_item], @user.subscription_items
    end

    test "includes subscription items related to customers sponsors-purpose and general-purpose customer" do
      user = create(:credit_card_org, :sponsors_invoiced)
      sub_item = create(:billing_subscription_item, account: user)
      sponsors_sub_item = create(:sponsors_subscription_item, account: user)

      refute_equal sub_item.customer, sponsors_sub_item.customer, "Items should have different customers"

      assert_same_elements [sub_item, sponsors_sub_item], user.subscription_items
    end

    test "does not include subscription item for a different user" do
      sub_item = create(:billing_subscription_item)
      other_user_sub_item = create(:billing_subscription_item)

      refute_equal sub_item.user, other_user_sub_item.user, "Items should have different users"

      assert_same_elements [sub_item], sub_item.user.subscription_items
    end
  end

  context "active_subscription_items relation" do
    test "includes active subscription item on general-purpose plan subscription for the user" do
      plan_subscription = create(:billing_plan_subscription, user: @user)
      subscription_item = create(:billing_subscription_item, plan_subscription: plan_subscription)
      assert_includes @user.active_subscription_items, subscription_item
    end

    test "includes active subscription item on Sponsors-specific plan subscription for the user" do
      plan_subscription = create(:billing_plan_subscription, :sponsors_invoiced)
      subscription_item = create(:sponsors_subscription_item,
        plan_subscription: plan_subscription)
      user = plan_subscription.user
      assert_includes user.active_subscription_items, subscription_item
    end

    test "does not include cancelled subscription item" do
      plan = create(:marketplace_listing_plan, :published)
      subscription_item = create(:billing_subscription_item, :cancelled, plan_subscription_id: @plan_subscription.id,
        subscribable: plan)
      user = @plan_subscription.user
      refute_includes user.active_subscription_items, subscription_item
    end

    test "does not include active subscription item for a different user" do
      subscription_item = create(:billing_subscription_item, plan_subscription: @plan_subscription)
      refute_includes @user.active_subscription_items, subscription_item
    end
  end

  context "#any_active_subscription_items_for_owned_accounts?" do
    test "returns true if user's account has an active subscription item" do
      plan_subscription = create :billing_plan_subscription, user: @user
      subscription_item = create(:billing_subscription_item,
                                 plan_subscription: plan_subscription,
                                )

      assert @user.reload.any_active_subscription_items_for_owned_accounts?(subscription_item.listing)
    end

    test "returns true if org account owned by user has an active subscription item" do
      plan = create(:marketplace_listing_plan, :published)
      plan_subscription = create(:billing_plan_subscription, user: @organization)
      create(:billing_subscription_item,
             plan_subscription_id: plan_subscription.id,
             subscribable: plan,
            )
      admin = @organization.admin

      assert admin.any_active_subscription_items_for_owned_accounts?(plan.listing)
    end

    test "returns false if user's account has no active subscription items" do
      plan = create(:marketplace_listing_plan, :published)
      subscription_item = create(:billing_subscription_item,
        plan_subscription_id: @plan_subscription.id,
        subscribable: plan,
      )
      subscription_item.update_attribute(:quantity, 0)
      user = @plan_subscription.user

      refute user.any_active_subscription_items_for_owned_accounts?(plan.listing)
    end

    test "returns false when user does not have a plan subscription" do
      plan = create(:marketplace_listing_plan, :published)

      refute @user.any_active_subscription_items_for_owned_accounts?(plan.listing)
    end

    test "returns false if org account owned by user has no active subscription items" do
      plan = create(:marketplace_listing_plan, :published)
      plan_subscription = create(:billing_plan_subscription, user: @organization)
      subscription_item = create(:billing_subscription_item,
        plan_subscription_id: plan_subscription.id,
        subscribable: plan,
      )
      subscription_item.update_attribute(:quantity, 0)
      admin = @organization.admin

      refute admin.any_active_subscription_items_for_owned_accounts?(plan.listing)
    end
  end

  context "past_subscription_items relation" do
    test "includes cancelled subscription item on general-purpose plan subscription for the user" do
      plan_subscription = create(:billing_plan_subscription, user: @user)
      subscription_item = create(:billing_subscription_item, :cancelled, plan_subscription: plan_subscription)
      assert_includes @user.past_subscription_items, subscription_item
    end

    test "includes cancelled subscription item on Sponsors-specific plan subscription for the user" do
      plan_subscription = create(:billing_plan_subscription, :sponsors_invoiced)
      subscription_item = create(:sponsors_subscription_item, :cancelled,
        plan_subscription: plan_subscription)
      user = plan_subscription.user
      assert_includes user.past_subscription_items, subscription_item
    end

    test "does not include active subscription item" do
      plan = create(:marketplace_listing_plan, :published)
      subscription_item = create(:billing_subscription_item, plan_subscription_id: @plan_subscription.id,
        subscribable: plan)
      user = @plan_subscription.user
      refute_includes user.past_subscription_items, subscription_item
    end

    test "does not include cancelled subscription item for a different user" do
      subscription_item = create(:billing_subscription_item, :cancelled, plan_subscription: @plan_subscription)
      refute_includes @user.past_subscription_items, subscription_item
    end
  end

  context "#cancel_subscription_items" do
    test "can cancel paid product_uuid subscription items" do
      plan_subscription = create(:billing_plan_subscription, :zuora)
      user = plan_subscription.user
      create :billing_subscription_item, plan_subscription: plan_subscription
      create :billing_subscription_item, :with_product_uuid, plan_subscription: plan_subscription

      assert_equal 2, user.reload.active_subscription_items.count

      perform_enqueued_jobs(only: [RunPendingPlanChangeJob]) do
        user.cancel_subscription_items!
      end

      assert_equal 0, user.reload.active_subscription_items.count
    end

    test "cancels all associated active and paid subscription items" do
      plan_subscription = create(:billing_plan_subscription, :zuora)
      user_with_sponsorship = plan_subscription.user
      create :billing_subscription_item, plan_subscription: plan_subscription
      create :billing_subscription_item, :cancelled, plan_subscription: plan_subscription
      create :billing_subscription_item, :free, plan_subscription: plan_subscription
      create :sponsorship, sponsor: user_with_sponsorship

      assert_equal 3, user_with_sponsorship.reload.active_subscription_items.count

      perform_enqueued_jobs(only: [RunPendingPlanChangeJob]) do
        user_with_sponsorship.cancel_subscription_items!
      end

      assert_equal 1, user_with_sponsorship.reload.active_subscription_items.count
    end

    test "skips all in-app purchased subscription items" do
      plan_subscription = create(:billing_plan_subscription, :zuora)
      user = plan_subscription.user

      create(:billing_subscription_item, :with_product_uuid, :iap, plan_subscription: plan_subscription)

      assert_equal 1, user.reload.active_subscription_items.count

      perform_enqueued_jobs(only: [RunPendingPlanChangeJob]) do
        user.cancel_subscription_items!
      end

      assert_equal 1, user.reload.active_subscription_items.count
    end

    # https://github.com/github/sponsors/issues/2377
    test "cancels locked one-time sponsorship's subscription item" do
      plan_subscription = create(:billing_plan_subscription, :zuora)
      user_with_sponsorship = plan_subscription.user
      tier = create(:sponsors_tier, :approved_sponsors_listing, :one_time)
      sponsorship = create(:sponsorship, tier: tier, sponsor: user_with_sponsorship,
        sponsorable: tier.sponsorable)
      assert_predicate sponsorship, :locked?
      refute_nil sponsorship.subscription_item
      assert_predicate sponsorship.subscription_item, :active?

      assert_difference(-> { user_with_sponsorship.reload.active_subscription_items.count }, -1) do
        perform_enqueued_jobs(only: [RunPendingPlanChangeJob]) do
          user_with_sponsorship.cancel_subscription_items!
        end
      end

      assert_predicate sponsorship.reload, :active?, "should not cancel related sponsorship that will be deactivated on expiration"
      refute_predicate sponsorship.subscription_item.reload, :active?
    end

    test "cancels subscription items and associated pending subscription item changes" do
      plan_subscription = create(:billing_plan_subscription, :zuora)
      user = plan_subscription.user
      create :billing_subscription_item, plan_subscription: plan_subscription
      create :billing_subscription_item, subscribable: @product_uuid, plan_subscription: plan_subscription, quantity: 1
      pending_plan_change = create(:billing_pending_plan_change, user: user)
      create :billing_pending_subscription_item_change, :cancellation, subscribable: @product_uuid, pending_plan_change: pending_plan_change

      assert_equal 2, user.reload.active_subscription_items.count
      assert_equal 1, user.pending_subscription_item_changes.count

      user.cancel_subscription_items!(force: true, skip_sync: true)

      assert_equal 0, user.reload.active_subscription_items.count
      assert_equal 0, user.pending_subscription_item_changes.count
    end

    test "cancels subscription items but not associated pending subscription item changes" do
      plan_subscription = create(:billing_plan_subscription, :zuora)
      user = plan_subscription.user
      create :billing_subscription_item, plan_subscription: plan_subscription
      create :billing_subscription_item, :with_product_uuid, plan_subscription: plan_subscription
      pending_plan_change = create(:billing_pending_plan_change, user: user)
      create :billing_pending_subscription_item_change, :billing_product_uuid_subscribable, :cancellation, pending_plan_change: pending_plan_change

      assert_equal 2, user.reload.active_subscription_items.count
      assert_equal 1, user.pending_subscription_item_changes.count

      user.cancel_subscription_items!(force: true, skip_sync: true)

      assert_equal 0, user.reload.active_subscription_items.count
      assert_equal 1, user.pending_subscription_item_changes.count
    end
  end

  context "#recurring_charge" do
    test "re-enables a disabled user with a coupon" do
      user = create :no_credit_card_user,
        :with_billing_locked,
        billed_on: GitHub::Billing.today + 1.week,
        plan: GitHub::Plan.pro

      user.redeem_coupon create(:coupon, discount: 7, expires_at: 2.weeks.ago)

      user.recurring_charge

      refute_predicate user.reload, :disabled?
    end

    test "doesn't run charge with coupon for zuora users" do
      plan_subscription = create :billing_plan_subscription, :zuora
      user = plan_subscription.user

      user.plan_subscription.expects(:retry_charge)
      user.expects(:recurring_charge_with_coupon).never

      user.recurring_charge
    end

    test "retries the charge for zuora subscriptions" do
      plan_subscription = create :billing_plan_subscription, :zuora
      user = plan_subscription.reload.user

      user.plan_subscription.expects(:retry_charge)

      user.recurring_charge
    end
  end

  context "#switch_billing_type_to_invoice" do
    test "switching an organization on monthly duration and plan subscription" do
      org = create :organization, :zuora, plan_duration: User::BillingDependency::MONTHLY_PLAN
      staff = create(:staff_admin_user)

      org.switch_billing_type_to_invoice(staff)

      assert org.invoiced?
      assert_equal 0, org.billing_attempts
      assert User::BillingDependency::YEARLY_PLAN, org.plan_duration
    end
  end

  context "#pending_plan_changes" do
    test "are cleaned up when a user is destroyed" do
      change = create :billing_pending_plan_change, user: @user
      create :billing_pending_subscription_item_change, pending_plan_change: change

      assert_difference "Billing::PendingPlanChange.count", -1 do
        assert_difference " Billing::PendingSubscriptionItemChange.count", -1 do
          @user.destroy
        end
      end
    end
  end

  context "#async_pending_cycle_change" do
    test "mimics behavior of pending_cycle_change" do
      create :billing_pending_plan_change,
        is_complete: true,
        user: @user
      free_trial_change = create :billing_pending_plan_change,
        user: @user
      create :billing_pending_subscription_item_change,
        free_trial: true,
        pending_plan_change: free_trial_change
      change = create :billing_pending_plan_change,
        user: @user
      create :billing_pending_subscription_item_change,
        pending_plan_change: change

      assert_equal @user.pending_cycle_change, @user.async_pending_cycle_change.sync
    end
  end

  context "#should_disable?" do
    test "false when user is invoiced" do
      user = create(:credit_card_user,
        plan: GitHub::Plan.pro,
        billed_on: GitHub::Billing.today - User::BillingDependency::DUNNING_DAYS,
        billing_attempts: User::BillingDependency::BILLING_ATTEMPTS_LIMIT,
        billing_type: "invoice"
      )

      refute user.should_disable?
    end

    test "true when per-repo user is over limit" do
      plan = GitHub::Plan.micro
      user = User.new \
        plan: plan,
        billed_on: GitHub::Billing.today + 10.days,
        billing_attempts: 0,
        owned_private_repositories: Array.new(plan.repos + 1) { Repository.new }

      assert_predicate user, :should_disable?
    end

    test "true when pro user is over billing attempts and dunning period has expired" do
      user = create(:credit_card_user,
        plan: GitHub::Plan.pro,
        billed_on: GitHub::Billing.today - User::BillingDependency::DUNNING_DAYS,
        billing_attempts: User::BillingDependency::BILLING_ATTEMPTS_LIMIT
      )

      assert user.should_disable?
    end

    test "true when user with a Copilot subscription is over billing attempts and dunning period has expired" do
      user = create(:credit_card_user,
        plan: GitHub::Plan.free_with_addons,
        billed_on: GitHub::Billing.today - User::BillingDependency::DUNNING_DAYS,
        billing_attempts: User::BillingDependency::BILLING_ATTEMPTS_LIMIT
      )
      plan_subscription = create(:billing_plan_subscription, user: user)
      create(:billing_subscription_item, :with_copilot_product_uuid, plan_subscription: plan_subscription)

      assert user.should_disable?
    end

    test "true when user with a Copilot trial has an authorization failure" do
      user = create(:credit_card_user, plan: GitHub::Plan.free_with_addons)
      user.customer.update_disabled_reasons(Billing::Public::BillingDisabledReasons::AuthorizationFailure)
      plan_subscription = create(:billing_plan_subscription, user: user)
      create(:billing_subscription_item, :with_copilot_product_uuid, plan_subscription: plan_subscription,
        free_trial_ends_on: GitHub::Billing.today + 30.days)

      assert user.paying_customer?
      assert user.payment_amount.zero?
      assert user.should_disable?
    end

    test "true when the user has any disabled reason present" do
      user = @credit_card_user
      user.customer.update_disabled_reasons(Billing::Public::BillingDisabledReasons::AuthorizationFailure)

      assert user.should_disable?
    end

    test "false when user is in the dunning period" do
      user = create(:credit_card_user,
        plan: GitHub::Plan.pro,
        billed_on: GitHub::Billing.today - (User::BillingDependency::DUNNING_DAYS - 1.day),
        billing_attempts: User::BillingDependency::BILLING_ATTEMPTS_LIMIT
      )

      # Account needs at least one past successful payment to be eligible for dunning
      create(:billing_transaction, user: user, amount_in_cents: 1_00, last_status: :settled)

      refute user.should_disable?
    end

    test "false when user is in good standing" do
      user = User.new \
        plan: GitHub::Plan.pro,
        billed_on: GitHub::Billing.today + 10.days,
        billing_attempts: 0

      refute_predicate user, :should_disable?
    end

    test "false when organization has private repos" do
      repo = create(:private_repository, owner: @organization)

      @organization.update_column(:plan, "free")
      @organization.reload

      refute @organization.should_disable?
    end
  end

  context "#needs_valid_payment_method_to_buy_data_packs?" do
    test "true when the total price with data packs is > 0" do
      %w[month year].each do |duration|
        user = User.new(plan: GitHub::Plan.free, plan_duration: duration)
        assert user.needs_valid_payment_method_to_buy_data_packs?(1)
      end
    end

    test "false when the total price with data packs is covered by a coupon" do
      %w[month year].each do |duration|
        user = create(:user, plan: GitHub::Plan.free, plan_duration: duration)

        coupon = create(:coupon, discount: GitHub::Plan.pro.cost + 5)
        user.redeem_coupon(coupon)

        refute user.needs_valid_payment_method_to_buy_data_packs?(1)
      end
    end

    test "false when self serve business org has a payment method but no billing information" do
      enable_feature_flag(:require_valid_contact_for_payment)
      business = create(:business, :with_self_serve_payment)
      org = create(:enterprise_linked_organization, business: business)

      refute org.has_saved_trade_screening_record?
      refute business.has_valid_trade_screening_record_for_payment?
      refute org.needs_valid_payment_method_to_buy_data_packs?(1)
    end
  end

  context "#zuora_account?" do
    test "true when the user's general-purpose customer record has a zuora_account_id" do
      customer = Customer.new(zuora_account_id: SecureRandom.hex(16))
      user = build(:user, customer: customer)

      assert_predicate user, :zuora_account?
    end

    test "false when the user's general-purpose customer record has no zuora_account_id" do
      customer = Customer.new(zuora_account_id: nil)
      user = build(:user, customer: customer)

      refute_predicate user, :zuora_account?
    end
  end

  context "#plan_support?" do
    test "knows which plans support private repos" do
      # all plans now support private repos
      free_user = @user
      business_org = create(:organization, plan: "business")
      assert business_org.plan_supports?(:repos, visibility: :public)
      assert business_org.plan_supports?(:repos, visibility: :private)

      free_org = @free_org
      assert free_org.plan_supports?(:repos, visibility: :public)
      assert free_org.plan_supports?(:repos, visibility: :private)

      assert free_user.plan_supports?(:repos, visibility: :public)
      assert free_user.plan_supports?(:repos, visibility: :private)
    end
  end

  context "#plan_limit" do
    test "knows collaborator limits for private and public repos" do
      free_user = @user
      business_org = create(:organization, plan: "business")

      assert_equal 10_000, business_org.plan_limit(:collaborators, visibility: :public)
      assert_equal 10_000, business_org.plan_limit(:collaborators, visibility: :private)

      assert_equal 10_000, free_user.plan_limit(:collaborators, visibility: :public)
      assert_equal 10_000, free_user.plan_limit(:collaborators, visibility: :private)
    end

    test "handles org-specific overrides for free plans" do
      free_user = @user
      free_org = @free_org

      assert_equal 10, free_user.plan_limit(:issue_pr_assignees, visibility: :public)
      assert_equal 10, free_user.plan_limit(:issue_pr_assignees, visibility: :private)
      assert_equal 10, free_org.plan_limit(:issue_pr_assignees, visibility: :public)
      assert_equal 1,  free_org.plan_limit(:issue_pr_assignees, visibility: :private)
    end
  end

  context "plan_effective_at" do
    test "returns the DateTime the user signed up for their current plan" do
      org = nil
      signup_time = GitHub::Billing.now
      org = travel_to(signup_time) do
        create(:organization, plan: GitHub::Plan.business)
      end

      assert_equal signup_time.to_i, org.plan_effective_at.to_i
    end

    test "returns the upgrade/downgrade DateTime when user has changed plans" do
      old_plan = GitHub::Plan.business
      first_signup_time = GitHub::Billing.now
      org = travel_to(first_signup_time) do
        create(:organization, plan: old_plan)
      end

      assert_equal first_signup_time.to_i, org.plan_effective_at.to_i

      new_signup_time = GitHub::Billing.now
      travel_to(new_signup_time) do
        org.update(plan: "business_plus")
        org.reload.track_plan_change(org, old_plan)
      end

      assert_equal new_signup_time.to_i, org.reload.plan_effective_at.to_i
    end

    test "returns the duration change DateTime when user has changed durations" do
      first_signup_time = GitHub::Billing.now
      org = travel_to(first_signup_time) do
        create(:organization, plan: "business_plus")
      end

      assert_equal first_signup_time.to_i, org.plan_effective_at.to_i

      duration_change_time = GitHub::Billing.now
      travel_to(duration_change_time) do
        org.update(plan_duration: User::BillingDependency::YEARLY_PLAN)
        org.reload.track_plan_duration_change(org, User::BillingDependency::MONTHLY_PLAN)
      end

      assert_equal duration_change_time.to_i, org.reload.plan_effective_at.to_i
    end

    test "returns the original signup DateTime when user has added seats at a later date" do
      old_plan = GitHub::Plan.business
      signup_time = GitHub::Billing.timezone.local(2019, 2, 1).to_datetime
      org = travel_to(signup_time) do
        create(:organization, plan: old_plan)
      end

      assert_equal signup_time.to_i, org.plan_effective_at.to_i

      seats_was = org.seats
      add_seats_time = GitHub::Billing.timezone.local(2019, 5, 1).to_datetime
      travel_to(add_seats_time) do
        org.update(seats: 7)
        org.track_seat_change(org, old_seats: seats_was)
      end

      assert_equal signup_time.to_i, org.reload.plan_effective_at.to_i
    end

    test "returns the most recent upgrade/downgrade date when the user has changed plans & changed back" do
      first_plan = GitHub::Plan.business
      signup_time = GitHub::Billing.timezone.local(2019, 2, 1).to_datetime
      org = travel_to(signup_time) do
        create(:organization, plan: first_plan)
      end

      assert_equal signup_time, org.plan_effective_at

      second_plan = GitHub::Plan.business_plus
      second_plan_time = GitHub::Billing.timezone.local(2019, 5, 1).to_datetime
      travel_to(second_plan_time) do
        org.update(plan: second_plan)
        org.reload.track_plan_change(org, first_plan)
      end

      assert_equal second_plan_time, org.reload.plan_effective_at

      third_plan_time = GitHub::Billing.timezone.local(2019, 7, 1).to_datetime
      third_plan = GitHub::Plan.business
      travel_to(third_plan_time) do
        org.update(plan: third_plan)
        org.reload.track_plan_change(org, second_plan)
      end

      assert_equal third_plan_time, org.reload.plan_effective_at
    end

    test "uses PST billing zone for transaction timestamp" do
      travel_to(GitHub::Billing.timezone.local(2019, 2, 1, 20)) do
        org = create(:organization, plan: GitHub::Plan.business)

        assert_equal GitHub::Billing.now, org.plan_effective_at
      end
    end

    test "returns now if user has no transactions" do
      org = travel_to(GitHub::Billing.timezone.local(2019, 2, 1)) do
        create(:organization, plan: GitHub::Plan.business)
      end
      org.transactions.destroy_all
      # Re-initialize Organization to remove memoized @plan_signup_transaction
      org = Organization.find(org.id)

      freeze_time do
        assert_equal GitHub::Billing.now.to_i, org.plan_effective_at.to_i
      end
    end
  end

  context "#seats" do
    test "returns business seat when organization belongs to a business" do
      business = create(:business, seats: 20)
      org = create(:organization, seats: 20)

      business.add_organization(org)
      org.update(seats: 5)
      org = Organization.find(org.id)

      assert_equal 20, org.seats
    end

    test "returns organization seat count when not owned by business" do
      org = create(:organization, seats: 20)

      assert_equal 20, org.seats
    end
  end

  context "#plan and #plan_name" do
    test "returns business plan when organization belongs to a business" do
      org = @free_org

      @business.add_organization(org)
      org.update(seats: 5)
      org = Organization.find(org.id)

      assert_equal "business_plus", org.plan.name
      assert_equal "business_plus", org.plan_name
    end

    test "returns organization plan when not owned by business" do
      org = @free_org

      assert_equal "free", org.plan.name
      assert_equal "free", org.plan_name
    end

    test "returns emu_user plan regardless of db value when the user is enterprise managed" do
      user = create(:emu, plan: "free_with_addons")

      assert_equal GitHub::Plan::EMU_USER, user.plan.name
      assert_equal GitHub::Plan::EMU_USER, user.plan_name
    end
  end

  context "#plan_duration" do
    test "returns business plan duration when organization belongs to a business" do
      org = create(:organization, plan_duration: User::BillingDependency::MONTHLY_PLAN)

      @business.add_organization(org)
      org.update(seats: 5)
      org = Organization.find(org.id)

      # Business is always yearly
      assert_equal User::BillingDependency::YEARLY_PLAN, org.plan_duration
    end

    test "returns organization plan_duration when not owned by business" do
      org = create(:organization, plan_duration: User::BillingDependency::MONTHLY_PLAN)

      assert_equal User::BillingDependency::MONTHLY_PLAN, org.plan_duration
    end
  end

  context "#billed_on" do
    test "returns business billed_on when organization belongs to a business" do
      billing_end_date = Date.tomorrow
      @business.customer.update(billing_end_date: billing_end_date)
      org = create(:organization, billed_on: Date.yesterday)

      @business.add_organization(org)
      org.update(seats: 5)
      org = Organization.find(org.id)

      # billed_on is billing_end_date + 1 day
      assert_equal billing_end_date + 1.day, org.billed_on
    end

    test "returns organization billed_on when not owned by business" do
      billed_on = Date.yesterday
      @organization.assign_attributes(billed_on: billed_on)

      assert_equal billed_on, @organization.billed_on
    end
  end

  context "#delegate_billing_to_business?" do
    if GitHub.single_business_environment?
      test "always returns false" do
        organization = create(:organization, business: @business)

        refute organization.delegate_billing_to_business?
      end
    else
      test "returns true if the organization is associated with a business" do
        organization = create(:organization, business: @business)

        assert organization.delegate_billing_to_business?
      end

      test "returns false if the organization is not associated with a business" do
        refute @organization.delegate_billing_to_business?
      end

      test "returns false for users" do
        refute @user.delegate_billing_to_business?
      end
    end
  end

  context "#budget_for", skip_enterprise: true do
    test "returns a new in-memory object with default values if no record exists" do
      config = @user.budget_for(group: "shared")

      assert config.enforce_spending_limit?
      assert_equal 0, config.spending_limit_in_subunits
      refute config.persisted?
    end

    test "returns the record from the DB if it exists" do
      Billing::BudgetLimit::FindBudget.expects(:for_account).with(@credit_card_user, true).once.returns(Billing::BudgetLimit::FindBudget::TRUSTED_TIER_SPENDING_LIMIT)
      create(:billing_budget, owner: @credit_card_user, enforce_spending_limit: false, spending_limit_in_subunits: 1000)

      config = @credit_card_user.budget_for(group: "shared")

      refute config.enforce_spending_limit?
      assert_equal 1000, config.spending_limit_in_subunits
    end

    test "returns a readonly record with an enforced limit of zero for users and organizations that have any trade restrictions, even if they previously had saved config" do
      organization = create(:credit_card_organization, :fully_trade_restricted)
      Billing::BudgetLimit::FindBudget.expects(:for_account).with(organization, true).once.returns(Billing::BudgetLimit::FindBudget::TRUSTED_TIER_SPENDING_LIMIT)
      create(:billing_budget, owner: organization, enforce_spending_limit: false, spending_limit_in_subunits: 1000)

      config = organization.budget_for(group: "shared")

      assert config.enforce_spending_limit?
      assert_equal 0, config.spending_limit_in_subunits
      assert config.readonly?
    end

    test "invoiced organizations converts codespaces product to appropriate product_key" do
      config = @invoiced_organization.budget_for(product: "codespaces_compute")
      assert config.new_record?
      assert_equal "codespaces", config.product
      refute config.readonly?
    end

    test "self-served organizations do not convert codespaces product" do
      config = @organization.budget_for(product: "codespaces_compute")
      assert config.new_record?
      assert_equal "codespaces", config.product
      refute config.readonly?
    end

    test "raises for unknown products and groups" do
      assert_raises(Billing::MeteredProduct::UnknownProductError) { @organization.budget_for(product: "unknown-product") }
      assert_raises(ArgumentError) { @organization.budget_for(group: "unknown-product") }
    end

    test "budget group being string or symbol has same behavior" do
      budget1 =  @user.budget_for(group: "codespaces")
      assert budget1.enforce_spending_limit
      assert_equal budget1.spending_limit_in_subunits, 0

      budget2 = @user.budget_for(group: :codespaces)
      assert_same_elements budget1.attributes.to_a, budget2.attributes.to_a
    end

  end

  context "#available_invitable_seats" do
    test "returns total available licenses for business when organization belongs to a business" do
      user = @user
      admin = create(:user)
      org = create(:organization, seats: 77, admins: [admin], public_members: [user])
      business = create(:business, :volume_licensed, seats: 20, organizations: [org]) # 20 enterprise licenses and 100 volume licenses
      org.reload
      business.reload

      assert_equal 118, org.available_invitable_seats
    end
  end

  context "#total_available_seats" do
    test "returns total available invitable and non-invitable licenses" do
      admin = @user
      org = create(:organization, seats: 100, admins: [admin])
      create(:business, :volume_licensed, seats: 20, organizations: [org])
      org.reload

      assert_equal 119, org.total_available_seats
    end
  end

  context "#filled_seats" do
    test "returns number of user licenses for business when organization belongs to a business" do
      user = @user
      admin = create(:user)
      org = create(:organization, seats: 77, admins: [admin], public_members: [user])
      business = create(:business, :volume_licensed, seats: 20, organizations: [org]) # 20 enterprise licenses and 100 volume licenses
      org.reload
      business.reload

      assert_equal 2, org.filled_seats
    end
  end

  context "user_is_outside_collaborator?" do
    test "returns true if user is outside collaborator" do
      org  = create(:organization, plan: "business_plus", seats: 10)
      repo = create(:private_repository, owner: org)
      repo.add_member(@user)
      assert org.user_is_outside_collaborator?(@user)
    end

    test "returns false if user is not an outside collaborator" do
      org  = create(:organization, plan: "business_plus", seats: 10)
      # note - user cannot be an outside collaborator if they are an org member
      org.add_member(@user)
      create(:private_repository, owner: org)
      refute org.user_is_outside_collaborator?(@user)
    end

    test "accepts an array of repository ids and does not query for them" do
      org  = create(:organization, plan: "business_plus", seats: 10)
      repo = create(:private_repository, owner: org)
      repo.add_member(@user)
      Repository.active.stubs(:where).returns([])
      assert org.user_is_outside_collaborator?(@user, [repo.id])
    end

    test "accepts a single repository id and does not query for it" do
      org  = create(:organization, plan: "business_plus", seats: 10)
      repo = create(:private_repository, owner: org)
      repo.add_member(@user)
      Repository.active.stubs(:where).returns([])
      assert org.user_is_outside_collaborator?(@user, repo.id)
    end
  end

  context "#has_seat_for_email?" do
    test "returns true if the plan is a per-repository plan" do
      organization = create(:organization, plan: :bronze, seats: 0)

      assert organization.has_seat_for_email?("someone@example.com")
    end

    test "returns true if the plan is per-seat but there are available seats" do
      organization = create(:organization, plan: :business, seats: 1000)

      assert organization.has_seat_for_email?("someone@example.com")
    end

    test "returns true if the plan is per-seat, the email is associated with the organiation already, and there are no more seats" do
      organization = create(:organization, plan: :business, seats: 2)
      email = "someone@example.com"
      organization.invite(email: email, inviter: organization.admins.first)

      assert organization.has_seat_for_email?(email)
    end

    test "returns false if the plan is per-seat and an upcoming plan change will mean there are not enough seats" do
      organization = create(:organization, plan: :business, seats: 1000)
      email = "someone@example.com"
      Billing::PendingPlanChange.create!(user: organization, seats: 1, active_on: 1.month.from_now)

      refute organization.has_seat_for_email?(email, pending_cycle: true)
    end

    test "returns false if the plan is per-seat, the email is not currently associated with the organiation, and there are no more seats" do
      organization = create(:organization, plan: :business, seats: 1)
      email = "someone@example.com"

      refute organization.has_seat_for_email?(email)
    end

    test "returns true if the organization is owned by a business and there are unused licenses" do
      business = create(:business, seats: 1000)
      organization = create(:organization, business: business)
      email = "someone@example.com"

      assert organization.has_seat_for_email?(email)
    end

    test "returns true if the organization is owned by a business and the email is already associated with the business even if the business has no unused licenses" do
      business = create(:business, seats: 3)
      organization1 = create(:organization, business: business)
      organization2 = create(:organization, business: business)
      email = "someone@example.com"
      organization1.invite(email: email, inviter: organization1.admins.first)

      assert organization2.has_seat_for_email?(email)
    end

    test "returns false if the organization is owned by a business, the email is not currently associated with the business, and there are no unused licenses on the business" do
      business = create(:business, seats: 1)
      organization = create(:organization, business: business)
      organization.reload # get fresh business
      email = "someone@example.com"

      refute organization.has_seat_for_email?(email)
    end

    test "returns true if the organization is owned by a business and the email is covered by a bundled license - even if the business has no unused licenses" do
      business = create(:business, :volume_licensed, seats: 1)
      organization = create(:organization, business: business)
      email = "someone@example.com"
      create(:licensing_bundled_license_assignment, business: business, email: email)

      assert organization.has_seat_for_email?(email)
    end
  end

  context "#has_seat_for?" do
    test "returns true if the plan is a per-repository plan" do
      organization = create(:organization, plan: :bronze, seats: 0)

      assert organization.has_seat_for?(@user)
    end

    test "returns true if the plan is per-seat but there are available seats" do
      organization = create(:organization, plan: :business, seats: 1000)

      assert organization.has_seat_for?(@user)
    end

    test "returns true if the plan is per-seat, the user is associated with the organiation already, and there are no more seats" do
      organization = create(:organization, plan: :business, seats: 2)
      organization.add_member(@user)

      assert organization.has_seat_for?(@user)
    end

    test "returns false if the plan is per-seat and an upcoming plan change will mean there are not enough seats" do
      organization = create(:organization, plan: :business, seats: 1000)
      Billing::PendingPlanChange.create!(user: organization, seats: 1, active_on: 1.month.from_now)

      refute organization.has_seat_for?(@user, pending_cycle: true)
    end

    test "returns false if the plan is per-seat, the email is not currently associated with the organiation, and there are no more seats" do
      organization = create(:organization, plan: :business, seats: 1)

      refute organization.has_seat_for?(@user)
    end

    test "returns true if the organization is owned by a business and there are unused licenses" do
      business = create(:business, seats: 1000)
      organization = create(:organization, business: business)

      assert organization.has_seat_for?(@user)
    end

    test "returns true if the organization is owned by a business and the user is already associated with the business even if the business has no unused licenses" do
      business = create(:business, seats: 3)
      organization1 = create(:organization, business: business)
      organization2 = create(:organization, business: business)
      organization1.add_member(@user)

      assert organization2.has_seat_for?(@user)
    end

    test "returns false if the organization is owned by a business, the user is not currently associated with the business, and there are no unused licenses on the business" do
      business = create(:business, seats: 1)
      organization = create(:organization, business: business)
      organization.reload # get fresh business

      refute organization.has_seat_for?(@user)
    end

    test "returns true if the organization is owned by a business and the user is covered by a bundled license - even if the business has no unused licenses" do
      business = create(:business, :volume_licensed, seats: 1)
      organization = create(:organization, business: business)
      create(:licensing_bundled_license_assignment, business: business, user: @user)

      assert organization.has_seat_for?(@user)
    end
  end

  context "#has_seats_for?" do
    test "returns true if the plan is a per-repository plan" do
      organization = create(:organization, plan: :bronze, seats: 0)

      assert organization.has_seats_for?([@user, create(:user)].map(&:id))
    end

    test "returns true if the plan is per-seat but there are available seats" do
      organization = create(:organization, plan: :business, seats: 1000)

      assert organization.has_seats_for?([@user, create(:user)].map(&:id))
    end

    test "returns true if the plan is per-seat, the user is associated with the organiation already, and there are no more seats" do
      organization = create(:organization, plan: :business, seats: 2)
      organization.add_member(@user)

      assert organization.has_seats_for?([@user].map(&:id))
    end

    test "returns false if the plan is per-seat and an upcoming plan change will mean there are not enough seats" do
      organization = create(:organization, plan: :business, seats: 1000)
      Billing::PendingPlanChange.create!(user: organization, seats: 1, active_on: 1.month.from_now)

      refute organization.has_seats_for?([@user].map(&:id), pending_cycle: true)
    end

    test "returns false if the plan is per-seat, the email is not currently associated with the organiation, and there are no more seats" do
      organization = create(:organization, plan: :business, seats: 1)

      refute organization.has_seats_for?([@user].map(&:id))
    end

    test "returns true if the organization is owned by a business and there are unused licenses" do
      business = create(:business, seats: 1000)
      organization = create(:organization, business: business)

      assert organization.has_seats_for?([@user].map(&:id))
    end

    test "returns true if the organization is owned by a business and the user is already associated with the business even if the business has no unused licenses" do
      business = create(:business, seats: 3)
      organization1 = create(:organization, business: business)
      organization2 = create(:organization, business: business)
      organization1.add_member(@user)

      assert organization2.has_seats_for?([@user].map(&:id))
    end

    test "returns false if the organization is owned by a business, the user is not currently associated with the business, and there are no unused licenses on the business" do
      business = create(:business, seats: 1)
      organization = create(:organization, business: business)
      organization.reload # get fresh business

      refute organization.has_seats_for?([@user].map(&:id))
    end

    test "returns true if the organization is owned by a business and the user is covered by a bundled license - even if the business has no unused licenses" do
      business = create(:business, :volume_licensed, seats: 1)
      organization = create(:organization, business: business)
      create(:licensing_bundled_license_assignment, business: business, user: @user)

      assert organization.has_seats_for?([@user].map(&:id))
    end
  end

  context "seat validations for plan base units" do
    test "0 seats is valid when the plan has base units of 0" do
      organization = create(:free_organization, seats: 1)

      organization.seats = 0
      organization.valid?

      assert organization.errors[:seats].none?
    end

    test "0 seats is invalid when the plan has base units of 1" do
      organization = create(:business_plus_organization, seats: 1)

      organization.seats = 0
      organization.valid?

      assert_includes organization.errors[:seats], "must be at least 1"
    end

    test "0 seats is valid when the plan has a base unit of 1 but the organization has a business" do
      business = create(:business, :volume_licensed, seats: 0)
      organization = create(:business_plus_organization, seats: 1)
      create(:licensing_bundled_license_assignment, business: business, user: organization.admins.first)

      organization.seats = 0
      organization.business = business
      organization.valid?

      assert organization.errors[:seats].none?
    end
  end

  context "upcoming renewal" do
    context "#renewal_eligible_businesses" do
      test "returns businesses with upcoming renewals" do
        user = @user
        business1 = create(:business, customer: create(:customer, :zuora, :invoiced, term_length: 12), seats: 1, owners: [user])
        business1.customer.update(billing_end_date: GitHub::Billing.today + 1.week)
        business2 = create(:business, customer: create(:customer, :zuora, :invoiced, term_length: 12), seats: 1, owners: [user])
        business2.customer.update(billing_end_date: GitHub::Billing.today + 2.months)

        assert_equal 1, user.renewal_eligible_businesses.count
        assert_equal business1, user.renewal_eligible_businesses.first
      end

      test "only returns invoiced businesses" do
        user = @user
        business1 = create(:business, customer: create(:customer, :zuora, :invoiced, term_length: 12), seats: 1, owners: [user])
        business1.customer.update(billing_end_date: GitHub::Billing.today + 1.week)
        business2 = create(:business, customer: create(:customer, :zuora, term_length: 12), seats: 1, owners: [user])
        business2.customer.update(billing_end_date: GitHub::Billing.today + 1.week)

        assert_equal 1, user.renewal_eligible_businesses.count
        assert_equal business1, user.renewal_eligible_businesses.first
      end

      test "returns expired businesses last" do
        user = @user
        business1 = create(:business, customer: create(:customer, :zuora, :invoiced, term_length: 12), seats: 1, owners: [user])
        business1.customer.update(billing_end_date: GitHub::Billing.today - 1.week)
        business2 = create(:business, customer: create(:customer, :zuora, :invoiced, term_length: 12), seats: 1, owners: [user])
        business2.customer.update(billing_end_date: GitHub::Billing.today + 1.week)

        assert_equal 2, user.renewal_eligible_businesses.count
        assert_equal business2, user.renewal_eligible_businesses.first
        assert_equal business1, user.renewal_eligible_businesses.last
      end

      test "returns the immediately expiring business first" do
        user = @user
        business1 = create(:business, customer: create(:customer, :zuora, :invoiced, term_length: 12), seats: 1, owners: [user])
        business1.customer.update(billing_end_date: GitHub::Billing.today + 2.weeks)
        business2 = create(:business, customer: create(:customer, :zuora, :invoiced, term_length: 12), seats: 1, owners: [user])
        business2.customer.update(billing_end_date: GitHub::Billing.today + 1.week)

        assert_equal 2, user.renewal_eligible_businesses.count
        assert_equal business2, user.renewal_eligible_businesses.first
        assert_equal business1, user.renewal_eligible_businesses.last
      end

      test "returns the most recently expired business first" do
        user = @user
        business1 = create(:business, customer: create(:customer, :zuora, :invoiced, term_length: 12), seats: 1, owners: [user])
        business1.customer.update(billing_end_date: GitHub::Billing.today - 2.weeks)
        business2 = create(:business, customer: create(:customer, :zuora, :invoiced, term_length: 12), seats: 1, owners: [user])
        business2.customer.update(billing_end_date: GitHub::Billing.today - 1.week)

        assert_equal 2, user.renewal_eligible_businesses.count
        assert_equal business2, user.renewal_eligible_businesses.first
        assert_equal business1, user.renewal_eligible_businesses.last
      end
    end

    context "#renewal_eligible_business" do
      test "returns nil if there are no eligible business" do
        enable_feature_flag(:ghe_sales_serve_renewals)
        enable_feature_flag(:sales_managed_subscription_self_serve_eligible_override)

        assert_nil @user.renewal_eligible_business
      end

      test "returns nil if feature flag is disabled" do
        disable_feature_flag(:ghe_sales_serve_renewals)
        enable_feature_flag(:sales_managed_subscription_self_serve_eligible_override)
        user = @user
        business1 = create(:business, customer: create(:customer, :zuora, :invoiced, term_length: 12), seats: 1, owners: [user])
        business1.customer.update(billing_end_date: GitHub::Billing.today + 2.weeks)
        business2 = create(:business, customer: create(:customer, :zuora, :invoiced, term_length: 12), seats: 1, owners: [user])
        business2.customer.update(billing_end_date: GitHub::Billing.today + 1.week)

        assert_nil user.renewal_eligible_business
      end

      test "returns nil if sales_managed_subscription_self_serve_eligible? is false" do
        enable_feature_flag(:ghe_sales_serve_renewals)
        disable_feature_flag(:sales_managed_subscription_self_serve_eligible_override)
        user = @user
        business1 = create(:business, customer: create(:customer, :zuora, :invoiced, term_length: 12), seats: 1, owners: [user])
        business1.customer.update(billing_end_date: GitHub::Billing.today + 2.weeks)
        business2 = create(:business, customer: create(:customer, :zuora, :invoiced, term_length: 12), seats: 1, owners: [user])
        business2.customer.update(billing_end_date: GitHub::Billing.today + 1.week)

        assert_nil user.renewal_eligible_business
      end

      test "returns nil if there are past due invoices and that feature flag is enabled" do
        enable_feature_flag(:ghe_sales_serve_renewals)
        enable_feature_flag(:sales_managed_subscription_self_serve_eligible_override)
        enable_feature_flag(:ghe_sales_serve_overdue)

        Business.any_instance.stubs(:past_due_invoice?).returns(true)

        user = @user
        business1 = create(:business, customer: create(:customer, :zuora, :invoiced, term_length: 12), seats: 1, owners: [user])
        business1.customer.update(billing_end_date: GitHub::Billing.today + 2.weeks)
        business2 = create(:business, customer: create(:customer, :zuora, :invoiced, term_length: 12), seats: 1, owners: [user])
        business2.customer.update(billing_end_date: GitHub::Billing.today + 1.week)

        assert_nil user.renewal_eligible_business
      end

      test "returns a business even if there are past due invoices but that feature flag is disabled" do
        enable_feature_flag(:ghe_sales_serve_renewals)
        enable_feature_flag(:sales_managed_subscription_self_serve_eligible_override)
        disable_feature_flag(:ghe_sales_serve_overdue)

        Business.any_instance.stubs(:past_due_invoice?).returns(true)

        user = @user
        business = create(:business, customer: create(:customer, :zuora, :invoiced, term_length: 12), seats: 1, owners: [user])
        business.customer.update(billing_end_date: GitHub::Billing.today + 2.weeks)

        assert_equal business, user.renewal_eligible_business
      end

      test "returns the business with most recent upcoming business" do
        enable_feature_flag(:ghe_sales_serve_renewals)
        enable_feature_flag(:sales_managed_subscription_self_serve_eligible_override)
        user = @user
        business1 = create(:business, customer: create(:customer, :zuora, :invoiced, term_length: 12), seats: 1, owners: [user])
        business1.customer.update(billing_end_date: GitHub::Billing.today + 2.weeks)
        business2 = create(:business, customer: create(:customer, :zuora, :invoiced, term_length: 12), seats: 1, owners: [user])
        business2.customer.update(billing_end_date: GitHub::Billing.today + 1.week)

        assert_equal business2, user.renewal_eligible_business
      end

      test "returns the business with most recent expired business" do
        enable_feature_flag(:ghe_sales_serve_renewals)
        enable_feature_flag(:sales_managed_subscription_self_serve_eligible_override)
        user = @user
        business1 = create(:business, customer: create(:customer, :zuora, :invoiced, term_length: 12), seats: 1, owners: [user])
        business1.customer.update(billing_end_date: GitHub::Billing.today - 2.weeks)
        business2 = create(:business, customer: create(:customer, :zuora, :invoiced, term_length: 12), seats: 1, owners: [user])
        business2.customer.update(billing_end_date: GitHub::Billing.today - 1.week)

        assert_equal business2, user.renewal_eligible_business
      end
    end
  end

  context "billing_email notice" do
    test "enqueues job to set or unset billing_email notice if billing email is invalid" do
      @user.stubs(:billing_email_invalid?).returns(true)

      assert_enqueued_jobs(1, queue: "billing", only: Billing::BillingEmailCheckJob) do
        @user.update(updated_at: 1.day.ago)
      end
    end

    test "does not enqueue job to set or unset billing_email notice if billing email is valid" do
      assert_enqueued_jobs(0, queue: "billing", only: Billing::BillingEmailCheckJob) do
        @user.update(updated_at: 1.day.ago)
      end
    end

    test "enqueues job to set or unset billing_email notice for an org" do
      org = create(:organization, admins: [@user, create(:user)])
      org.stubs(:billing_email_invalid?).returns(true)

      assert_enqueued_jobs(1, queue: "billing", only: Billing::BillingEmailCheckJob) do
        org.update(updated_at: 1.day.ago)
      end
    end

    test "does not enqueue job to set or unset billing_email notice for an org" do
      org = create(:organization, admins: [@user, create(:user)])

      assert_enqueued_jobs(0, queue: "billing", only: Billing::BillingEmailCheckJob) do
        org.update(updated_at: 1.day.ago)
      end
    end
  end

  context "org_billing_trouble notice" do
    test "does not enqueue job to set org_billing_trouble notice if account is not an org" do
      @user.stubs(:billing_trouble?).returns(true)

      assert_enqueued_jobs(0, queue: "billing", only: Billing::OrgBillingTroubleCheckJob) do
        @user.update(updated_at: 1.day.ago)
      end
    end

    test "enqueues job to set org_billing_trouble notice if org has billing trouble" do
      @organization.stubs(:billing_trouble?).returns(true)

      assert_enqueued_jobs(1, queue: "billing", only: Billing::OrgBillingTroubleCheckJob) do
        @organization.update(updated_at: 1.day.ago)
      end
    end

    test "does not enqueue job to set org_billing_trouble notice if org does not have billing trouble" do
      assert_enqueued_jobs(0, queue: "billing", only: Billing::OrgBillingTroubleCheckJob) do
        @organization.update(updated_at: 1.day.ago)
      end
    end
  end

  context "personal_billing_trouble notice" do
    test "enqueues job to set personal_billing_trouble notice if user has billing trouble" do
      @user.stubs(:billing_trouble?).returns(true)

      assert_enqueued_jobs(1, queue: "billing", only: Billing::PersonalBillingTroubleCheckJob) do
        @user.update(updated_at: 1.day.ago)
      end
    end

    test "does not enqueue job to set personal_billing_trouble notice if user does not have billing trouble" do
      assert_enqueued_jobs(0, queue: "billing", only: Billing::PersonalBillingTroubleCheckJob) do
        @user.update(updated_at: 1.day.ago)
      end
    end

    test "does not enqueue job to set personal_billing_trouble notice if account is an organization" do
      assert_enqueued_jobs(0, queue: "billing", only: Billing::PersonalBillingTroubleCheckJob) do
        @organization.update(updated_at: 1.day.ago)
      end
    end
  end

  context "#customer" do
    test "returns general-purpose customer even if a Sponsors-specific customer exists for the user" do
      general_purpose_customer = create(:customer_account, user: @user).customer
      sponsors_customer = create(:customer, :sponsors_invoiced, payment_method: build(:payment_method, primary: false))
      create(:customer_account, :sponsors_invoiced, user: @user, customer: sponsors_customer)

      assert_equal general_purpose_customer, @user.customer
    end

    test "does not make additional queries with repeated calls" do
      general_purpose_customer = create(:customer_account, user: @user).customer

      assert_query_count(1) do
        assert_equal general_purpose_customer, @user.customer
      end

      assert_query_count(0) do
        assert_equal general_purpose_customer, @user.customer
      end
    end

    test "does not make an additional query to the Sponsors-specific customer when calling #sponsors_customer after" do
      sponsors_customer = create(:customer, :sponsors_invoiced, payment_method: build(:payment_method, primary: false))
      create(:customer_account, :sponsors_invoiced, user: @user, customer: sponsors_customer)

      @user.customer # load all the customers tied to the user

      assert_query_count(0) do
        assert_equal sponsors_customer, @user.sponsors_customer
      end
    end
  end

  context "#customer_bill_cycle_day" do
    test "returns the business's value if there is a business" do
      @organization.update!(business: @business)
      @business.customer.update!(bill_cycle_day: 5)

      assert_equal @business.customer.bill_cycle_day, @organization.customer_bill_cycle_day
    end

    test "returns the customer's value if there's no business" do
      @organization.customer = create(:customer, bill_cycle_day: 5)

      assert_equal @organization.customer.bill_cycle_day, @organization.customer_bill_cycle_day
    end

    test "returns zero when there's no customer" do
      @organization.customer = nil

      assert_equal 0, @organization.customer_bill_cycle_day
    end
  end

  context "#metered_cycle_day" do
    test "returns 1 when the customer is nil" do
      @organization.customer = nil
      assert_equal 1, @organization.metered_cycle_day
    end

    test "returns 1 when there is no customer" do
      assert_equal 1, @organization.metered_cycle_day
    end

    test "returns 1 when the customer's bill cycle day is 0" do
      @organization.customer = create(:customer, bill_cycle_day: 0)
      assert_equal 1, @organization.metered_cycle_day
    end

    test "returns 1 for an organization that is metered via azure" do
      org = create(:organization)
      org.customer = create(:customer, bill_cycle_day: 4, metered_via_azure: true, azure_subscription_id: SecureRandom.uuid)
      assert_equal 1, org.metered_cycle_day
    end

    test "returns the bill cyle day of the customer when the customer's is a present and postive" do
      @organization.customer = create(:customer, bill_cycle_day: 4)
      assert_equal 4, @organization.metered_cycle_day
    end
  end

  context "#start_of_billing_day_with_timezone" do
    test "returns the start of the date in UTC for azure subscription billed orgs" do
      org = create(:enterprise_linked_organization)
      org.business.stubs(:billed_through_azure_subscription?).returns(true)
      date = Date.parse("2021-11-29 13:37:00 +00:00")
      expected_date_with_timezone = ActiveSupport::TimeZone["UTC"].parse(date.iso8601).beginning_of_day

      assert_equal expected_date_with_timezone, org.start_of_billing_day_with_timezone(date)
    end

    test "returns the start of the date in PDT/PST for non azure subscription billed orgs" do
      org = create(:team_org)
      date = Date.parse("2021-11-29 13:37:00 +00:00")
      expected_date_with_timezone = GitHub::Billing.timezone.parse(date.iso8601).beginning_of_day

      assert_equal expected_date_with_timezone, org.start_of_billing_day_with_timezone(date)
    end

    test "returns the start of the date in PDT/PST for users" do
      date = Date.parse("2021-11-29 13:37:00 +00:00")
      expected_date_with_timezone = GitHub::Billing.timezone.parse(date.iso8601).beginning_of_day

      assert_equal expected_date_with_timezone, @user.start_of_billing_day_with_timezone(date)
    end
  end

  context "#has_valid_payment_method?", skip_enterprise: true do
    test "returns true for user with valid payment method and no screening profile" do
      org = create(:credit_card_org)
      assert org.has_valid_payment_method?(feature_type: :noncommercial, check_for_stopgap_restriction: true)
    end

    test "returns true for user with valid payment method and valid screening profile" do
      org = create(:credit_card_org, :with_valid_contact_for_billing)
      assert org.has_valid_payment_method?(check_for_stopgap_restriction: true)
    end

    test "returns true for user with valid payment method and hit_in_review screening profile" do
      org = create(:credit_card_org, :with_account_screening_profile)
      org.trade_screening_record.hit_in_review!

      assert org.has_valid_payment_method?(check_for_stopgap_restriction: true)
    end

    test "returns false for user with valid payment method and stopgap screening profile" do
      org = create(:credit_card_org)
      org.terms_of_service.update(type: "Corporate", actor: org.admins.first)

      enable_feature_flag(:live_sdn_screening, org)
      create(:account_screening_profile, :lic_r_enabled_and_restricted, owner: org)

      refute org.reload.has_valid_payment_method?(check_for_stopgap_restriction: true)
    end

    test "returns true for enterprise linked org with a valid payment method" do
      business = create(:business, :with_valid_contact_for_billing, :with_self_serve_payment)
      org = create(:enterprise_linked_organization, business: business)

      assert org.has_valid_payment_method?(should_delegate_billing_to_business: true)
    end

    test "returns false if 'check_if_delegate_billing_to_business' param is set to false for enterprise linked org with a valid payment method" do
      business = create(:business, :with_self_serve_payment)
      org = create(:enterprise_linked_organization, business: business)
      disable_feature_flag(:delegate_valid_payment_method_to_business)

      refute org.has_valid_payment_method?(should_delegate_billing_to_business: false)
    end

    test "returns true if 'check_if_delegate_billing_to_business' param is set to false for enterprise linked org with a valid payment method and the feature flag is enabled" do
      business = create(:business, :with_valid_contact_for_billing, :with_self_serve_payment)
      org = create(:enterprise_linked_organization, business: business)
      enable_feature_flag(:delegate_valid_payment_method_to_business)

      assert org.has_valid_payment_method?(should_delegate_billing_to_business: false)
    end

    test "returns false for enterprise linked org with no payment method" do
      business = create(:business)
      org = create(:enterprise_linked_organization, business: business)

      refute org.has_valid_payment_method?(should_delegate_billing_to_business: true)
    end

    test "returns true for User object with a valid payment method" do
      user = create(:credit_card_user, :with_valid_contact_for_billing)

      assert user.has_valid_payment_method?(should_delegate_billing_to_business: true)
    end

    test "returns true for User object with a valid payment method for cost management" do
      user = @credit_card_user

      assert user.has_valid_payment_method?(feature_type: :noncommercial, should_delegate_billing_to_business: true)
    end

    test "returns false for User object with no payment method" do
      refute @user.has_valid_payment_method?(should_delegate_billing_to_business: true)
    end
  end

  context "annual_discount_allowed?" do
    test "returns false if remove_org_annual_discount FF enabled" do
      enable_feature_flag(:remove_org_annual_discount)

      org = create(:team_org)
      refute org.annual_discount_allowed?(billing_cycle: User::BillingDependency::YEARLY_PLAN)
    end

    test "returns false if not an org" do
      disable_feature_flag(:remove_org_annual_discount)

      refute @user.annual_discount_allowed?
    end

    test "returns true if there are no billing transactions in the org" do
      disable_feature_flag(:remove_org_annual_discount)

      org = create(:team_org)
      assert org.annual_discount_allowed?(billing_cycle: User::BillingDependency::YEARLY_PLAN)
    end

    test "returns false if target plan interval is monthly" do
      disable_feature_flag(:remove_org_annual_discount)

      org = create(:team_org)
      refute org.annual_discount_allowed?(billing_cycle: User::BillingDependency::MONTHLY_PLAN)
    end

    test "returns false if plan is nil" do
      disable_feature_flag(:remove_org_annual_discount)

      org = create(:team_org)
      refute org.annual_discount_allowed?(plan: nil, billing_cycle: User::BillingDependency::MONTHLY_PLAN)
    end

    test "returns true for Team if there are no Team/Enterprise yearly transactions in the org" do
      disable_feature_flag(:remove_org_annual_discount)

      team_org = create(:organization, plan_duration: User::BillingDependency::MONTHLY_PLAN, plan: "business")
      create(:billing_transaction,
        user: team_org,
        plan_name: "business_plus",
        renewal_frequency: :monthly,
        amount_in_cents: 20_00
      )
      create(:billing_transaction,
        user: team_org,
        plan_name: "business",
        renewal_frequency: :monthly,
        amount_in_cents: 4_00
      )
      assert team_org.annual_discount_allowed?(
        plan: GitHub::Plan.business_plus,
        billing_cycle: User::BillingDependency::YEARLY_PLAN,
        target_date: 1.year.from_now.to_date
      )
    end

    test "returns true for Enterprise if there are no Team/Enterprise yearly transactions in the org" do
      disable_feature_flag(:remove_org_annual_discount)

      org = create(:organization, plan_duration: User::BillingDependency::MONTHLY_PLAN, plan: "business_plus")
      create(:billing_transaction,
        user: org,
        plan_name: "business_plus",
        renewal_frequency: :monthly,
        amount_in_cents: 20_00
      )
      create(:billing_transaction,
        user: org,
        plan_name: "business",
        renewal_frequency: :monthly,
        amount_in_cents: 4_00
      )
      assert org.annual_discount_allowed?(
        plan: GitHub::Plan.business_plus,
        billing_cycle: User::BillingDependency::YEARLY_PLAN,
        target_date: 1.year.from_now.to_date
      )
    end

    # we should fix this case later when possible
    test "incorrectly returns false if there is an annual transaction of a non-eligible plan" do
      disable_feature_flag(:remove_org_annual_discount)

      jan_1st_2023 = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")
      jan_2nd_2024 = GitHub::Billing.date_in_timezone Date.parse("2024-01-02")
      org = create(:organization, plan_duration: User::BillingDependency::MONTHLY_PLAN, plan: "business_plus")
      travel_to jan_1st_2023 do
        create(:billing_transaction,
          user: org,
          plan_name: "silver",
          renewal_frequency: :yearly,
          amount_in_cents: 20_00
        )
        create(:billing_transaction,
          user: org,
          plan_name: "business_plus",
          renewal_frequency: :monthly,
          amount_in_cents: 20_00
        )
        create(:billing_transaction,
          user: org,
          plan_name: "business",
          renewal_frequency: :monthly,
          amount_in_cents: 4_00
        )
      end
      travel_to jan_2nd_2024 do
        refute org.annual_discount_allowed?(billing_cycle: User::BillingDependency::YEARLY_PLAN)
      end
    end

    test "returns false if has Team yearly transaction" do
      disable_feature_flag(:remove_org_annual_discount)

      jan_1st_2023 = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")
      jan_2nd_2024 = GitHub::Billing.date_in_timezone Date.parse("2024-01-02")
      team_org = travel_to jan_1st_2023 do
        org = create(:organization, plan_duration: User::BillingDependency::MONTHLY_PLAN, plan: "business")
        create(:billing_transaction,
          user: org,
          plan_name: "business",
          renewal_frequency: :yearly,
          amount_in_cents: 44_00
        )
        create(:billing_transaction,
          user: org,
          plan_name: "business",
          renewal_frequency: :monthly,
          amount_in_cents: 4_00
        )
        assert org.annual_discount_allowed?(billing_cycle: User::BillingDependency::YEARLY_PLAN)
        assert org.annual_discount_allowed?(billing_cycle: User::BillingDependency::YEARLY_PLAN, target_date: 3.months.from_now.to_date)
        refute org.annual_discount_allowed?(billing_cycle: User::BillingDependency::YEARLY_PLAN, target_date: 1.year.from_now.to_date)

        org
      end

      travel_to jan_2nd_2024 do
        refute team_org.annual_discount_allowed?(billing_cycle: User::BillingDependency::YEARLY_PLAN)
      end
    end

    test "returns false if has Enterprise yearly transaction" do
      disable_feature_flag(:remove_org_annual_discount)

      jan_1st_2023 = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")
      jan_2nd_2024 = GitHub::Billing.date_in_timezone Date.parse("2024-01-02")
      team_org = travel_to jan_1st_2023 do
        org = create(:organization, plan_duration: User::BillingDependency::MONTHLY_PLAN, plan: "business")
        create(:billing_transaction,
          user: org,
          plan_name: "business",
          renewal_frequency: :monthly,
          amount_in_cents: 4_00
        )
        create(:billing_transaction,
          user: org,
          plan_name: "business_plus",
          renewal_frequency: :yearly,
          amount_in_cents: 231_00
        )
        create(:billing_transaction,
          user: org,
          plan_name: "business",
          renewal_frequency: :monthly,
          amount_in_cents: 4_00
        )
        assert org.annual_discount_allowed?(billing_cycle: User::BillingDependency::YEARLY_PLAN)
        assert org.annual_discount_allowed?(billing_cycle: User::BillingDependency::YEARLY_PLAN, target_date: 3.months.from_now.to_date)
        refute org.annual_discount_allowed?(billing_cycle: User::BillingDependency::YEARLY_PLAN, target_date: 1.year.from_now.to_date)

        org
      end

      travel_to jan_2nd_2024 do
        refute team_org.annual_discount_allowed?(plan: GitHub::Plan.business_plus, billing_cycle: User::BillingDependency::YEARLY_PLAN)
      end
    end
  end

  context "#successful_paid_payments?" do
    test "returns false for users with no successful paid transactions" do
      create(:billing_transaction, :failed, amount_in_cents: 4, user: @user)
      create(:billing_transaction, amount_in_cents: 0, user: @user)

      refute @user.successful_paid_payments?
    end

    test "returns true for users with the minimum count of successful paid transactions" do
      create(:billing_transaction, amount_in_cents: 4, user: @user)
      assert @user.successful_paid_payments?
      refute @user.successful_paid_payments?(minimum_payment_count: 2)

      create(:billing_transaction, amount_in_cents: 4, user: @user)
      assert @user.successful_paid_payments?(minimum_payment_count: 2)
      refute @user.successful_paid_payments?(minimum_payment_count: 3)

      create(:billing_transaction, amount_in_cents: 4, user: @user)
      assert @user.successful_paid_payments?(minimum_payment_count: 3)
      refute @user.successful_paid_payments?(minimum_payment_count: 4)
    end

    test "returns true for users with successful paid transactions after the start date" do
      create(:billing_transaction, amount_in_cents: 4, user: @user, created_at: GitHub::Billing.today)

      assert @user.successful_paid_payments?(start_date: GitHub::Billing.today - 1.day)
      refute @user.successful_paid_payments?(start_date: GitHub::Billing.today + 1.day)
    end
  end

  context "#invoiced?" do
    if GitHub.billing_enabled?
      test "returns false for org owned by business using card billing type" do
        @business.customer.update_attribute(:billing_type, "card")
        @business.add_organization(@organization)
        @organization.reload

        assert_predicate @business, :self_serve_payment?
        assert_predicate @organization, :delegate_billing_to_business?
        refute_predicate @organization, :invoiced?
      end

      test "returns true for org owned by business using invoice billing type" do
        @business.customer.update_attribute(:billing_type, "invoice")
        @business.add_organization(@organization)
        @organization.reload

        assert_predicate @business, :invoiced?
        assert_predicate @organization, :delegate_billing_to_business?
        assert_predicate @organization, :invoiced?
      end

      test "returns false for standalone org using card billing type" do
        @organization.update_attribute(:billing_type, "card")
        @organization.reload

        refute_predicate @organization, :delegate_billing_to_business?
        refute_predicate @organization, :invoiced?
      end

      test "returns true for standalone org using invoice billing type" do
        @organization.update_attribute(:billing_type, "invoice")

        refute_predicate @organization, :delegate_billing_to_business?
        assert_predicate @organization, :invoiced?
      end
    end
  end

  context "#has_billing_record?" do
    test "returns false if an account has no Zuora account" do
      user = create(:paypal_user)
      refute user.zuora_account?

      refute user.has_billing_record?
    end

    test "returns true if an account has a zuora account" do
      create(:customer_account, :zuora, user: @user)
      @user.reload

      assert @user.has_billing_record?
    end
  end

  context "#upgrading_from_trial?" do
    test "returns true when there is an active trial for the organization" do
      Billing::EnterpriseCloudTrial.new(@organization).create

      assert @organization.upgrading_from_trial?
    end

    test "returns true when trial is not active but was already present before" do
      org = @organization
      pending_plan_change = create(:billing_pending_plan_change, active_on: 10.days.ago, is_complete: true)
      create(:billing_plan_trial, :active, user: org, pending_plan_change: pending_plan_change)

      assert org.upgrading_from_trial?
    end

    test "returns false when current plan is business plus" do
      org = create(:business_plus_organization)
      pending_plan_change = create(:billing_pending_plan_change, active_on: 10.days.ago, is_complete: true)
      create(:billing_plan_trial, :active, user: org, pending_plan_change: pending_plan_change)

      refute org.upgrading_from_trial?
    end

    test "returns false when never had a trial" do
      refute @organization.upgrading_from_trial?
    end
  end

  context "#autopay_disabled_by_india_rbi?" do
    test "returns false for invoiced customers" do
      invoiced_user = create :user, :invoiced
      refute invoiced_user.autopay_disabled_by_india_rbi?
    end

    test "returns false for users without existing zuora service" do
      refute @user.autopay_disabled_by_india_rbi?
    end

    test "returns false for customers with auto pay enabled" do
      india_based_user = create :india_based_credit_card_user
      create :billing_plan_subscription, :zuora,
        user: india_based_user
      refute india_based_user.reload.autopay_disabled_by_india_rbi?
    end

    test "returns true for users with zuora service and auto pay disabled due to india rbi" do
      india_rbi_disabled_user = create :india_based_credit_card_user, :disabled_by_india_rbi
      create :billing_plan_subscription, :zuora,
        user: india_rbi_disabled_user
      assert india_rbi_disabled_user.reload.autopay_disabled_by_india_rbi?
    end
  end

  context "#payment_processor_email" do
    test "returns email for a user" do
      assert_equal @user.email, @user.payment_processor_email
    end

    test "returns business billing_email for an organization owned by a business" do
      create(:business, organizations: [@organization])
      @organization.reload
      refute_nil @organization.business
      assert_equal @organization.business.billing_email, @organization.payment_processor_email
    end
  end

  context "#payment_processor_account_name" do
    test "returns login for a user" do
      assert_equal @user.login, @user.payment_processor_account_name
    end

    test "returns business name for an organization owned by a business" do
      create(:business, organizations: [@organization])
      @organization.reload
      refute_nil @organization.business
      assert_equal @organization.business.name, @organization.payment_processor_account_name
    end
  end

  context "#update_billing_date" do
    test "updates billing date" do
      user = @user
      billing_date = Date.today + 2.days
      user.update_billing_date(next_billing_date: billing_date, billing_attempts: 0)

      assert_equal billing_date, user.billed_on
    end
  end

  context "#customer_for" do
    test "returns general-purpose customer when purpose is not sponsors" do
      user = @credit_card_user
      assert_equal user.customer, user.customer_for(nil)
      assert_equal user.customer, user.customer_for(:general)
      assert_equal user.customer, user.customer_for("general")
    end

    test "returns sponsors-purpose customer when purpose passed is sponsors" do
      org = create(:credit_card_org, :sponsors_invoiced)
      assert_equal org.sponsors_customer, org.customer_for(:sponsors)
      assert_equal org.sponsors_customer, org.customer_for("sponsors")
    end

    test "returns business's customer when purpose passsed is not sponsors and delegate_to_business is true" do
      org = create(:enterprise_linked_org, :sponsors_invoiced)
      assert_equal org.business.customer, org.customer_for(nil, delegate_to_business: true)
      assert_equal org.business.customer, org.customer_for(:general, delegate_to_business: true)
      assert_equal org.business.customer, org.customer_for("general", delegate_to_business: true)
    end

    test "returns org's sponsors-purpose customer even when delegate_to_business is true" do
      org = create(:enterprise_linked_org, :sponsors_invoiced)
      assert_equal org.sponsors_customer, org.customer_for(:sponsors, delegate_to_business: true)
      assert_equal org.sponsors_customer, org.customer_for("sponsors", delegate_to_business: true)
    end
  end

  context "#billing_customer" do
    test "returns customer for user" do
      user = @credit_card_user
      assert_equal user.customer, user.billing_customer
    end

    test "returns customer for organization" do
      org = create(:credit_card_org)
      assert_equal org.customer, org.billing_customer
    end

    test "returns customer for business when delegated" do
      org = create(:enterprise_linked_org)
      assert_equal org.business.customer, org.billing_customer
    end
  end

  context "#update_plan_if_addons_changed" do
    test "does nothing if the user has addons on the `pro` plan" do
      user = create(:user, plan: GitHub::Plan::PRO, billing_attempts: 1)
      create(:billing_subscription_item, account: user)

      user.update_plan_if_addons_changed

      assert_equal GitHub::Plan::PRO, user.plan.name
      assert_equal 1, user.billing_attempts
    end

    test "sets the plan to `free_with_addons` if the user has addons on the `free` plan" do
      org = create(:free_organization, plan: GitHub::Plan::FREE, billing_attempts: 1)
      create(:billing_subscription_item, account: org)

      org.update_plan_if_addons_changed

      assert_equal GitHub::Plan::FREE_WITH_ADDONS, org.plan.name
      assert_equal 1, org.billing_attempts
    end

    test "sets the plan to `free` if the user has no addons on the `free_with_addons` plan" do
      org = create(:free_organization, plan: GitHub::Plan::FREE_WITH_ADDONS, billing_attempts: 1)

      org.update_plan_if_addons_changed

      assert_equal GitHub::Plan::FREE, org.plan.name
    end

    test "sets the plan to `free_with_addons` if the user has addons and a pending plan change to `free`" do
      user = create(:user, plan: GitHub::Plan::PRO, billing_attempts: 1)
      create(:billing_subscription_item, account: user)

      pending_change = create :billing_pending_plan_change,
        active_on: GitHub::Billing.today,
        plan: GitHub::Plan::FREE,
        user: user,
        actor: user
      pending_change.run

      assert_equal GitHub::Plan::FREE_WITH_ADDONS, user.plan.name
      assert_equal 1, user.billing_attempts
    end

    test "sets the plan to `free` if the user has no addons and a pending plan change to `free_with_addons`" do
      user = create(:user, plan: GitHub::Plan::PRO, billing_attempts: 1)

      pending_change = create :billing_pending_plan_change,
        active_on: GitHub::Billing.today,
        plan: GitHub::Plan::FREE_WITH_ADDONS,
        user: user,
        actor: user
      pending_change.run

      assert_equal GitHub::Plan::FREE, user.plan.name
    end

    test "sets the plan to `free_with_addons` if the user has addons and the plan is manually changed to `free`" do
      user = create(:user, plan: GitHub::Plan::PRO, billing_attempts: 1)
      create(:billing_subscription_item, account: user)

      user.update(plan: GitHub::Plan::FREE)

      assert_equal GitHub::Plan::FREE_WITH_ADDONS, user.plan.name
      assert_equal 1, user.billing_attempts
    end

    test "sets the plan to `free` if the user has no addons and the plan is manually changed to `free_with_addons`" do
      user = create(:user, plan: GitHub::Plan::PRO, billing_attempts: 1)

      user.update(plan: GitHub::Plan::FREE_WITH_ADDONS)

      assert_equal GitHub::Plan::FREE, user.plan.name
    end

    test "does not try to update a user that was deleted, even if their plan changes" do
      sponsor = create(:credit_card_user, plan_subscription: @plan_subscription, plan: GitHub::Plan.free_with_addons)
      subscription_item = create(:sponsorship, sponsor: sponsor).subscription_item

      assert_difference(-> { Billing::SubscriptionItem.active.count }, -1) do
        sponsor.destroy! # causes active subscription item to be deleted, which would normally trigger a plan update
      end

      refute Billing::SubscriptionItem.exists?(subscription_item.id)
    end
  end

  context "#cancel_advanced_security_on_downgrade" do
    test "cancels an Advanced Security subscription item when downgrading from Enterprise to Team plan" do
      org = create(:credit_card_organization, plan: GitHub::Plan.business_plus)
      owner = org.owner
      enable_feature_flag(:ghas_self_serve_orgs, org)

      org.subscribe_to_advanced_security(seats: 5, actor: owner, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
      assert org.reload.advanced_security_purchased_for_entity?
      assert org.has_active_advanced_security_subscription?

      org.update!(plan: GitHub::Plan.business)

      org.reload
      refute org.has_active_advanced_security_subscription?
      refute org.advanced_security_purchased_for_entity?
    end

    test "cancels an Advanced Security subscription item when downgrading from Enterprise to Free plan" do
      org = create(:credit_card_organization, plan: GitHub::Plan.business_plus)
      owner = org.owner
      enable_feature_flag(:ghas_self_serve_orgs, org)

      org.subscribe_to_advanced_security(seats: 5, actor: owner, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
      assert org.reload.advanced_security_purchased_for_entity?
      assert org.has_active_advanced_security_subscription?

      org.update!(plan: GitHub::Plan.free)

      org.reload
      refute org.has_active_advanced_security_subscription?
      refute org.advanced_security_purchased_for_entity?
    end
  end

  context "#outside_collaborator_ids" do
    test "filters out collaborators on advisory workspace repos" do
      # Create a public repo
      repo = create(:repository, :minimal, owner: @organization)

      # Create external user
      external_user = @user

      # Create a draft repo advisory on the public repo, and create a
      # _private_ workspace repo for it
      advisory = create(:draft_repository_advisory, :with_workspace,
                        repository: repo)

      # Add an external user as a collaborator on the advisory, which also
      # grants write ability on the private workspace repo (Note advisory
      # collaborator is different than repo collaborator)
      advisory.add_collaborator(external_user)
      repo_invitation = RepositoryInvitation.find_by(invitee_id: external_user.id, repository_id: advisory.workspace_repository.id)
      repo_invitation&.accept!(acceptor: external_user)

      # Verify workspace repo is private and writable by the external user
      assert advisory.readable_by?(external_user)
      refute_nil advisory.workspace_repository
      assert advisory.workspace_repository.private?
      assert advisory.workspace_repository.writable_by?(external_user)

      # Verify workspace collaborator _is not_ counted as an outside user
      outside_collaborator_ids = @organization.outside_collaborator_ids
      refute_includes outside_collaborator_ids, external_user.id
    end

    test "uses cached ids when collaborator_cache_read FF is enabled" do
      enable_feature_flag(:collaborator_cache_read)
      outside_collaborator = create(:user)
      OrganizationCollaborator.create(user_id: outside_collaborator.id, organization_id: @organization.id, private: true)
      assert_equal [outside_collaborator.id], @organization.outside_collaborator_ids(include_forks: false).to_a
      assert_equal [outside_collaborator.id], @organization.outside_collaborator_ids(on_repositories_with_visibility: [:private], include_forks: false).to_a
      assert_equal [], @organization.outside_collaborator_ids(on_repositories_with_visibility: [:private], actor_ids: [@user.id], include_forks: false).to_a
      assert_equal [], @organization.outside_collaborator_ids(on_repositories_with_visibility: [:public], include_forks: false).to_a
    end

    test "uses experiment for cached ids when collaborator_cache_write FF is enabled and collaborator_cache_read FF is disabled" do
      enable_feature_flag(:collaborator_cache_write)
      disable_feature_flag(:collaborator_cache_read)
      GitHub::Experiment.raise_on_mismatches = true
      outside_collaborator = @user
      OrganizationCollaborator.create(user_id: outside_collaborator.id, organization_id: @organization.id, private: true)
      assert_raises Scientist::Experiment::MismatchError do
        @organization.outside_collaborator_ids
      end
    end
  end

  context "#can_be_authorized?" do
    test "returns true for non tier one users and credit card payment method" do
      create(:billing_budget, owner: @non_trusted_user)

      assert @non_trusted_user.can_be_authorized?
    end

    test "returns true for orgs" do
      org = create(
        :organization,
        :zuora,
        plan_subscription: create(:billing_plan_subscription, :zuora),
      )
      create(:billing_budget, owner: org)

      assert org.can_be_authorized?
    end

    test "returns false for orgs if metered via Azure" do
      org = @organization
      org.customer = create(:customer, metered_via_azure: true, azure_subscription_id: SecureRandom.uuid)

      create(:billing_budget, owner: org)

      refute org.can_be_authorized?
    end

    test "returns false for users without a payment method" do
      refute @trusted_user.can_be_authorized?
    end

    test "returns true for paypal users" do
      paypal_user = create(:paypal_user)

      refute paypal_user.can_be_authorized?
    end

    test "returns false for users in dunning on a paid plan with a recent history of successful payments" do
      today = Date.new(2023, 1, 1)
      travel_to today do
        @credit_card_user.update(plan: "pro", billing_attempts: 1)
        create(:billing_budget, owner: @credit_card_user)
        create(:billing_transaction, user: @credit_card_user, amount_in_cents: 4_00, last_status: :settled, created_at: today - 3.months)
        create(:billing_transaction, user: @credit_card_user, amount_in_cents: 4_00, last_status: :settled, created_at: today - 2.months)
        create(:billing_transaction, user: @credit_card_user, amount_in_cents: 4_00, last_status: :settled, created_at: today - 1.month)
        create(:billing_transaction, user: @credit_card_user, amount_in_cents: 4_00, last_status: :failed)

        refute_predicate @credit_card_user, :can_be_authorized?
      end

      # Using the Time.current explicitly rather than using GitHub::Billing.today
      # Due to the date landing on the day boundary, it can sometimes cause us to be
      # on the wrong side of the day boundary, especially when doing time arithmetic.
      travel_to today + 1.month + 1.day do
        assert_predicate @credit_card_user, :can_be_authorized?
      end
    end
  end

  context "#validate_purchases_allowed" do
    test "allowed for user in good standing" do
      result = @user.validate_purchases_allowed

      assert result.success?
    end

    test "not allowed for spammy users" do
      user = create(:spammy_user)
      assert user.spammy?

      result = user.validate_purchases_allowed

      assert result.failed?
      assert result.error_message.include?("Your account is flagged and unable to make purchases")
    end

    test "not allowed for spammy actors when actor is provided" do
      user = create(:spammy_user)
      org = @organization
      assert user.spammy?
      refute org.spammy?

      result = org.validate_purchases_allowed(actor: user)

      assert result.failed?
      assert result.error_message.include?("Your account is flagged and unable to make purchases")
    end

    test "allowed for disabled users when check_disabled is false" do
      user = create(:billing_locked_user)
      assert user.disabled?

      result = user.validate_purchases_allowed(check_disabled: false)

      assert result.success?
    end

    test "not allowed for disabled users when check_disabled is true" do
      user = create(:billing_locked_user)
      assert user.disabled?

      result = user.validate_purchases_allowed(check_disabled: true)

      assert result.failed?
      assert result.error_message.include?("Your account is currently locked from purchases")
    end

    test "allowed for users in dunning when check_dunning is false" do
      user = create(:user, billing_attempts: 1)
      assert user.dunning?

      result = user.validate_purchases_allowed(check_dunning: false)

      assert result.success?
    end

    test "not allowed for users in dunning when check_dunning is true" do
      user = create(:user, billing_attempts: 1)
      assert user.dunning?

      result = user.validate_purchases_allowed(check_dunning: true)

      assert result.failed?
      assert result.error_message.include?("Your account is currently locked from purchases")
    end

    test "allowed for trade restricted users when check_trade_restrictions is false" do
      user = create(:user, :partially_trade_restricted)
      assert user.has_any_trade_restrictions?

      result = user.validate_purchases_allowed(check_trade_restrictions: false)

      assert result.success?
    end

    test "not allowed for trade restricted users when check_trade_restrictions is true" do
      user = create(:user, :partially_trade_restricted)
      assert user.has_any_trade_restrictions?

      result = user.validate_purchases_allowed(check_trade_restrictions: true)

      assert result.failed?
      assert result.error_message.include?("Due to U.S. trade controls law restrictions, your GitHub account has been restricted")
    end
  end

  context "#reset_billing_attempts" do
    test "works even when the user has invalid budgets" do
      user = create(:credit_card_user, billing_attempts: 3)
      budget = user.budgets.build(product: "codespaces", enforce_spending_limit: true, spending_limit_in_subunits: -1)

      refute budget.valid?
      assert_equal 1, user.budgets.size

      assert_nothing_raised do
        user.reset_billing_attempts
      end

      assert_equal 0, user.reload.billing_attempts
    end
  end
end

class EmuUserBillingDependencyTest < GitHub::BillingTestCase
  include UserBillingSubscriptionSharedTests
  include UserBillingDependencySharedTests

  include GitHub::ZuoraTestHelper
  include HydroTestHelpers

  fixtures do
    @user = create(:emu, :owner)
    @business = @user.enterprise_managed_business

    @organization = create(:organization, business: @business)
  end

  setup do
    @expected_user_plan = GitHub::Plan.find(GitHub::Plan::EMU_USER, account: @user)
    ActionMailer::Base.deliveries.clear
  end
end unless GitHub.single_business_environment?

class MultiTenantUserBillingDependencyTest < GitHub::BillingTestCase
  include UserBillingSubscriptionSharedTests
  include UserBillingDependencySharedTests

  include GitHub::ZuoraTestHelper
  include HydroTestHelpers

  fixtures do
    on_multi_tenant_enterprise do
      @user = create(:emu, :owner)
      @business = @user.enterprise_managed_business

      @organization = create(:organization, business: @business)
    end
  end

  setup do
    @expected_user_plan = GitHub::Plan.find(GitHub::Plan::EMU_USER, account: @user)
    on_multi_tenant_enterprise
    ActionMailer::Base.deliveries.clear
  end
end unless GitHub.single_business_environment?

class UserBillingDependencyScopesTest < GitHub::BillingTestCase
  fixtures do
    @organization = create(:organization)
    @user = create(:user)
    @credit_card_user = create(:credit_card_user)
    @invoiced_organization = create(:invoiced_organization)

    unless GitHub.single_business_environment?
      @business = create(:business)
      @emu_business = create(:business, :enterprise_managed)
      @emu_user = create(:emu, business: @emu_business)
      @emu_org = create(:organization, business: @emu_business)
    end
  end

  context ".on_paid_plan" do
    test "includes users and orgs on a paid GitHub plan" do
      refute_predicate @user, :paid_plan?, "need a user on a free plan"
      assert_predicate @organization, :paid_plan?, "need an org on a paid plan"
      assert_predicate @invoiced_organization, :paid_plan?
      paid_user = create(:paid_user)
      unless GitHub.single_business_environment?
        free_business = create(:business)
        free_business.downgrade_to_free_plan
        free_org = create(:organization, login: "orgWithFreeBusiness", business: free_business)
        refute_predicate free_org.reload, :paid_plan?, "need an org with a business on a free plan"
      end
      user_ids = [paid_user, @user, @organization, @invoiced_organization].map(&:id)
      user_ids.concat([@emu_org.id, free_org.id]) unless GitHub.single_business_environment?

      result = User.on_paid_plan.where(id: user_ids)

      assert result.all?(&:paid_plan?), "expected scope to be in sync with #paid_plan? instance method, but the " \
        "scope returned a user/org where #paid_plan? is false: #{result.reject(&:paid_plan?).map(&:to_s)}"
      result_ids = result.map(&:id)
      assert_includes result_ids, paid_user.id, "expected #{paid_user.plan} user to be included"
      refute_includes result_ids, @user.id, "expected #{@user.plan} user to be excluded"
      assert_includes result_ids, @organization.id, "expected #{@organization.plan} org to be included"
      assert_includes result_ids, @invoiced_organization.id, "expected invoiced org to be included"
      unless GitHub.single_business_environment?
        assert_includes result_ids, @emu_org.id, "expected org whose business is on a paid plan to be included"
        refute_includes result_ids, free_org.id,
          "expected org whose business downgrade to the free plan to be excluded"
      end
    end
  end

  context ".without_billing_email" do
    test "includes organizations and users without a billing email" do
      assert_predicate @organization.billing_email, :present?, "need an org that does have a billing email"
      org_without_email = create(:organization)
      org_without_email.update_attribute(:organization_billing_email, nil)
      user_without_email = @user
      user_without_email.update_attribute(:organization_billing_email, "")
      user_ids = [@organization, org_without_email, user_without_email].map(&:id)

      result = User.without_billing_email.where(id: user_ids)

      assert_includes result, org_without_email
      assert_includes result, user_without_email
      refute_includes result, @organization
      assert_equal org_without_email, org_without_email.admin.billingless_org,
        "want the scope to stay in sync with instance method #billingless_org"
    end
  end

  context ".delegates_billing_to_business" do
    if GitHub.single_business_environment?
      test "returns an empty list" do
        assert_empty User.delegates_billing_to_business
      end
    else
      test "includes organizations with businesses" do
        assert_nil @organization.business, "need an org without a business"
        org_with_business = create(:organization, business: @business)
        user_ids = [@organization, @user, org_with_business].map(&:id)

        result = User.delegates_billing_to_business.where(id: user_ids)

        assert_includes result, org_with_business
        refute_includes result, @user
        refute_includes result, @organization
        assert result.all?(&:delegate_billing_to_business?),
          "want the scope to stay in sync with instance method #delegate_billing_to_business?"
      end
    end
  end

  context ".disabled" do
    test "returns users with disabled=true" do
      refute_predicate @user, :disabled?, "need a non-disabled account"
      disabled_account = @credit_card_user
      disabled_account.disable!
      refute_predicate @organization, :disabled?, "need a non-disabled org"
      disabled_org = create(:credit_card_organization, :with_billing_locked)

      if GitHub.flipper[:use_billing_locked_rather_than_disabled].enabled?
        disabled_account.customer.lock_billing
        disabled_org.customer.lock_billing
      end

      user_ids = [@user, disabled_account, @organization, disabled_org].map(&:id)

      result = User.disabled.where(id: user_ids)

      assert result.all? { |user| user.disabled? }, "expected scope to be in sync with #disabled? method"
      assert_includes result, disabled_account
      assert_includes result, disabled_org
      refute_includes result, @user
      refute_includes result, @organization
    end
  end

  context ".not_disabled" do
    test "returns users with disabled=false or the disabled field is null" do
      refute_predicate @user, :disabled?, "need a non-disabled account"
      disabled_account = @credit_card_user
      disabled_account.disable!
      refute_predicate @organization, :disabled?, "need a non-disabled org"
      disabled_org = create(:credit_card_organization, :with_billing_locked)
      null_disabled_account = create(:user)
      null_disabled_account.update_attribute(:disabled, nil)
      if GitHub.flipper[:use_billing_locked_rather_than_disabled].enabled?
        disabled_account.customer.lock_billing
        disabled_org.customer.lock_billing
      end
      user_ids = [@user, disabled_account, @organization, disabled_org, null_disabled_account].map(&:id)

      result = User.not_disabled.where(id: user_ids)

      assert result.none? { |user| user.disabled? }, "expected no disabled=true users to be returned by scope"
      refute_includes result, disabled_account
      refute_includes result, disabled_org
      assert_includes result, @user, "should include user whose account is not disabled"
      assert_includes result, @organization, "should include org whose account is not disabled"
      assert_includes result, null_disabled_account, "should include user whose account has no disabled value"
    end
  end

  context ".needs_billed" do
    test "not billed if plan is nil" do
      @organization.destroy
      user = create :user, billed_on: GitHub::Billing.today - 1.week
      user.send :write_attribute, :plan, "free"
      user.save
      assert_equal 1, User.needs_billed.size
    end

    test "not billed if plan is free" do
      @organization.destroy
      create :user, plan: "free", billed_on: GitHub::Billing.today - 1.week
      assert_equal 1, User.needs_billed.size
    end

    test "not billed if payment_type is not credit_card" do
      @organization.destroy
      create :user, plan: "small", billing_type: "invoice", billed_on: GitHub::Billing.today - 1.week
      assert_equal 1, User.needs_billed.size
    end

    test "not billed if user is suspended" do
      @organization.destroy
      create :user, plan: "pro", billed_on: GitHub::Billing.today - 1.week, suspended_at: GitHub::Billing.now
      assert_equal 1, User.needs_billed.size
    end

    test "not billed if user has billing locked" do
      @organization.destroy
      credit_card_user = create :credit_card_user, :with_billing_locked, plan: "pro", billed_on: GitHub::Billing.today - 1.week
      if GitHub.flipper[:use_billing_locked_rather_than_disabled].enabled?
        credit_card_user.customer.lock_billing
      end
      assert_equal 1, User.needs_billed.size
    end

    test "not billed if organization has been soft-deleted" do
      assert_equal 2, User.needs_billed.size
      @organization.soft_delete!
      assert_equal 1, User.needs_billed.size
    end

    test "billed if not disabled" do
      @organization.destroy
      create :user, plan: "small", billed_on: GitHub::Billing.today - 1.week
      assert_equal 2, User.needs_billed.size
    end

    test "not billed if user has a plan subscription with a zuora subscription" do
      @organization.destroy
      only = [TradeControls::ComplianceCheckJob, ProcessEmailDomainForReputationDataJob]
      perform_enqueued_jobs(only: only) do
        user = create :credit_card_user, plan: "small", billed_on: GitHub::Billing.today - 1.week
        create :billing_plan_subscription, :zuora, user: user

        assert_equal 1, User.needs_billed.size
      end
    end

    test "billed if user has a zuora_subscription but no payment_method" do
      @organization.destroy
      only = [TradeControls::ComplianceCheckJob, ProcessEmailDomainForReputationDataJob]
      perform_enqueued_jobs(only: only) do
        user = create :user, plan: "small", billed_on: GitHub::Billing.today - 1.week
        create :billing_plan_subscription, :zuora, user: user

        assert_nil user.payment_method
        assert_equal 2, User.needs_billed.size
      end
    end

    test "not billed if user has a subscription through Apple IAP and no payment method" do
      user = create :user, plan: GitHub::Plan.pro, billed_on: GitHub::Billing.today - 1.week
      plan_subscription = create :billing_plan_subscription, :zuora, :apple_iap, user: user

      assert_nil user.payment_method
      assert plan_subscription.apple_iap_subscription?
      refute User.needs_billed.where(id: user.id).exists?
    end

    test "not billed if user has a subscription through Apple IAP, no payment method and no zuora subscription" do
      user = create :user, plan: GitHub::Plan.pro, billed_on: GitHub::Billing.today - 1.week
      plan_subscription = create :billing_plan_subscription, :apple_iap, user: user

      assert_nil user.payment_method
      assert plan_subscription.apple_iap_subscription?
      refute User.needs_billed.where(id: user.id).exists?
    end
  end
end

class UserBillingDepdendencySubscriptionsTest < GitHub::BillingTestCase
  fixtures do
    @user = create(:user)
    @sponsors_plan_sub = create(:billing_plan_subscription, :sponsors_invoiced, user: @user)
    @general_plan_sub = create(:billing_plan_subscription, user: @user)
  end

  context "#plan_subscription_for" do
    test "returns Sponsors-specific plan subscription when purpose=sponsors" do
      assert_equal @sponsors_plan_sub, @user.reload.plan_subscription_for(:sponsors)
    end

    test "returns general-purpose plan subscription when purpose=general" do
      assert_equal @general_plan_sub, @user.reload.plan_subscription_for(:general)
    end

    test "returns nil when requested plan subscription does not exist" do
      user = create(:user)
      assert_nil user.plan_subscription, "need a user with no general-purpose plan sub"
      assert_nil user.plan_subscription_for(:general)

      assert_nil user.sponsors_plan_subscription, "need a user with no Sponsors-specific plan sub"
      assert_nil user.plan_subscription_for(:sponsors)
    end

    test "returns nil when general-purpose plan subscription exists but purpose=sponsors was given" do
      @sponsors_plan_sub.destroy
      assert_nil @user.sponsors_plan_subscription, "need a user with no Sponsors-specific plan sub"
      assert_nil @user.reload.plan_subscription_for(:sponsors)

      assert_equal [@general_plan_sub], @user.plan_subscriptions
      assert_nil @user.plan_subscription_for(:sponsors)
    end

    test "does not make additional queries when plan_subscriptions is already loaded" do
      assert_same_elements [@sponsors_plan_sub, @general_plan_sub], @user.reload.plan_subscriptions

      assert_query_count(0) do
        assert_equal @general_plan_sub, @user.plan_subscription_for(:general)
        assert_equal @sponsors_plan_sub, @user.plan_subscription_for(:sponsors)
      end
    end
  end
end

class UserBillingDependencyPagesTest < GitHub::BillingTestCase
  fixtures do
    @business_plus_org = create(:business_plus_org)
    @free_org = create(:free_org)
    @pro_user = create(:user, plan: "pro")
  end

  context "#delete_or_restore_pages_on_plan_change" do
    test "when downgrading from business_plus, unpublishes private pages" do
      enable_feature_flag(:pages_soft_deletion)
      owner = @business_plus_org
      repo = create(:private_repository, owner: owner)

      create(:private_page, repository: repo)
      assert repo.page
      refute repo.deleted_at

      perform_enqueued_jobs only: [DestroyPrivatePageJob, RestoreSoftDeletedPagesJob] do
        owner.update!(plan: "business")
      end
      repo.reload

      assert repo.page
      assert repo.page.deleted_at
    end

    test "When downgrading from business_plus, unpublishes private pages. Restores them when repo and page are public" do
      enable_feature_flag(:pages_soft_deletion)
      owner = @business_plus_org

      page = create(:private_page, :built, owner: owner)
      repo = page.repository
      refute repo.page.deleted_at

      perform_enqueued_jobs only: [DestroyPrivatePageJob, RestoreSoftDeletedPagesJob] do
        owner.update!(plan: "business")
      end
      repo.reload

      assert repo.page
      assert repo.page.deleted_at

      # Switch repo and page to public
      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { repo.set_visibility(actor: repo.owner, visibility: Repository::PUBLIC_VISIBILITY) }
      repo.reload
      repo.page.reload

      assert repo.page
      refute repo.page.deleted_at
    end

    test "when downgrading to free, unpublishes pages of private repos" do
      enable_feature_flag(:pages_soft_deletion)
      user = @pro_user
      repo = create(:private_repository, owner: user)

      create(:page, repository: repo, public: true)
      assert repo.page
      refute repo.deleted_at

      perform_enqueued_jobs only: [DestroyPrivatePageJob, RestoreSoftDeletedPagesJob] do
        user.update(plan: "free")
      end
      repo.reload

      assert repo.page
      assert repo.page.deleted_at
    end

    test "when downgrading from pro to free when repo is private with public page, unpublishes pages. Restore them when repo and page are switched to public" do
      enable_feature_flag(:pages_soft_deletion)
      user = @pro_user

      repo = create(:private_repository, owner: user)
      page = create(:page, :built, repository: repo)
      repo = page.repository
      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { repo.set_visibility(actor: repo.owner, visibility: Repository::PRIVATE_VISIBILITY) }

      assert repo.page
      refute repo.page.deleted_at
      perform_enqueued_jobs only: [DestroyPrivatePageJob, RestoreSoftDeletedPagesJob] do
        user.update(plan: "free")
      end

      repo.reload
      assert repo.page
      assert repo.page.deleted_at

      repo.errors.clear

      # Switch repo and page to public
      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { repo.set_visibility(actor: repo.owner, visibility: Repository::PUBLIC_VISIBILITY) }
      repo.reload
      repo.page.reload

      assert repo.page
      refute repo.page.deleted_at
    end

    test "when downgrading to free_with_addons, unpublishes pages of private repos" do
      enable_feature_flag(:pages_soft_deletion)
      user = @pro_user
      repo = create(:private_repository, owner: user)

      create(:page, repository: repo, public: true)
      assert repo.page
      refute repo.deleted_at

      perform_enqueued_jobs only: [DestroyPrivatePageJob, RestoreSoftDeletedPagesJob] do
        user.update(plan: "free_with_addons")
      end
      repo.reload

      assert repo.page
      assert repo.page.deleted_at
    end

    test "when downgrading to free_with_addons, unpublishes pages of private repos, re enables page to public when switch to public repo" do
      enable_feature_flag(:pages_soft_deletion)
      user = @pro_user

      page = create(:private_page, :built, owner: user)
      repo = page.repository
      repo.public = false
      repo.save!

      assert repo.page
      refute repo.page.deleted_at

      perform_enqueued_jobs only: [DestroyPrivatePageJob, RestoreSoftDeletedPagesJob] do
        user.update(plan: "free_with_addons")
      end
      repo.reload

      assert repo.page
      assert repo.page.deleted_at

      # Switch repo and page to public
      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { repo.set_visibility(actor: repo.owner, visibility: Repository::PUBLIC_VISIBILITY) }
      repo.reload
      repo.page.reload

      assert repo.page
      refute repo.page.deleted_at
    end

    test "when downgrading to free_with_addons, unpublishes pages of private repos, switch back to higher plan" do
      enable_feature_flag(:pages_soft_deletion)
      user = @pro_user
      page = create(:page, :built, owner: user)
      repo = page.repository
      repo.public = false
      repo.save!

      assert repo.page
      refute repo.public
      refute repo.page.deleted_at

      perform_enqueued_jobs only: [DestroyPrivatePageJob, RestoreSoftDeletedPagesJob] do
        user.update(plan: GitHub::Plan::FREE)
      end
      repo.reload

      assert repo.page
      assert repo.page.deleted_at

      perform_enqueued_jobs only: [DestroyPrivatePageJob, RestoreSoftDeletedPagesJob] do
        user.update(plan: GitHub::Plan::PRO)
      end
      repo.reload

      assert repo.page
      refute repo.page.deleted_at
    end

    test "when upgrading, restores soft-deleted pages under a user and private repository" do
      enable_feature_flag(:pages_soft_deletion)
      user = create :user, plan: "free"

      public_page = create(:page, :built, owner: user, deleted_at: Time.zone.now)
      public_page_repo = public_page.repository
      public_page_repo.public = false
      public_page_repo.save!

      assert public_page_repo.page
      assert public_page_repo.page.deleted_at

      private_page = create(:private_page, :built, owner: user, deleted_at: Time.zone.now)
      private_page_repo = private_page.repository

      assert private_page_repo.page
      assert private_page_repo.page.deleted_at

      perform_enqueued_jobs only: [DestroyPrivatePageJob, RestoreSoftDeletedPagesJob] do
        user.update(plan: "pro")
        user.save!
      end

      private_page_repo.reload
      public_page_repo.reload

      # Assert private page and page of private repo are both restored
      assert private_page_repo.page
      assert private_page_repo.page.deleted_at
      assert public_page_repo.page
      refute public_page_repo.page.deleted_at
    end

    test "when upgrading, restores soft-deleted private pages" do
      enable_feature_flag(:pages_soft_deletion)
      owner = @free_org
      private_page_repo = create(:private_repository, owner: owner)
      private_repo = create(:private_repository, owner: owner)

      create(:private_page, repository: private_page_repo, deleted_at: Time.zone.now)
      assert private_page_repo.page
      assert private_page_repo.page.deleted_at

      create(:page, repository: private_repo, public: true, deleted_at: Time.zone.now)
      assert private_repo.page
      assert private_repo.page.deleted_at

      perform_enqueued_jobs only: [DestroyPrivatePageJob, RestoreSoftDeletedPagesJob] do
        owner.update(plan: "business-plus")
      end
      private_page_repo.reload
      private_repo.reload

      # Assert private page and page of private repo are both restored
      assert private_page_repo.page
      refute private_page_repo.deleted_at
      assert private_repo.page
      refute private_repo.deleted_at
    end

    test "when upgrading, restores soft-deleted pages of private repos" do
      enable_feature_flag(:pages_soft_deletion)
      owner = @free_org
      private_page_repo = create(:private_repository, owner: owner)
      private_repo = create(:private_repository, owner: owner)

      create(:private_page, repository: private_page_repo, deleted_at: Time.zone.now)
      assert private_page_repo.page
      assert private_page_repo.page.private?
      assert private_page_repo.page.deleted_at

      create(:page, repository: private_repo, public: true, deleted_at: Time.zone.now)
      assert private_repo.page
      assert private_repo.page.public?
      assert private_repo.page.deleted_at
      perform_enqueued_jobs only: [DestroyPrivatePageJob, RestoreSoftDeletedPagesJob] do
        owner.update(plan: "business")
      end
      private_page_repo.reload
      private_repo.reload

      # Assert private page stays soft deleted
      assert private_page_repo.page
      assert private_page_repo.page.deleted_at
      # Assert page of private repo is restored
      assert private_repo.page
      refute private_repo.page.deleted_at
    end
  end

  context "#delete_or_restore_pages" do
    test "enqueues job to restore pages on plan upgrade" do
      enable_feature_flag(:pages_soft_deletion)
      org = @free_org

      assert_enqueued_with(job: RestoreSoftDeletedPagesJob, args: [org]) do
        org.update!(plan: GitHub::Plan.business)
      end

      assert_enqueued_with(job: RestoreSoftDeletedPagesJob, args: [org]) do
        org.update!(plan: GitHub::Plan.business_plus)
      end
    end

    test "enqueues job to delete pages on plan downgrade" do
      enable_feature_flag(:pages_soft_deletion)
      org = @business_plus_org

      assert_enqueued_with(job: DestroyPrivatePageJob, args: [org]) do
        org.update!(plan: GitHub::Plan.free)
      end
    end
  end
end
