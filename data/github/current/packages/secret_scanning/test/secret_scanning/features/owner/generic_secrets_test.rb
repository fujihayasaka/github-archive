# typed: true
# frozen_string_literal: true

require "test_helper"

module SecretScanning::Features::Owner
  class OwnerGenericSecretsTest < GitHub::TestCase
    include SecretScanning::Features::FeatureFlagHelper

    fixtures do
      @business = create(:business)
      @user = create(:user)
      @org = create(:business_plus_org, business: @business)
    end

    setup do
      GitHub.stubs(:configuration_secret_scanning_enabled?).returns(true)
      @business.stubs(:advanced_security_purchased?).returns(true)
      @org.stubs(:advanced_security_purchased?).returns(true)

      @org_generic_secrets = SecretScanning::Features::Org::GenericSecrets.new(@org)
      @business_generic_secrets = SecretScanning::Features::Business::GenericSecrets.new(@business)
      @user_generic_secrets = SecretScanning::Features::User::GenericSecrets.new(@user)
    end

    context "initialize" do
      test "good input" do
        refute SecretScanning::Features::Owner::GenericSecrets.new(@business).nil?
        refute SecretScanning::Features::Owner::GenericSecrets.new(@org).nil?
        refute SecretScanning::Features::Owner::GenericSecrets.new(@user).nil?
      end
    end

    context "business owner delegates", skip_enterprise: true do
      context "feature_available?" do
        test "false if advanced security is unavailable" do
          @owner_generic_secrets = SecretScanning::Features::Owner::GenericSecrets.new(@business)
          @business.stubs(:advanced_security_purchased?).returns(false)
          refute @owner_generic_secrets.feature_available?
        end

        test "without token scanning" do
          @owner_generic_secrets = SecretScanning::Features::Owner::GenericSecrets.new(@business)
          SecretScanning::Features::Business::TokenScanning.any_instance.stubs(:feature_available?).returns(false)
          refute @owner_generic_secrets.feature_available?
          refute @business_generic_secrets.feature_available?
        end
        test "with token scanning" do
          @owner_generic_secrets = SecretScanning::Features::Owner::GenericSecrets.new(@business)
          assert @owner_generic_secrets.feature_available?
          assert @business_generic_secrets.feature_available?
        end
      end
      test "enable/disable/enabled?" do
        @owner_generic_secrets = SecretScanning::Features::Owner::GenericSecrets.new(@business)
        refute @owner_generic_secrets.enabled?
        refute @business_generic_secrets.enabled?
        @owner_generic_secrets.enable(actor: @user)
        assert @owner_generic_secrets.enabled?
        assert @business_generic_secrets.enabled?
        @owner_generic_secrets.disable(actor: @user)
        refute @owner_generic_secrets.enabled?
        refute @business_generic_secrets.enabled?
      end
    end

    context "org owner delegates", skip_enterprise: true do
      context "feature_available?" do
        test "false if advanced security is unavailable" do
          @owner_generic_secrets = SecretScanning::Features::Owner::GenericSecrets.new(@org)
          @org.stubs(:advanced_security_purchased?).returns(false)
          refute @org_generic_secrets.feature_available?
        end
        test "without token scanning" do
          @owner_generic_secrets = SecretScanning::Features::Owner::GenericSecrets.new(@org)
          SecretScanning::Features::Org::TokenScanning.any_instance.stubs(:feature_available?).returns(false)
          refute @owner_generic_secrets.feature_available?
          refute @org_generic_secrets.feature_available?
        end
        test "with token scanning" do
          @owner_generic_secrets = SecretScanning::Features::Owner::GenericSecrets.new(@org)
          assert @owner_generic_secrets.feature_available?
          assert @org_generic_secrets.feature_available?
        end
      end
      test "enable/disable/enabled?" do
        @owner_generic_secrets = SecretScanning::Features::Owner::GenericSecrets.new(@org)
        refute @owner_generic_secrets.enabled?
        refute @org_generic_secrets.enabled?
        @owner_generic_secrets.enable(actor: @user)
        assert @owner_generic_secrets.enabled?
        assert @org_generic_secrets.enabled?
        @owner_generic_secrets.disable(actor: @user)
        refute @owner_generic_secrets.enabled?
        refute @org_generic_secrets.enabled?
      end
      test "enabled_by_owning_business?" do
        SecretScanning::Features::Business::GenericSecrets.any_instance.stubs(:enabled?).returns(true)
        @owner_generic_secrets = SecretScanning::Features::Owner::GenericSecrets.new(@org)
        if @owner_generic_secrets.show_security_config_ux?
          refute @owner_generic_secrets.enabled_by_owning_business?
          refute @org_generic_secrets.enabled_by_enterprise?
        else
          assert @owner_generic_secrets.enabled_by_owning_business?
          assert @org_generic_secrets.enabled_by_enterprise?
        end
        SecretScanning::Features::Business::GenericSecrets.any_instance.stubs(:enabled?).returns(false)
        refute @owner_generic_secrets.enabled_by_owning_business?
        refute @org_generic_secrets.enabled_by_enterprise?
      end
    end

    context "user owner (not supported) delegates" do
      context "feature_available?" do
        test "without token scanning" do
          @owner_generic_secrets = SecretScanning::Features::Owner::GenericSecrets.new(@user)
          SecretScanning::Features::User::TokenScanning.any_instance.stubs(:feature_available?).returns(false)
          refute @owner_generic_secrets.feature_available?
          refute @user_generic_secrets.feature_available?
        end
        test "even with token scanning" do
          @owner_generic_secrets = SecretScanning::Features::Owner::GenericSecrets.new(@user)
          SecretScanning::Features::User::TokenScanning.any_instance.stubs(:feature_available?).returns(true)
          refute @owner_generic_secrets.feature_available?
          refute @user_generic_secrets.feature_available?
        end
      end
      test "enable/disable/enabled?" do
        @owner_generic_secrets = SecretScanning::Features::Owner::GenericSecrets.new(@user)
        refute @owner_generic_secrets.enabled?
        refute @user_generic_secrets.enabled?
        @owner_generic_secrets.enable(actor: @user)
        refute @owner_generic_secrets.enabled?
        refute @user_generic_secrets.enabled?
        @owner_generic_secrets.disable(actor: @user)
        refute @owner_generic_secrets.enabled?
        refute @user_generic_secrets.enabled?
      end
    end
  end
end
