# typed: true
# frozen_string_literal: true

require "test_helper"
module ::SecretScanning::Features
  class SecretScanningAdvancedSecurityHelperTest < GitHub::TestCase
    include SecretScanning::Features::FeatureFlagHelper

    fixtures do
      @owner = create(:user)
      if GitHub.enterprise?
        @business = create(:global_business)
        @user = create(:user)
        @user_owned_repo = create(:private_repository, force_user_owned: true, owner: @user)
        @org = create(:organization, admin: @user, business: @business)
        @org_repo = create(:private_repository, owner: @org)
      else
        @business = create(:business, :enterprise_managed)
        @emu_user = create(:emu, business: @business)
        @emu_owned_repo = create(:private_repository, force_user_owned: true, owner: @emu_user)
        @org = create(:organization, admin: @emu_user, business: @business)
        @org_repo = create(:private_repository, owner: @org)
      end
    end

    def stub_advanced_security_as_purchased(enabled)
      if GitHub.enterprise?
        GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(enabled)
      else
        @business.mark_advanced_security_as_purchased_for_entity(actor: @owner) if enabled
      end
    end

    def stub_secret_protection_as_purchased(enabled)
      if GitHub.enterprise?
        GitHub::Enterprise.license.stubs(:secret_protection_enabled).returns(enabled)
      else
        @business.set_advanced_security_enabled_type_for_entity(option: Configurable::AdvancedSecurityBillingConfig::SECRET_PROTECTION_VOLUME, actor: @owner) if enabled
      end
    end

    def stub_code_security_as_purchased(enabled)
      if GitHub.enterprise?
        GitHub::Enterprise.license.stubs(:code_security_enabled).returns(enabled)
      else
        @business.set_customer_to_split_volume_code_security_only(actor: @owner) if enabled
      end
    end

    def stub_purchase_state(purchased)
      case purchased
      when "bundled"
        stub_advanced_security_as_purchased(true)
      when "secret_protection"
        stub_secret_protection_as_purchased(true)
        stub_advanced_security_as_purchased(false)
      when "code_security"
        stub_code_security_as_purchased(true)
        stub_advanced_security_as_purchased(false)
      else
        stub_advanced_security_as_purchased(false)
      end
    end

    context "#advanced_security_available?" do
      context "enterprise", enterprise_only: true do
        context "org-owned repos" do
          test_cases = [
            { expected: true,  flagEnabled: true,  purchased: true },
            { expected: false, flagEnabled: true,  purchased: false },
            { expected: true,  flagEnabled: false, purchased: true },
            { expected: false, flagEnabled: false, purchased: false }
          ]
          test_cases.each do |tc|
            test "returns #{tc[:expected]} when ghas for enterprise users is #{tc[:flagEnabled]} and advanced security is #{tc[:purchased]}" do
              GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(tc[:flagEnabled])
              stub_advanced_security_as_purchased(tc[:purchased])
              assert_equal tc[:expected], SecretScanning::Features::AdvancedSecurityHelper.advanced_security_available?(@org_repo)
            end
          end
        end

        context "user-owned repos" do
          test_cases = [
            { expected: true,  flagEnabled: true,  purchased: true },
            { expected: false, flagEnabled: true,  purchased: false },
            { expected: false, flagEnabled: false, purchased: true },
            { expected: false, flagEnabled: false, purchased: false }
          ]
          test_cases.each do |tc|
            test "returns #{tc[:expected]} when ghas for enterprise users is #{tc[:flagEnabled]} and advanced security is #{tc[:purchased]}" do
              GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(tc[:flagEnabled])
              stub_advanced_security_as_purchased(tc[:purchased])
              assert_equal tc[:expected], SecretScanning::Features::AdvancedSecurityHelper.advanced_security_available?(@user_owned_repo)
            end
          end
        end
      end

      context "dotcom", skip_enterprise: true do
        context "org-owned repos" do
          test_cases = [
            { expected: true,  purchased: true },
            { expected: false, purchased: false }
          ]
          test_cases.each do |tc|
            test "returns #{tc[:expected]} when advanced security is #{tc[:purchased]}" do
              stub_advanced_security_as_purchased(tc[:purchased])
              assert_equal tc[:expected], SecretScanning::Features::AdvancedSecurityHelper.advanced_security_available?(@org_repo)
            end
          end
        end

        context "EMU-owned repos" do
          test_cases = [
            { expected: true,  purchased: true },
            { expected: false, purchased: false }
          ]
          test_cases.each do |tc|
            test "returns #{tc[:expected]} when advanced security is #{tc[:purchased]}" do
              stub_advanced_security_as_purchased(tc[:purchased])
              assert_equal tc[:expected], SecretScanning::Features::AdvancedSecurityHelper.advanced_security_available?(@emu_owned_repo)
            end
          end
        end
      end
    end

    context "#secret_scanning_available?" do
      context "enterprise org-owned repos", enterprise_only: true do
        test_cases = [
          { expected: true,  purchased: "bundled" },
          { expected: true,  purchased: "secret_protection" },
          { expected: false, purchased: "code_security" },
          { expected: false, purchased: false },
        ]
        test_cases.each do |tc|
          test "returns #{tc[:expected]} when sku split is #{tc[:purchased]} is purchased" do
            stub_purchase_state(tc[:purchased])

            assert_equal tc[:expected], SecretScanning::Features::AdvancedSecurityHelper.secret_scanning_available?(@org_repo)
          end
        end
      end

      context "enterprise user", enterprise_only: true do
        test_cases = [
          { expected: true,  purchased: "bundled" },
          { expected: true,  purchased: "secret_protection" },
          { expected: false, purchased: "code_security" },
          { expected: false, purchased: false },
        ]
        test_cases.each do |tc|
          test "returns #{tc[:expected]} when sku split is #{tc[:purchased]} is purchased" do
            stub_purchase_state(tc[:purchased])

            assert_equal tc[:expected], SecretScanning::Features::AdvancedSecurityHelper.secret_scanning_available?(@user_owned_repo.owner)
          end
        end
      end

      context "enterprise user-owned repos", enterprise_only: true do
        test_cases = [
          { expected: true,  purchased: "bundled" },
          { expected: true,  purchased: "secret_protection" },
          { expected: false, purchased: "code_security" },
          { expected: false, purchased: false },
        ]
        test_cases.each do |tc|
          test "returns #{tc[:expected]} when sku split is #{tc[:purchased]} is purchased" do
            GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(true)
            stub_purchase_state(tc[:purchased])

            assert_equal tc[:expected], SecretScanning::Features::AdvancedSecurityHelper.secret_scanning_available?(@user_owned_repo)
          end
        end
      end

      context "dotcom org-owned repos", skip_enterprise: true do
        test_cases = [
          { expected: true,  purchased: "bundled" },
          { expected: true,  purchased: "secret_protection" },
          { expected: false, purchased: "code_security" },
          { expected: false, purchased: false },
        ]
        test_cases.each do |tc|
          test "returns #{tc[:expected]} when sku split is #{tc[:purchased]} is purchased" do
            stub_purchase_state(tc[:purchased])
            assert_equal tc[:expected], SecretScanning::Features::AdvancedSecurityHelper.secret_scanning_available?(@org_repo)
          end
        end
      end

      context "dotcom EMU-owned repos", skip_enterprise: true do
        test_cases = [
          { expected: true,  purchased: "bundled" },
          { expected: true,  purchased: "secret_protection" },
          { expected: false, purchased: "code_security" },
          { expected: false, purchased: false },
        ]
        test_cases.each do |tc|
          test "returns #{tc[:expected]} when sku split is #{tc[:purchased]} is purchased" do
            stub_purchase_state(tc[:purchased])
            assert_equal tc[:expected], SecretScanning::Features::AdvancedSecurityHelper.secret_scanning_available?(@emu_owned_repo)
          end
        end
      end

      context "dotcom EMU", skip_enterprise: true do
        test_cases = [
          { expected: true,  purchased: "bundled" },
          { expected: true,  purchased: "secret_protection" },
          { expected: false, purchased: "code_security" },
          { expected: false, purchased: false },
        ]
        test_cases.each do |tc|
          test "returns #{tc[:expected]} when sku split is #{tc[:purchased]} is purchased" do
            stub_purchase_state(tc[:purchased])
            assert_equal tc[:expected], SecretScanning::Features::AdvancedSecurityHelper.secret_scanning_available?(@emu_owned_repo.owner)
          end
        end
      end
    end

    context "#bundled_ghas_configurable?" do
      context "org-owned repos" do
        test_cases = [
          { expected: false, state: "unbundled" },
          { expected: true,  state: "bundled" },
        ]
        test_cases.each do |tc|
          test "returns #{tc[:expected]} when sku split is advanced security is #{tc[:state]}" do
            if tc[:state] == "unbundled"
              stub_secret_protection_as_purchased(true)
              @business.set_customer_to_split_metered_offering(actor: ::User.ghost)
            else
              stub_advanced_security_as_purchased(true)
              @business.mark_advanced_security_as_metered_for_entity(actor: ::User.ghost)
            end
            assert_equal tc[:expected], SecretScanning::Features::AdvancedSecurityHelper.bundled_ghas_configurable?(@org_repo)
          end
        end
      end

      context "enterprise user-owned repos", enterprise_only: true do
        test_cases = [
          { expected: false, state: "unbundled" },
          { expected: true,  state: "bundled" },
        ]
        test_cases.each do |tc|
          test "returns #{tc[:expected]} when sku split is advanced security is #{tc[:state]}" do
            GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(true)
            stub_advanced_security_as_purchased(true)
            if tc[:state] == "unbundled"
              stub_secret_protection_as_purchased(true)
              GitHub.global_business.set_customer_to_split_metered_offering(actor: ::User.ghost)
            else
              GitHub.global_business.mark_advanced_security_as_metered_for_entity(actor: ::User.ghost)
            end
            assert_equal tc[:expected], SecretScanning::Features::AdvancedSecurityHelper.bundled_ghas_configurable?(@user_owned_repo)
          end
        end
      end

      context "dotcom EMU-owned repos", skip_enterprise: true do
        test_cases = [
          { expected: false, state: "unbundled" },
          { expected: true,  state: "bundled" },
        ]
        test_cases.each do |tc|
          test "returns #{tc[:expected]} when sku split is advanced security is #{tc[:state]}" do
            if tc[:state] == "unbundled"
              stub_secret_protection_as_purchased(true)
            else
              stub_advanced_security_as_purchased(true)
            end
            assert_equal tc[:expected], SecretScanning::Features::AdvancedSecurityHelper.bundled_ghas_configurable?(@emu_owned_repo)
          end
        end
      end
    end
  end
end
