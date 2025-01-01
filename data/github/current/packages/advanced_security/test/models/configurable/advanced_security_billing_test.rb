# typed: true
# frozen_string_literal: true

require "test_helper"

class AdvancedSecurityBillingTest < GitHub::TestCase
  fixtures do
    @user = create :user
    @organization = create(:organization, admin: @user)
    if GitHub.single_business_environment?
      GitHub::Enterprise.ensure_business!
      @business = GitHub.global_business
    else
      @business = create(:business)
    end
  end

  setup do
    GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(true) if GitHub.enterprise?
  end

  test "returns connect usage" do
    enterprise_installation = create(:enterprise_installation, owner: @business)

    create(:business_user_account, business: @business, user: nil, enterprise_installation_user_accounts: [
      create(:enterprise_installation_user_account, :ghas_connect,
        enterprise_installation: enterprise_installation,
        site_admin: true,
        using_code_security: true)])

    create(:business_user_account, business: @business, user: nil, enterprise_installation_user_accounts: [
      create(:enterprise_installation_user_account, :ghas_connect,
        enterprise_installation: enterprise_installation,
        site_admin: true,
        using_secret_protection: true)])

    create(:business_user_account, business: @business, user: nil, enterprise_installation_user_accounts: [
      create(:enterprise_installation_user_account, :ghas_connect,
        enterprise_installation: enterprise_installation,
        site_admin: true,
        using_advanced_security: true)])

    assert_equal 3, @business.advanced_security_business_user_accounts(sku: GitHub::Turboghas::SKU::Bundled).count
    assert_equal 2, @business.advanced_security_business_user_accounts(sku: GitHub::Turboghas::SKU::SecretSecurity).count
    assert_equal 2, @business.advanced_security_business_user_accounts(sku: GitHub::Turboghas::SKU::CodeSecurity).count
  end

  context "#advanced_security_purchased?" do
    context "enterprise", enterprise_only: true do
      test "returns false for all entities if not enabled in license" do
        GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(false)
        refute @user.advanced_security_purchased?
        refute @organization.advanced_security_purchased?
        refute GitHub.global_business.advanced_security_purchased?
      end

      test "returns true for all entities if enabled in license" do
        GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(true)
        assert @user.advanced_security_purchased?
        assert @organization.advanced_security_license_for_sku(sku: GitHub::Turboghas::SKU::Bundled).purchased?
        assert @organization.advanced_security_purchased?
        assert GitHub.global_business.advanced_security_purchased?
      end

      # Configurable::AdvancedSecurityBillingConfig isn't relevant in GHES and shouldn't be used there
      test "returns false if license doesn't include GHAS, regardless of config" do
        # These would never really be called in an Enterprise context, but in this
        # test we're explicitly testing this "shouldn't happen" case
        @organization.mark_advanced_security_as_purchased_for_entity(actor: @user)
        GitHub.global_business.mark_advanced_security_as_purchased_for_entity(actor: @user)

        GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(false)
        refute @user.advanced_security_purchased?
        refute @organization.advanced_security_purchased?
        refute GitHub.global_business.advanced_security_purchased?
      end
    end

    context "dotcom", skip_enterprise: true do
      test "returns false for a user as users can't purchase GHAS for themselves" do
        # It's still false even if they own a business which does have GHAS
        @business.add_owner(@user, actor: @user)
        @business.mark_advanced_security_as_purchased_for_entity(actor: @user)
        refute @user.advanced_security_purchased?
      end

      test "returns false for an org not in busines without the config" do
        @organization.config.delete(Configurable::AdvancedSecurityBillingConfig::ADVANCED_SECURITY_KEY)
        refute @organization.advanced_security_purchased?
      end

      test "returns false where org not in busines has not purchased GHAS" do
        @organization.mark_advanced_security_as_not_purchased_for_entity(actor: @user)
        refute @organization.advanced_security_purchased?
      end

      test "returns true for org not in busines if it's purchased GHAS" do
        @organization.mark_advanced_security_as_purchased_for_entity(actor: @user)
        assert @organization.advanced_security_purchased?
      end

      test "returns false for org in business if business doesn't have advanced security" do
        @business.mark_advanced_security_as_not_purchased_for_entity(actor: @user)
        @organization.business = @business
        refute @organization.advanced_security_purchased?, "org has advanced security but shouldn't"
      end

      # Until https://github.com/github/code-scanning/issues/2733 has been done,
      # we may end up with an org having GHAS marked as purchased inside a business
      # which doesn't (because the org bought it and then transferred in).
      # Even once 2733 has been done, it's probably still worth having this test as
      # a "belt-and-braces" check on the logic.
      test "returns false for org in business if business doesn't have advanced security, even if org does" do
        @organization.mark_advanced_security_as_purchased_for_entity(actor: @user)
        @business.mark_advanced_security_as_not_purchased_for_entity(actor: @user)
        @organization.business = @business
        refute @organization.advanced_security_purchased?, "org has advanced security but shouldn't"
      end

      test "returns true for org in business if business has advanced security" do
        @organization.mark_advanced_security_as_not_purchased_for_entity(actor: @user)
        @business.mark_advanced_security_as_purchased_for_entity(actor: @user)
        @organization.business = @business
        assert @organization.advanced_security_purchased?, "org doesn't have advanced security but should"
      end
    end
  end

  context "#secret_protection_purchased?" do
    context "enterprise", enterprise_only: true do
      test "returns false if secret protection is not purchased" do
        GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(true)
        GitHub::Enterprise.license.stubs(:secret_protection_enabled).returns(false)
        refute @organization.secret_protection_purchased?
        refute @business.secret_protection_purchased?
      end

      test "returns true if secret protection is purchased" do
        GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(false)
        GitHub::Enterprise.license.stubs(:secret_protection_enabled).returns(true)
        assert @organization.secret_protection_purchased?
        assert @organization.advanced_security_license_for_sku(sku: GitHub::Turboghas::SKU::SecretSecurity).purchased?
        assert @business.secret_protection_purchased?
        assert @business.advanced_security_license_for_sku(sku: GitHub::Turboghas::SKU::SecretSecurity).purchased?
      end
    end

    context "dotcom", skip_enterprise: true do
      test "returns false when advanced_security_purchased? is false" do
        @organization.mark_advanced_security_as_not_purchased_for_entity(actor: @user)
        @business.mark_advanced_security_as_not_purchased_for_entity(actor: @user)

        refute @organization.secret_protection_purchased?
        refute @business.secret_protection_purchased?
      end

      test "returns the value of secret_protection_purchased? when advanced security is purchased and the billable owner is a business" do
        @business.mark_advanced_security_as_purchased_for_entity(actor: @user)

        assert_equal @business.secret_protection_purchased?, @business.secret_protection_purchased?
      end
    end
  end
