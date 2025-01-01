# typed: true
# frozen_string_literal: true

require "test_helper"

module SecretScanning::Features::Org
  class OrgTokenScanningTest < GitHub::TestCase
    include SecretScanning::Features::FeatureFlagHelper

    fixtures do
      @business = create(:business)
    end

    setup do
      @user = create(:user)
      @org = create(:business_plus_org, business: @business, admin: @user)
      @token_scanning = SecretScanning::Features::Org::TokenScanning.new(@org)
      GitHub.stubs(:configuration_secret_scanning_enabled?).returns(true)
      @org.stubs(:advanced_security_purchased?).returns(true)
      @business.stubs(:advanced_security_purchased?).returns(true)


      GitHub.flipper[FeatureFlags::READ_PUBLIC_REPO_ALERTS].enable
      @token_scanning_business = SecretScanning::Features::Business::TokenScanning.new(@business)

      @org_without_business = create(:organization)
      @token_scanning_org_without_business = SecretScanning::Features::Org::TokenScanning.new(@org_without_business)
      @org_without_business.stubs(:advanced_security_purchased?).returns(true)
    end

    context "initialize" do
      test "good input" do
        refute SecretScanning::Features::Org::TokenScanning.new(@org).nil?
      end
    end

    context "feature_available?" do
      test "returns true if all conditions are met" do
        assert @token_scanning.feature_available?
      end

      test "false if global config disabled" do
        GitHub.stubs(:configuration_secret_scanning_enabled?).returns(false)

        refute @token_scanning.feature_available?
      end

      test "false if GHAS not purchased and flag is disabled" do
        @org.stubs(:advanced_security_purchased?).returns(false)
        GitHub.flipper[FeatureFlags::READ_PUBLIC_REPO_ALERTS].disable

        refute @token_scanning.feature_available?
      end
    end

    context "enabled?" do
      test "true if feature available" do
        @token_scanning.stubs(:feature_available?).returns(true)
        assert @token_scanning.enabled?
      end

      test "false if feature unavailable" do
        @token_scanning.stubs(:feature_available?).returns(false)
        refute @token_scanning.enabled?
      end
    end

    context "enable_secret_scanning_for_new_repos" do
      test "user enable" do
        @token_scanning.enable_secret_scanning_for_new_repos(actor: @user)

        assert @token_scanning.secret_scanning_enabled_for_new_repos?
      end
    end

    context "disable_secret_scanning_for_new_repos" do
      test "user disable" do
        @token_scanning.enable_secret_scanning_for_new_repos(actor: @user)
        @token_scanning.disable_secret_scanning_for_new_repos(actor: @user)

        refute @token_scanning.secret_scanning_enabled_for_new_repos?
      end
    end

    context "get_admins_to_notify" do
      test "return org admins and security managers" do
        SecurityCenter::FeatureFlagHelper.stubs(:show_security_manager_in_org_role_assignment?).returns(true)

        # Add security manager for the org
        security_manager_user = create(:user)
        create(:security_manager_team, organization: @org).add_member(security_manager_user)

        directly_assigned_security_manager = create(:user)
        @org.add_member(directly_assigned_security_manager)
        @org.grant_org_role(assignee: directly_assigned_security_manager, role: Role.security_manager_role)

        admins_to_notify = @token_scanning.get_admins_to_notify
        assert_same_elements([security_manager_user, directly_assigned_security_manager, @user], admins_to_notify)
      end

      test "return org admins only if there are no security managers" do
        assert_equal [@user], @token_scanning.get_admins_to_notify
      end
    end
  end
end
