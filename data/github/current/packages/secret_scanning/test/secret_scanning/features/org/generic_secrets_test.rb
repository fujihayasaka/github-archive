# typed: true
# frozen_string_literal: true

require "test_helper"

module SecretScanning::Features::Org
  class OrgGenericSecretsTest < GitHub::TestCase
    include SecretScanning::Features::FeatureFlagHelper

    setup do
      @business = create(:business)
      @business.stubs(:advanced_security_purchased?).returns(true)
      @org = create(:business_plus_org, business: @business)
      @user = create(:user)
      @token_scanning_org = SecretScanning::Features::Org::TokenScanning.new(@org)
      @generic_secrets_org = SecretScanning::Features::Org::GenericSecrets.new(@org)
      @generic_secrets_business = SecretScanning::Features::Business::GenericSecrets.new(@business)

      @org.stubs(:advanced_security_purchased?).returns(true)
      GitHub.stubs(:configuration_secret_scanning_enabled?).returns(true)
    end

    context "initialize" do
      test "good input" do
        refute SecretScanning::Features::Org::GenericSecrets.new(@org).nil?
      end
    end

    context "feature_available?", skip_enterprise: true do
      test "returns false if advanced security is not purchased" do
        @org.stubs(:advanced_security_purchased?).returns(false)
        refute @generic_secrets_org.feature_available?
      end

      test "returns false if the org does not have token scanning available" do
        SecretScanning::Features::Org::TokenScanning.any_instance.stubs(:feature_available?).returns(false)
        refute @generic_secrets_org.feature_available?
      end

      test "returns true" do
        assert @generic_secrets_org.feature_available?
      end
    end

    context "enabled?", skip_enterprise: true do
      test "returns true if enabled by the org" do
        @org.config.enable(SecretScanning::Features::Org::GenericSecrets::CONFIG_KEY_USER_ENABLED, @user)
        assert @generic_secrets_org.enabled?
      end

      test "returns true if enabled by the enterprise" do
        @business.config.enable(SecretScanning::Features::Business::GenericSecrets::CONFIG_KEY_USER_ENABLED, @user)
        unless @generic_secrets_org.show_security_config_ux?
          assert @generic_secrets_org.enabled?
        end
      end
    end

    context "show_user_feedback_link?" do
      test "false if not enabled" do
        @generic_secrets_org.disable(actor: @user)
        refute @generic_secrets_org.show_user_feedback_link?(@user)
      end

      test "false if survey ff disabled" do
        GitHub.flipper[FeatureFlags::GENERIC_SECRETS_FEEDBACK_LINK].disable
        @generic_secrets_org.enable(actor: @user)
        refute @generic_secrets_org.show_user_feedback_link?(@user)
      end

      test "false if user dismissed" do
        GitHub.flipper[FeatureFlags::GENERIC_SECRETS_FEEDBACK_LINK].enable
        User.any_instance.stubs(:dismissed_notice?).returns(true)
        @generic_secrets_org.enable(actor: @user)
        refute @generic_secrets_org.show_user_feedback_link?(@user)
      end

      test "true when ff enabled, feature enabled, and not dismissed" do
        GitHub.flipper[FeatureFlags::GENERIC_SECRETS_FEEDBACK_LINK].enable
        User.any_instance.stubs(:dismissed_notice?).returns(false)
        @generic_secrets_org.enable(actor: @user)
        if GitHub.single_or_multi_tenant_enterprise?
          refute @generic_secrets_org.show_user_feedback_link?(@user)
        else
          assert @generic_secrets_org.show_user_feedback_link?(@user)
        end
      end
    end
  end
end