end

class AdvancedSecurityBillingEMUTest < GitHub::TestCase
  fixtures do
    @owner = create(:user)
    if GitHub.enterprise?
      @business = create(:global_business)
      @user = create(:user, business: @business)
    else
      @business = create(:business, :enterprise_managed)
      @emu_user = create(:emu, business: @business)
      @emu_owned_repo = create(:private_repository, force_user_owned: true, owner: @emu_user)
    end
  end

  setup do
    GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(true) if GitHub.enterprise?
  end

  context "#advanced_security_purchased?" do
    test "returns true if business has purchased GHAS", skip_enterprise: true do
      @business.mark_advanced_security_as_purchased_for_entity(actor: @owner)
      assert @emu_user.advanced_security_purchased?
    end

    test "returns false if business has not purchased GHAS", skip_enterprise: true do
      GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(false) if GitHub.enterprise?
      refute @emu_user.advanced_security_purchased?
    end

    test "returns true for user in GHES when feature disabled but GHAS enabled by license", enterprise_only: true do
      GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(false)
      @business.mark_advanced_security_as_purchased_for_entity(actor: @owner)
      assert @user.advanced_security_purchased?
    end
  end

  context "#secret_protection_purchased?" do
    context "enterprise", enterprise_only: true do
      test "returns true if business has purchased secret scanning" do
        GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(false)
        GitHub::Enterprise.license.stubs(:secret_protection_enabled).returns(true)
        assert @user.secret_protection_purchased?
      end

      test "returns false if business has not purchased secret scanning" do
        GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(true)
        GitHub::Enterprise.license.stubs(:secret_protection_enabled).returns(false)
        refute @user.secret_protection_purchased?
      end
    end

    context "dotcom", skip_enterprise: true do
      test "returns true if business has purchased secret scanning" do
        @business.mark_secret_protection_as_purchased_for_entity_as_volume(actor: @owner)
        assert @emu_user.secret_protection_purchased?
      end

      test "returns false if business has not purchased secret scanning" do
        refute @emu_user.secret_protection_purchased?
      end
    end
  end
end
