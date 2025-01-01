# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryAdvancedSecurityDependencyTest < GitHub::TestCase
  include TurboghasHelpers
  include HydroTestHelpers

  fixtures do
    GitHub::Enterprise.ensure_business! if GitHub.single_business_environment?
    @user = create(:user)
    @org = create(:organization, :zuora, admin: @user)
    @private_org_repo = create(:private_repository, owner: @org)
    @public_org_repo = create(:public_repository, owner: @org)
    @private_user_repo = create(:private_repository, owner: @user)
    @public_user_repo = create(:public_repository, owner: @user)

    if GitHub.enterprise?
      @business = create(:global_business)
    else
      @business = create(:business, :with_self_serve_payment, owners: [@user])
    end
    @private_business_org = create(:organization, admin: @user, business: @business)
    @private_business_org_repo = create(:private_repository, owner: @private_business_org)
    @business_org_repo = create(:repository, owner: @private_business_org)

    create(:billing_product_uuid, :advanced_security)
  end

  # Set things up so that enabling_advanced_security_would_exceed_seat_allowance? would return true.
  # This will be a shared starting point for each test of this method.
  def setup_for_enabling_advanced_security_would_exceed_seat_allowance
    if GitHub.enterprise?
      GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(true)
      GitHub::Enterprise.license.stubs(:advanced_security_seats).returns(10)
    else
      @private_org_repo.owner.mark_advanced_security_as_purchased_for_entity(actor: @user)
      @private_org_repo.owner.set_advanced_security_seats_for_entity(seats: 10, actor: @user)
    end
    @private_org_repo.disable_advanced_security!(actor: @user)

    @private_org_repo.owner.advanced_security_license.stubs(:consumed_seats).returns(7)
    @private_org_repo.stubs(:seat_usage_increase_if_advanced_security_enabled).returns(5)
  end

  def setup_for_self_serve_business_enabling_advanced_security_would_exceed_seat_allowance
    return if GitHub.enterprise?

    @business.subscribe_to_advanced_security(seats: 10, actor: @user, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)

    @private_business_org_repo.disable_advanced_security!(actor: @user)

    @private_business_org_repo.owner.advanced_security_license.stubs(:consumed_seats).returns(7)
    @private_business_org_repo.stubs(:seat_usage_increase_if_advanced_security_enabled).returns(5)
  end

  def setup_for_enable_advanced_security_on_state_change
    Organization.any_instance.stubs(:advanced_security_enabled_on_new_repos?).returns(true)

    if GitHub.enterprise?
      GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(true)
      GitHub::Enterprise.license.stubs(:advanced_security_seats).returns(10)
    else
      @private_org_repo.owner.mark_advanced_security_as_purchased_for_entity(actor: @user)
      @private_org_repo.owner.set_advanced_security_seats_for_entity(seats: 10, actor: @user)
    end

    stub_turboghas_summary(maximum_committers: 5, active_committers: 1)
  end

  test "emits a hydro event when ghas is toggled" do
    if GitHub.enterprise?
      GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(true)
      GitHub::Enterprise.license.stubs(:advanced_security_seats).returns(10)
    else
      @private_org_repo.owner.mark_advanced_security_as_purchased_for_entity(actor: @user)
      @private_org_repo.owner.set_advanced_security_seats_for_entity(seats: 10, actor: @user)
    end

    @private_org_repo.enable_advanced_security!(actor: @user)

    # this message being published is critical to ghas billing detecting repositories have had ghas enabled
    assert_hydro_messages(count: 1, schema: "github.security_center.v0.AdvancedSecurityToggled")
  end

  context "#enable_advanced_security_on_state_change?" do
    context "ghas is not enabled for new repos at the org level" do
      test "returns false if a repo's state changes to private" do
        setup_for_enable_advanced_security_on_state_change
        @public_org_repo.owner.stubs(:advanced_security_enabled_on_new_repos?).returns(false)

        @public_org_repo.public = false
        @public_org_repo.save

        refute @public_org_repo.enable_advanced_security_on_state_change?
      end
    end

    context "ghas is enabled for new repos at the org level" do
      test "returns true if a repo's state changes to private" do
        setup_for_enable_advanced_security_on_state_change

        @public_org_repo.public = false
        @public_org_repo.save

        assert @public_org_repo.enable_advanced_security_on_state_change?
      end

      test "returns true if a repo's state changes to internal" do
        setup_for_enable_advanced_security_on_state_change

        @business_org_repo.set_visibility(actor: @user, visibility: "internal")
        @business_org_repo.save

        assert @business_org_repo.enable_advanced_security_on_state_change?
      end

      test "returns true if a GHES repo's state changes to public", enterprise_only: true do
        setup_for_enable_advanced_security_on_state_change

        @private_org_repo.public = true
        @private_org_repo.save

        assert @private_org_repo.enable_advanced_security_on_state_change?
      end

      test "returns false if a dotcom repo's state changes to public", skip_enterprise: true do
        setup_for_enable_advanced_security_on_state_change

        @private_org_repo.public = true
        @private_org_repo.save

        refute @private_org_repo.enable_advanced_security_on_state_change?
      end
    end
  end

  context "#enabling_advanced_security_would_exceed_seat_allowance?" do
    test "Returns false if GHAS not purchased" do
      setup_for_enabling_advanced_security_would_exceed_seat_allowance

      if GitHub.enterprise?
        GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(false)
      else
        # TODO: What does this even do? Do we cancel the subscription item if we call this?
        @private_org_repo.owner.mark_advanced_security_as_not_purchased_for_entity(actor: @user)
      end

      refute @private_org_repo.enabling_advanced_security_would_exceed_seat_allowance?
    end

    test "Returns false if unlimited license" do
      setup_for_enabling_advanced_security_would_exceed_seat_allowance

      if GitHub.enterprise?
        GitHub::Enterprise.license.stubs(:advanced_security_seats).returns(0)
      else
        @private_org_repo.owner.set_advanced_security_seats_for_entity(seats: 0, actor: @user)
      end

      refute @private_org_repo.enabling_advanced_security_would_exceed_seat_allowance?
    end

    test "Returns false if seat limit would not be exceeded" do
      setup_for_enabling_advanced_security_would_exceed_seat_allowance

      @private_org_repo.stubs(:seat_usage_increase_if_advanced_security_enabled).returns(2)

      refute @private_org_repo.enabling_advanced_security_would_exceed_seat_allowance?
    end

    test "Returns false if consumed seats is at the limit but the new repo uses no extra seats" do
      setup_for_enabling_advanced_security_would_exceed_seat_allowance

      @private_business_org_repo.owner.advanced_security_license.stubs(:consumed_seats).returns(10)
      @private_business_org_repo.stubs(:seat_usage_increase_if_advanced_security_enabled).returns(0)

      refute @private_business_org_repo.enabling_advanced_security_would_exceed_seat_allowance?
    end

    test "Returns true if seat limit would be exceeded" do
      # Deliberately do no other changes beyond what's in the following method.
      # This ensures the changes made in the other tests are doing what we expect
      # and we're not getting spurious test passes.
      setup_for_enabling_advanced_security_would_exceed_seat_allowance

      assert @private_org_repo.enabling_advanced_security_would_exceed_seat_allowance?
    end

    test "Returns true if seat limit already exceeded" do
      setup_for_enabling_advanced_security_would_exceed_seat_allowance

      @private_org_repo.owner.advanced_security_license.stubs(:consumed_seats).returns(15)
      @private_org_repo.stubs(:seat_usage_increase_if_advanced_security_enabled).returns(0)

      assert @private_org_repo.enabling_advanced_security_would_exceed_seat_allowance?
    end
  end

  context "advanced_security_configurable?" do
    test "disabled for org repos with GHAS not purchased" do
      GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(false) if GitHub.enterprise?
      refute @private_org_repo.advanced_security_configurable?
      refute @public_org_repo.advanced_security_configurable?
    end

    test "enabled for private org repo on dotcom with GHAS purchased", skip_enterprise: true do
      @org.business = create :business
      @org.business.mark_advanced_security_as_purchased_for_entity(actor: @user)

      assert @private_org_repo.advanced_security_configurable?
      refute @public_org_repo.advanced_security_configurable?
    end

    test "enabled for private and public org repos on GHES with GHAS purchased", enterprise_only: true do
      GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(true)
      assert @private_org_repo.advanced_security_configurable?
      assert @public_org_repo.advanced_security_configurable?
    end

    test "disabled for non-EMU user repos on Dotcom", skip_enterprise: true do
      refute @private_user_repo.advanced_security_configurable?
      refute @public_user_repo.advanced_security_configurable?
    end

    test "enabled for private EMU user repos on Dotcom", skip_enterprise: true do
      emu = create(:emu)
      emu.enterprise_managed_business.mark_advanced_security_as_purchased_for_entity(actor: emu)
      assert emu.enterprise_managed_business.advanced_security_purchased_for_entity?

      public_emu_repo = create(:public_repository, owner: emu, force_user_owned: true)
      private_emu_repo = create(:private_repository, owner: emu, force_user_owned: true)

      refute public_emu_repo.advanced_security_configurable?
      assert private_emu_repo.advanced_security_configurable?
    end

    test "disabled for GHES user repos if feature disabled", enterprise_only: true do
      GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(false) if GitHub.enterprise?
      GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(true)

      refute @private_user_repo.advanced_security_configurable?
      refute @public_user_repo.advanced_security_configurable?
    end

    test "enabled for GHES user repos if feature enabled", enterprise_only: true do
      GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(true) if GitHub.enterprise?
      GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(true)

      assert @private_user_repo.advanced_security_configurable?
      assert @public_user_repo.advanced_security_configurable?
    end
  end
end
