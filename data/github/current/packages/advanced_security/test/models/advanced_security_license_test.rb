# typed: true
# frozen_string_literal: true

require "test_helper"

class AdvancedSecurityLicenseTest < GitHub::TestCase
  include TurboghasHelpers

  fixtures do
    @user1 = create(:user)
    @user1_public_repo = create(:public_repository, id: 1, owner: @user1)
    @user1_private_repo = create(:private_repository, id: 2, owner: @user1)
    @user2 = create(:user)
    @user2_public_repo = create(:public_repository, id: 3, owner: @user2)
    @user2_private_repo = create(:private_repository, id: 4, owner: @user2)
    customer = create(:customer, payment_method_user: @user1, purpose: Customer::DEFAULT_PURPOSE)
    customer_account = create(:customer_account, :zuora, customer:, user: @user1)
    @org1 = create(:organization, customer_account:, admins: [@user1])
    @org1_repo_public = create(:public_repository, id: 5, owner: @org1)
    @org1_repo_private = create(:private_repository, id: 6, owner: @org1)
    @org1_inactive_repo = create(:private_repository, id: 7, owner: @org1, active: nil)
    @org2 = create(:organization, admins: [@user1])
    @org2_repo_public = create(:public_repository, id: 8, owner: @org2)
    @org2_repo_private = create(:private_repository, id: 9, owner: @org2)
    @org2_inactive_repo = create(:private_repository, id: 10, owner: @org2, active: nil)
    if GitHub.single_business_environment?
      GitHub::Enterprise.ensure_business!
      @business = GitHub.global_business
    else
      @business = create(:business, owners: [@user1])
    end
    @user3 = create(:user)
    @user4 = create(:user)
    @org3 = create :organization, admins: [@user1], business: @business, public_members: [@user3]
    @org4 = create :organization, admins: [@user1], business: @business, public_members: [@user4]

    unless GitHub.enterprise?
      @self_serve_business = create(:billing_plan_subscription, :business_owned).business
    end
    create(:billing_product_uuid, :advanced_security)
  end

  setup do
    stub_turboghas_summary(maximum_committers: 3, active_committers: 2)

    if !GitHub.enterprise?
      @org1.mark_advanced_security_as_purchased_for_entity(actor: @user1)
      @org2.mark_advanced_security_as_purchased_for_entity(actor: @user2)
      @self_serve_business_owner = @self_serve_business.owners.first
    end
    if GitHub.enterprise?
      @org1_repo_public.enable_advanced_security!(actor: @user1)
      @org2_repo_public.enable_advanced_security!(actor: @user1)

      GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(true)
    end
    @org1_repo_private.enable_advanced_security!(actor: @user1)
    @org2_repo_private.enable_advanced_security!(actor: @user1)

    Failbot.reports.clear
  end

  # For all methods try to make sure that all cases from https://github.com/github/code-scanning/issues/2895 are covered

  context "AdvancedSecurityLicense.billable_entity" do
    context "enterprise", enterprise_only: true do
      test "always returns global business" do
        assert_equal GitHub.global_business, AdvancedSecurityLicense.billable_entity(@business)
        assert_equal GitHub.global_business, AdvancedSecurityLicense.billable_entity(@org1)
        assert_equal GitHub.global_business, AdvancedSecurityLicense.billable_entity(@user1)
      end
    end

    context "dotcom", skip_enterprise: true do
      test "can request a summary from turboghas" do
        org5 = create(:organization, admin: @user1)
        org5.add_member(@user3)
        repo1 = create :private_repository, owner: org5
        org5.mark_advanced_security_as_purchased_for_entity(actor: @user1)

        stub_turboghas_summary(active_committers: 2)

        assert_equal org5.advanced_security_license.consumed_seats, 2
      end

      test "seat_usage_increase_if_advanced_security_enabled_for_all_repos returns data" do
        org5 = create(:organization, admin: @user1)
        org5.add_member(@user3)
        repo1 = create :private_repository, owner: org5
        org5.mark_advanced_security_as_purchased_for_entity(actor: @user1)

        stub_turboghas_summary(additional_committers: 1)

        assert_equal AdvancedSecurityLicense.seat_usage_increase_if_advanced_security_enabled_for_all_repos(owner: org5), 1
      end

      test "business returns itself" do
        assert_equal @business, AdvancedSecurityLicense.billable_entity(@business)
      end

      test "org not in business returns itself" do
        assert_equal @org1, AdvancedSecurityLicense.billable_entity(@org1)
      end

      test "org in business that has not purchased GHAS returns itself" do
        @business.mark_advanced_security_as_not_purchased_for_entity(actor: @user1)
        @org1.business = @business
        assert_equal @org1, AdvancedSecurityLicense.billable_entity(@org1)
      end

      test "org in business that has purchased GHAS returns business" do
        @business.mark_advanced_security_as_purchased_for_entity(actor: @user1)
        @org1.business = @business
        assert_equal @business, AdvancedSecurityLicense.billable_entity(@org1)
      end

      test "EMU in business that has purchased GHAS returns business" do
        owner = create(:user)
        emu_business = create(:business, :enterprise_managed)
        emu_business.mark_advanced_security_as_purchased_for_entity(actor: owner)
        emu_user = create(:emu, business: emu_business)

        assert_equal emu_business, AdvancedSecurityLicense.billable_entity(emu_user)
      end
    end
  end

  context "#seats" do
    context "enterprise", enterprise_only: true do
      test "not purchased" do
        GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(false)
        GitHub::Enterprise.license.stubs(:advanced_security_seats).returns(0)

        assert_equal 0, @business.advanced_security_license.seats
        assert_equal 0, @org1.advanced_security_license.seats
        assert_equal 0, @user1.advanced_security_license.seats

        # even if seats explicitly set (which is not allowed by the license validation)
        GitHub::Enterprise.license.stubs(:advanced_security_seats).returns(15)

        assert_equal 0, @business.advanced_security_license.seats
        assert_equal 0, @org1.advanced_security_license.seats
        assert_equal 0, @user1.advanced_security_license.seats
      end

      test "purchased with unlimited seats" do
        assert_equal 0, @business.advanced_security_license.seats
        assert_equal 0, @org1.advanced_security_license.seats
        assert_equal 0, @user1.advanced_security_license.seats
      end

      test "purchased with limited seats" do
        GitHub::Enterprise.license.stubs(:advanced_security_seats).returns(70)

        assert_equal 70, @business.advanced_security_license.seats
        assert_equal 70, @org1.advanced_security_license.seats
        assert_equal 70, @user1.advanced_security_license.seats
      end
    end

    context "dotcom", skip_enterprise: true do
      test "org not in business, not purchased" do
        @org1.mark_advanced_security_as_not_purchased_for_entity(actor: @user1)

        assert_equal 0, @org1.advanced_security_license.seats
      end

      test "org in a business on an enterprise plan" do
        enable_feature_flag(:ghec_disabled_for_organizations_linked_to_enterprise)
        org = create(:organization, force_enterprise_managed_organization: true)

        assert_raises(StandardError, "Organization is not on a GHEC plan or is a child of an Enterprise, and therefore cannot purchase GHAS") do
          org.mark_advanced_security_as_purchased_for_entity(actor: User.ghost)
        end
      end

      test "org thats dunning" do
        enable_feature_flag(:ghec_disabled_for_organizations_linked_to_enterprise)
        org = create(:organization)
        org.increment_billing_attempts

        assert org.dunning?

        assert_raises(StandardError, "Organization is not eligible for GHAS since its in a dunning state") do
          org.mark_advanced_security_as_purchased_for_entity(actor: User.ghost)
        end
      end

      test "org thats part of a business on a free trial" do
        enable_feature_flag(:ghec_disabled_for_organizations_linked_to_enterprise)

        business = create(:business, :default_managed)
        org = create(:organization, business: business)
        business.update!(trial_expires_at: 2.days.from_now, business_type: 0)

        assert_raises(StandardError, "Organization is not eligible for GHAS since parent business is on a free trial") do
          org.mark_advanced_security_as_purchased_for_entity(actor: User.ghost)
        end
      end

      test "org not in business, purchased unlimited seats" do
        @org1.mark_advanced_security_as_purchased_for_entity(actor: @user1)
        @org1.set_advanced_security_seats_for_entity(actor: @user1, seats: 0)

        assert_equal 0, @org1.advanced_security_license.seats
        assert @org1.advanced_security_license.unlimited_seats?
      end

      test "org not in business, purchased limited seats" do
        @org1.mark_advanced_security_as_purchased_for_entity(actor: @user1)
        @org1.set_advanced_security_seats_for_entity(actor: @user1, seats: 15)

        assert_equal 15, @org1.advanced_security_license.seats
      end

      test "org in business, not purchased" do
        @org1.business = @business
        @business.mark_advanced_security_as_not_purchased_for_entity(actor: @user1)

        assert_equal 0, @org1.advanced_security_license.seats
      end

      test "org in business, purchase unlimited seats" do
        @org1.business = @business
        @business.mark_advanced_security_as_purchased_for_entity(actor: @user1)
        @business.set_advanced_security_seats_for_entity(actor: @user1, seats: 0)

        assert_equal 0, @org1.advanced_security_license.seats
        assert @org1.advanced_security_license.unlimited_seats?
      end

      test "org in business, purchased limited seats" do
        @org1.business = @business
        @business.mark_advanced_security_as_purchased_for_entity(actor: @user1)
        @business.set_advanced_security_seats_for_entity(actor: @user1, seats: 15)

        assert_equal 15, @org1.advanced_security_license.seats
      end

      test "org in business, purchased limited seats when self-serve" do
        business = create :business, :with_self_serve_payment, owners: [@user1]
        @org1.business = business
        business.subscribe_to_advanced_security(seats: 25, actor: @user1, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)

        assert_equal 25, @org1.advanced_security_license.seats
      end

      test "org not in business, with invalid config at org level" do
        # This config is invalid and should be impossible to set in production
        @org1.mark_advanced_security_as_not_purchased_for_entity(actor: @user1) # NOTE: Should we be able to mark_advanced_security_as_not_purchased for subscription items?
        @org1.set_advanced_security_seats_for_entity(actor: @user1, seats: 15)

        assert_equal 0, @org1.advanced_security_license.seats
      end

      test "business not purchased" do
        assert_equal 0, @business.advanced_security_license.seats
      end

      test "business purchased unlimited seats" do
        @business.mark_advanced_security_as_purchased_for_entity(actor: @user1)
        @business.set_advanced_security_seats_for_entity(actor: @user1, seats: 0)
        assert_equal 0, @business.advanced_security_license.seats
        assert @business.advanced_security_license.unlimited_seats?
      end

      test "business purchased limited seats" do
        @business.mark_advanced_security_as_purchased_for_entity(actor: @user1)
        @business.set_advanced_security_seats_for_entity(actor: @user1, seats: 15)
        assert_equal 15, @business.advanced_security_license.seats
        refute @business.advanced_security_license.unlimited_seats?
      end

      test "business purchased limited seats when self-serve" do
        business = create :business, :with_self_serve_payment, owners: [@user1]
        business.subscribe_to_advanced_security(seats: 15, actor: @user1, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        assert_equal 15, business.advanced_security_license.seats
        refute business.advanced_security_license.unlimited_seats?
      end

      test "invoiced businesses do not have GHAS stored on a subscription item" do
        assert @business.invoiced?
        refute @business.self_serve_payment?
        refute @business.advanced_security_seats_stored_on_subscription_item?
      end

      test "self-serve business cannot set GHAS subscription to 0 seats" do
        self_serve_business = create(:billing_plan_subscription, :business_owned).business
        self_serve_business_owner = self_serve_business.owners.first

        enable_feature_flag(:ghas_self_serve_orgs, self_serve_business)
        self_serve_business.subscribe_to_advanced_security(seats: 5, actor: self_serve_business_owner, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)

        assert self_serve_business.advanced_security_seats_stored_on_subscription_item?
        result = self_serve_business.set_advanced_security_seats_for_entity(actor: self_serve_business_owner, seats: 0)
        assert_equal result.message, "Cannot set the number of self-serve GitHub Advanced Security seats to 0: to set it to 0, cancel the subscription"
        assert_equal 1, Failbot.reports.size
      end

      test "self-serve business can update GHAS subscription seat quantity" do
        self_serve_business = create(:billing_plan_subscription, :business_owned).business
        self_serve_business_owner = self_serve_business.owners.first

        enable_feature_flag(:ghas_self_serve_orgs, self_serve_business)
        self_serve_business.subscribe_to_advanced_security(seats: 5, actor: self_serve_business_owner, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        self_serve_business.set_advanced_security_seats_for_entity(actor: self_serve_business_owner, seats: 10)

        assert self_serve_business.advanced_security_seats_stored_on_subscription_item?
        assert_equal 10, self_serve_business.advanced_security_license.seats
      end

      test "self-serve business cannot update GHAS subscription seat quantity if a subscription does not yet exist" do
        self_serve_business = create(:billing_plan_subscription, :business_owned).business
        self_serve_business_owner = self_serve_business.owners.first

        enable_feature_flag(:ghas_self_serve_orgs, self_serve_business)

        refute self_serve_business.advanced_security_subscription_item
        result = self_serve_business.set_advanced_security_seats_for_entity(actor: self_serve_business_owner, seats: 10)
        assert_equal result.message, "Cannot set the number of self-serve GitHub Advanced Security seats because the subscription has not been purchased"
        assert_equal 1, Failbot.reports.size
      end
    end
  end

  context "#unlimited_seats?" do
    context "enterprise", enterprise_only: true do
      test "not purchased" do
        GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(false)

        refute @business.advanced_security_license.unlimited_seats?
        refute @org1.advanced_security_license.unlimited_seats?
        refute @user1.advanced_security_license.unlimited_seats?
      end

      test "purchased with unlimited seats" do
        GitHub::Enterprise.license.stubs(:advanced_security_seats).returns(0)

        assert @business.advanced_security_license.unlimited_seats?
        assert @org1.advanced_security_license.unlimited_seats?
        assert @user1.advanced_security_license.unlimited_seats?
      end

      test "purchased with limited seats" do
        GitHub::Enterprise.license.stubs(:advanced_security_seats).returns(70)

        refute @business.advanced_security_license.unlimited_seats?
        refute @org1.advanced_security_license.unlimited_seats?
        refute @user1.advanced_security_license.unlimited_seats?
      end
    end

    context "dotcom", skip_enterprise: true do
      test "org not in business, not purchased" do
        @org1.mark_advanced_security_as_not_purchased_for_entity(actor: @user1)

        refute @org1.advanced_security_license.unlimited_seats?
      end

      test "org not in business, purchased unlimited seats" do
        @org1.mark_advanced_security_as_purchased_for_entity(actor: @user1)
        @org1.set_advanced_security_seats_for_entity(actor: @user1, seats: 0)

        assert @org1.advanced_security_license.unlimited_seats?
      end

      test "org not in business, purchased limited seats" do
        @org1.mark_advanced_security_as_purchased_for_entity(actor: @user1)
        @org1.set_advanced_security_seats_for_entity(actor: @user1, seats: 15)

        refute @org1.advanced_security_license.unlimited_seats?
      end

      test "org in business, not purchased" do
        @org1.business = @business
        @business.mark_advanced_security_as_not_purchased_for_entity(actor: @user1)

        refute @org1.advanced_security_license.unlimited_seats?
      end

      test "org in business, purchased unlimited seats" do
        @org1.business = @business
        @business.mark_advanced_security_as_purchased_for_entity(actor: @user1)
        @business.set_advanced_security_seats_for_entity(actor: @user1, seats: 0)

        assert @org1.advanced_security_license.unlimited_seats?
      end

      test "org in business, purchased limited seats" do
        @org1.business = @business
        @business.mark_advanced_security_as_purchased_for_entity(actor: @user1)
        @business.set_advanced_security_seats_for_entity(actor: @user1, seats: 15)

        refute @org1.advanced_security_license.unlimited_seats?
      end

      test "business not purchased" do
        refute @business.advanced_security_license.unlimited_seats?
      end

      test "business purchased unlimited seats" do
        @business.mark_advanced_security_as_purchased_for_entity(actor: @user1)
        @business.set_advanced_security_seats_for_entity(actor: @user1, seats: 0)
        assert @business.advanced_security_license.unlimited_seats?
      end

      test "business purchased limited seats" do
        @business.mark_advanced_security_as_purchased_for_entity(actor: @user1)
        @business.set_advanced_security_seats_for_entity(actor: @user1, seats: 15)
        refute @business.advanced_security_license.unlimited_seats?
      end

      test "self-serve trial has unlimited seats", skip_enterprise: true do
        result = @self_serve_business.subscribe_to_advanced_security_trial(
          actor: @self_serve_business_owner,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        assert result.ok?
        assert @self_serve_business.advanced_security_license.unlimited_seats?
      end

      test "self-serve purchased does not have unlimited seats", skip_enterprise: true do
        result = @self_serve_business.subscribe_to_advanced_security(
          actor: @self_serve_business_owner,
          seats: 5,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        assert result.ok?
        refute @self_serve_business.advanced_security_license.unlimited_seats?
      end
    end
  end

  context "#consumed_seats" do
    test "returns zero when advanced security is not enabled" do
      if GitHub.enterprise?
        GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(false)
      end
      stub_turboghas_summary(maximum_committers: 1, active_committers: 1)
      assert_equal 0, @business.advanced_security_license.consumed_seats
    end

    test "returns org numbers", skip_enterprise: true do
      @org1.mark_advanced_security_as_purchased_for_entity(actor: @user1)
      stub_turboghas_summary(maximum_committers: 1, active_committers: 1)
      assert_equal 1, @org1.advanced_security_license.consumed_seats
    end
  end

  context "#allowance_exceeded?" do
    test "returns false for business if GHAS not purchased" do
      GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(false) if GitHub.enterprise?
      @business.mark_advanced_security_as_not_purchased_for_entity(actor: @user1) unless GitHub.enterprise?

      refute @business.advanced_security_license.allowance_exceeded?
    end

    test "returns false for business if fewer seats used than purchased" do
      if GitHub.enterprise?
        GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(true)
        GitHub::Enterprise.license.stubs(:advanced_security_seats).returns(10)
      else
        @business.mark_advanced_security_as_purchased_for_entity(actor: @user1)
        @business.set_advanced_security_seats_for_entity(actor: @user1, seats: 10)
      end

      stub_turboghas_summary(maximum_committers: 5, active_committers: 5)

      assert_equal 5, @business.advanced_security_license.consumed_seats
      refute @business.advanced_security_license.allowance_exceeded?
    end

    test "returns false for business if fewer seats used than purchased when self-serve", skip_enterprise: true do
      business = create :business, :with_self_serve_payment, owners: [@user1]
      business.subscribe_to_advanced_security(seats: 10, actor: @user1, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)

      stub_turboghas_summary(maximum_committers: 5, active_committers: 5)

      assert_equal 5, business.advanced_security_license.consumed_seats
      refute business.advanced_security_license.allowance_exceeded?
    end

    test "returns false for business if same number of seats used as purchased" do
      if GitHub.enterprise?
        GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(true)
        GitHub::Enterprise.license.stubs(:advanced_security_seats).returns(10)
      else
        @business.mark_advanced_security_as_purchased_for_entity(actor: @user1)
        @business.set_advanced_security_seats_for_entity(actor: @user1, seats: 10)
      end

      stub_turboghas_summary(maximum_committers: 10, active_committers: 10)

      assert_equal 10, @business.advanced_security_license.consumed_seats
      refute @business.advanced_security_license.allowance_exceeded?
    end

    test "returns false for business if same number of seats used as purchased when self-serve", skip_enterprise: true do
      business = create :business, :with_self_serve_payment, owners: [@user1]
      business.subscribe_to_advanced_security(seats: 10, actor: @user1, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)

      stub_turboghas_summary(maximum_committers: 10, active_committers: 10)

      assert_equal 10, business.advanced_security_license.consumed_seats
      refute business.advanced_security_license.allowance_exceeded?
    end

    test "returns true for business if more seats used than purchased" do
      if GitHub.enterprise?
        GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(true)
        GitHub::Enterprise.license.stubs(:advanced_security_seats).returns(10)
      else
        @business.mark_advanced_security_as_purchased_for_entity(actor: @user1)
        @business.set_advanced_security_seats_for_entity(actor: @user1, seats: 10)
      end

      stub_turboghas_summary(maximum_committers: 11, active_committers: 11)

      assert_equal 11, @business.advanced_security_license.consumed_seats
      assert @business.advanced_security_license.allowance_exceeded?
    end

    test "returns false for business if seats unlimited" do
      if GitHub.enterprise?
        GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(true)
        GitHub::Enterprise.license.stubs(:advanced_security_seats).returns(0)
      else
        @business.mark_advanced_security_as_purchased_for_entity(actor: @user1)
        @business.set_advanced_security_seats_for_entity(actor: @user1, seats: 0)
      end

      stub_turboghas_summary(maximum_committers: 11, active_committers: 11)

      assert_equal 11, @business.advanced_security_license.consumed_seats
      refute @business.advanced_security_license.allowance_exceeded?
    end
  end

  context "#remaining_seats" do
    test "positive remaining seats" do
      @org1.advanced_security_license.stubs(:seats).returns(14)
      @org1.advanced_security_license.stubs(:consumed_seats).returns(4)
      assert_equal 10, @org1.advanced_security_license.remaining_seats
    end

    test "negative remaining seats" do
      @org1.advanced_security_license.stubs(:seats).returns(5)
      @org1.advanced_security_license.stubs(:consumed_seats).returns(17)
      assert_equal 0, @org1.advanced_security_license.remaining_seats
    end

    test "unlimited license seats" do
      @org1.advanced_security_license.stubs(:seats).returns(0)
      @org1.advanced_security_license.stubs(:consumed_seats).returns(4)
      assert_equal 0, @org1.advanced_security_license.remaining_seats
    end
  end

  test "#seat_usage_increase_if_advanced_security_enabled_for_repos" do
    stub_turboghas_summary(additional_committers: 1)

    assert_equal 1, AdvancedSecurityLicense.seat_usage_increase_if_advanced_security_enabled_for_repos(owner: @org1, repo_ids: [@user1_private_repo.id])
  end

  context "#user_ids" do
    test "with a billable_entity that's a business returns users that are members of orgs in that business" do
      @org3.business = @business
      @org4.business = @business
      @business.mark_advanced_security_as_purchased_for_entity(actor: @user1)

      if GitHub.enterprise?
        # include all users to replicate the behaviour of the previous system
        assert_same_elements [@user1.id, @user2.id, @user3.id, @user4.id], @org4.advanced_security_license.user_ids
      else
        assert_same_elements [@user1.id, @user3.id, @user4.id], @org4.advanced_security_license.user_ids
      end
    end

    test "with a billable_entity that's an org returns users that are members of only that org", skip_enterprise: true do
      @org4.business = nil
      @org4.mark_advanced_security_as_purchased_for_entity(actor: @user1)

      assert_same_elements [@user1.id, @user4.id], @org4.advanced_security_license.user_ids
    end

    # This skips enterprise because there we always have the global business as billable entity
    test "without a business or org as billable entity returns no users", skip_enterprise: true do
      assert_empty AdvancedSecurityLicense.new(@user1).user_ids
    end

    test "does not return user IDs that have their billing locked" do
      user = create(:credit_card_user, :with_billing_locked)
      if GitHub.flipper[:use_billing_locked_rather_than_disabled].enabled?
        user.customer.lock_billing
      end

      org = create :organization, public_members: [user]
      org.mark_advanced_security_as_purchased_for_entity(actor: User.ghost)

      refute org.advanced_security_license.user_ids.include?(user.id)
    end

    test "does not return user IDs that have been suspended" do
      user = create :user, suspended_at: Time.current
      org = create :organization, public_members: [user]
      org.mark_advanced_security_as_purchased_for_entity(actor: User.ghost)

      refute org.advanced_security_license.user_ids.include?(user.id)
    end
  end

  test "#active_committer_user_ids" do
    VCR.use_cassette("get-active-committers-all-features", persist_with: :turboghas) do
      assert_same_elements [1, 5, 6, 9], AdvancedSecurityLicense.new(@org1).active_committer_user_ids
    end
  end

  test "#additional_committers_per_repository" do
    VCR.use_cassette("get-additional-committers-per-repository", persist_with: :turboghas) do
      assert_equal [[2, 2]].to_h, AdvancedSecurityLicense.new(@org1).additional_committers_per_repository(repository_ids: [@org1_repo_public.id, @org1_repo_private.id])
    end
  end
end
