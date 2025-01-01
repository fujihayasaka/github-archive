# typed: true
# frozen_string_literal: true

require "test_helper"

module EnterpriseCloudOnboard
  class SecretProtectionTrialTest < GitHub::TestCase
    include TurboghasHelpers

    fixtures do
      make_trusted_oauth_apps_owner
      create(:launch_integration)

      @owner = create(:user)
      @organization = create(:organization, admin: @owner, plan: GitHub::Plan.business)
      @repo = OrganizationOnboard::DemoRepository.new(organization: @organization).setup(@owner)&.repository

      @business = create(:business, owners: [@owner])
      @org_from_business = create(:organization, admin: @owner, plan: GitHub::Plan.business)
      @business.add_organization(@org_from_business)
      @repo_from_business = OrganizationOnboard::DemoRepository.new(organization: @org_from_business).setup(@owner)&.repository

      create(:billing_product_uuid, :advanced_security)
    end

    context "with enterprises" do
      context "#enable" do
        test "enables Secret Protection when no SKU is purchased" do
          # set up
          biz = T.let(@business, Business)
          trial = EnterpriseCloudOnboard::SecretProtectionTrial.new(billable_entity: @business)
          refute trial.enabled?
          refute biz.secret_protection.purchased?

          # call
          trial.enable(actor: @owner, days: 1)

          # check stuff
          assert trial.enabled?
          assert biz.secret_protection.purchased?
        end

        test "enables Secret Protection when Code Security volume is purchased" do
          # set up
          biz = T.let(@business, Business)
          biz.set_customer_to_split_volume_code_security_only(actor: @owner)
          trial = EnterpriseCloudOnboard::SecretProtectionTrial.new(billable_entity: @business)
          assert biz.code_security_sku_purchased_for_entity?
          refute trial.enabled?
          refute biz.secret_protection.purchased?

          # call
          trial.enable(actor: @owner, days: 1)

          # check stuff
          assert trial.enabled?
          assert biz.secret_protection.purchased?
          assert biz.code_security_sku_purchased_for_entity?
        end

        test "enables Secret Protection when split metered is enabled but there are no Secret Protection committers" do
          # set up
          biz = T.let(@business, Business)
          biz.set_customer_to_split_metered_offering(actor: @owner)
          trial = EnterpriseCloudOnboard::SecretProtectionTrial.new(billable_entity: @business)
          refute trial.enabled?
          stub_turboghas_summary(active_committers: 0) # feature is not used

          # call
          trial.enable(actor: @owner, days: 1)

          # check stuff
          assert trial.enabled?
          assert biz.secret_protection.purchased?
        end

        test "enables Secret Protection when GHAS metered is enabled and there no committers using it" do
          # set up
          biz = T.let(@business, Business)
          biz.set_advanced_security_enabled_type_for_entity(option: Configurable::AdvancedSecurityBillingConfig::GHAS_METERED, actor: @owner)
          trial = EnterpriseCloudOnboard::SecretProtectionTrial.new(billable_entity: @business)
          refute trial.enabled?
          refute biz.secret_protection.purchased?
          stub_turboghas_summary(active_committers: 0) # feature is not used

          # call
          trial.enable(actor: @owner, days: 1)

          # check stuff
          assert trial.enabled?
          assert biz.secret_protection.purchased?
        end

        test "raises when split volume is enabled" do
          # set up
          biz = T.let(@business, Business)
          biz.mark_advanced_security_as_purchased_for_entity_as_volume_unbundled(actor: @owner)
          assert biz.code_security_sku_purchased_for_entity?
          trial = EnterpriseCloudOnboard::SecretProtectionTrial.new(billable_entity: @business)
          refute trial.enabled?

          # call
          assert_raises(EnterpriseCloudOnboard::SKUTrial::EnablementError) do
            trial.enable(actor: @owner, days: 1)
          end

          # check stuff
          refute trial.enabled?
          assert biz.code_security_sku_purchased_for_entity?
        end

        test "raises when Secret Protection volume is enabled" do
          # set up
          biz = T.let(@business, Business)
          biz.set_advanced_security_enabled_type_for_entity(option: Configurable::AdvancedSecurityBillingConfig::SECRET_PROTECTION_VOLUME, actor: @owner)
          trial = EnterpriseCloudOnboard::SecretProtectionTrial.new(billable_entity: @business)
          refute trial.enabled?

          # call
          assert_raises(EnterpriseCloudOnboard::SKUTrial::EnablementError) do
            trial.enable(actor: @owner, days: 1)
          end

          # check stuff
          refute trial.enabled?
          assert_equal Configurable::AdvancedSecurityBillingConfig::SECRET_PROTECTION_VOLUME, biz.advanced_security_enabled_type_for_entity
        end

        test "raises when GHAS volume is enabled" do
          # set up
          biz = T.let(@business, Business)
          biz.set_advanced_security_enabled_type_for_entity(option: Configurable::AdvancedSecurityBillingConfig::GHAS_VOLUME, actor: @owner)
          trial = EnterpriseCloudOnboard::SecretProtectionTrial.new(billable_entity: @business)
          refute trial.enabled?
          refute biz.secret_protection.purchased?
          assert biz.advanced_security_purchased_for_entity?

          # call
          assert_raises(EnterpriseCloudOnboard::SKUTrial::EnablementError) do
            trial.enable(actor: @owner, days: 1)
          end

          # check stuff
          refute trial.enabled?
          refute biz.secret_protection.purchased?
          assert biz.advanced_security_purchased_for_entity?
        end

        test "raises when GHAS metered is enabled and there are committers using it" do
          # set up
          biz = T.let(@business, Business)
          biz.set_advanced_security_enabled_type_for_entity(option: Configurable::AdvancedSecurityBillingConfig::GHAS_METERED, actor: @owner)
          trial = EnterpriseCloudOnboard::SecretProtectionTrial.new(billable_entity: @business)
          refute trial.enabled?
          refute biz.secret_protection.purchased?
          stub_turboghas_summary(active_committers: 1) # feature is used

          # call
          assert_raises(EnterpriseCloudOnboard::SKUTrial::EnablementError) do
            trial.enable(actor: @owner, days: 1)
          end

          # check stuff
          refute trial.enabled?
          refute biz.secret_protection.purchased?
        end

        test "does not enable Secret Protection if the user is not the owner" do
          # set up
          biz = T.let(@business, Business)
          user = create(:user)
          @org_from_business.add_member(user)
          refute @repo_from_business.advanced_security_enabled?
          trial = EnterpriseCloudOnboard::SecretProtectionTrial.new(billable_entity: @business)
          refute trial.enabled?
          refute biz.secret_protection.purchased?

          # call
          assert_raises(EnterpriseCloudOnboard::SKUTrial::EnablementError) do
            trial.enable(actor: user, days: 1)
          end

          # check stuff
          refute trial.enabled?
          refute biz.secret_protection.purchased?
        end
      end # context "#enable"

      context "#disable" do
        test "disables Secret Protection" do
          # set up
          biz = T.let(@business, Business)
          trial = EnterpriseCloudOnboard::SecretProtectionTrial.new(billable_entity: biz)
          trial.enable(actor: @owner, days: 10)
          assert trial.enabled?
          assert biz.secret_protection.purchased?

          # call
          trial.disable(actor: User.ghost)

          # check stuff
          refute trial.enabled?
          refute biz.secret_protection.purchased?
          assert_equal 0, biz.secret_scanning_license_count
        end

        test "disables Secret Protection trial after it is purchased as volume" do
          # set up
          biz = T.let(@business, Business)
          trial = EnterpriseCloudOnboard::SecretProtectionTrial.new(billable_entity: biz)
          trial.enable(actor: @owner, days: 10)
          assert trial.enabled?
          assert biz.secret_protection.purchased?

          # purchase it
          biz.set_advanced_security_enabled_type_for_entity(option: Configurable::AdvancedSecurityBillingConfig::SECRET_PROTECTION_VOLUME, actor: User.ghost)
          num_licenses = 10
          biz.set_secret_scanning_license_count(count: num_licenses, actor: User.ghost)

          # call
          trial.disable(actor: User.ghost)

          # check stuff
          refute trial.enabled?
          assert biz.secret_protection.purchased?
          assert_equal Configurable::AdvancedSecurityBillingConfig::SECRET_PROTECTION_VOLUME, biz.advanced_security_enabled_type_for_entity
          assert_equal num_licenses, biz.secret_scanning_license_count
        end

        test "disables Secret Protection trial after Code Security is purchased as volume" do
          # set up
          biz = T.let(@business, Business)
          trial = EnterpriseCloudOnboard::SecretProtectionTrial.new(billable_entity: biz)
          trial.enable(actor: @owner, days: 10)
          assert trial.enabled?
          assert biz.secret_protection.purchased?

          # purchase Code Security & Secret Protection
          biz.set_advanced_security_enabled_type_for_entity(option: Configurable::AdvancedSecurityBillingConfig::CODE_SECURITY_VOLUME, actor: User.ghost)
          num_licenses = 10
          biz.set_code_security_license_count(count: num_licenses, actor: User.ghost)

          # call
          trial.disable(actor: User.ghost)

          # check stuff
          refute trial.enabled?
          refute biz.secret_protection.purchased?
          assert_equal num_licenses, biz.code_security_license_count
          assert_equal 0, biz.secret_scanning_license_count
        end

        test "disables Secret Protection after both SKUs are purchased as volume" do
          # set up
          biz = T.let(@business, Business)
          trial = EnterpriseCloudOnboard::SecretProtectionTrial.new(billable_entity: biz)
          trial.enable(actor: @owner, days: 10)
          assert trial.enabled?
          assert biz.secret_protection.purchased?

          # purchase Code Security & Secret Protection
          biz.set_advanced_security_enabled_type_for_entity(option: Configurable::AdvancedSecurityBillingConfig::SPLIT_VOLUME, actor: User.ghost)
          num_sp_licenses = 10
          num_cs_licenses = 20
          biz.set_code_security_license_count(count: num_cs_licenses, actor: User.ghost)
          biz.set_secret_scanning_license_count(count: num_sp_licenses, actor: User.ghost)

          # call
          trial.disable(actor: User.ghost)

          # check stuff
          refute trial.enabled?
          assert biz.secret_protection.purchased?
          assert_equal num_cs_licenses, biz.code_security_license_count
          assert_equal num_sp_licenses, biz.secret_scanning_license_count
        end
      end # context "#disable"

      context "#set_number_of_days" do
        test "sets the number of days for the trial" do
          # set up
          biz = T.let(@business, Business)
          trial = EnterpriseCloudOnboard::SecretProtectionTrial.new(billable_entity: biz)
          original_days = 10
          trial.enable(actor: @owner, days: original_days)

          # call
          new_days = 20
          trial.set_number_of_days(actor: User.ghost, days: new_days)

          # check stuff
          assert_equal new_days, trial.number_of_days
        end

        test "raises if the trial would expire" do
          # set up
          biz = T.let(@business, Business)
          trial = EnterpriseCloudOnboard::SecretProtectionTrial.new(billable_entity: biz)
          start_days_ago = 10
          original_days = 20
          trial.enable(actor: @owner, days: original_days, start_date: Date.current - start_days_ago.days)
          assert trial.enabled?

          # call
          new_days = start_days_ago / 2
          assert_raises(EnterpriseCloudOnboard::SKUTrial::WouldExpireError) do
            trial.set_number_of_days(actor: User.ghost, days: new_days)
          end

          # check stuff
          assert_equal original_days, trial.number_of_days
          assert trial.enabled?
        end
      end # context "#set_number_of_days"
    end # context "with enterprises"
  end
end unless GitHub.enterprise?
