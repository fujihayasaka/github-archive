# typed: true
# frozen_string_literal: true

require "test_helper"

module SecretScanning::Features::Repo
  class RepoGenericSecretsTest < GitHub::TestCase
    include SecretScanning::Features::FeatureFlagHelper

    setup do
      @business = create(:business)
      @business.stubs(:advanced_security_purchased?).returns(true)
      @org = create(:business_plus_org, business: @business)
      @user = create(:user)
      @repo = create(:private_repository, owner: @org)
      @token_scanning_repo = SecretScanning::Features::Repo::TokenScanning.new(@repo)
      @generic_secrets_repo = SecretScanning::Features::Repo::GenericSecrets.new(@repo)

      @org.stubs(:advanced_security_purchased?).returns(true)
      @repo.stubs(:advanced_security_enabled?).returns(true)
      GitHub.stubs(:configuration_secret_scanning_enabled?).returns(true)
    end

    context "initialize" do
      test "good input" do
        refute SecretScanning::Features::Repo::GenericSecrets.new(@repo).nil?
      end
    end

    context "feature_available?", skip_enterprise: true do
      test "returns false if the owner has not purchased advanced security" do
        @org.stubs(:advanced_security_purchased?).returns(false)
        refute @generic_secrets_repo.feature_available?
      end

      test "returns false if token scanning is not enabled" do
        @token_scanning_repo.disable(actor: @user)
        refute @generic_secrets_repo.feature_available?
      end

      test "returns false if generic secrets is staff disabled" do
        @generic_secrets_repo.staff_disable(actor: @repo.owner)
        refute @generic_secrets_repo.feature_available?
      end

      test "returns true if token scanning is enabled" do
        @token_scanning_repo.enable(actor: @user)
        assert @generic_secrets_repo.feature_available?
      end

      test "returns false if sku split is enabled and GHAS/secret scanning license is not purchased" do
        @token_scanning_repo.enable(actor: @user)
        @org.stubs(:advanced_security_purchased?).returns(false)
        @org.stubs(:secret_protection_purchased?).returns(false)
        refute @generic_secrets_repo.feature_available?
      end

      test "returns true if sku split is enabled and secret scanning license is purchased" do
        @token_scanning_repo.enable(actor: @user)
        @org.stubs(:secret_protection_purchased?).returns(true)
        assert @generic_secrets_repo.feature_available?
      end
    end

    context "enabled?", skip_enterprise: true do
      test "returns true if enabled by the repo" do
        @token_scanning_repo.enable(actor: @user)
        @repo.config.enable(SecretScanning::Features::Repo::GenericSecrets::CONFIG_KEY_USER_ENABLED, @user)
        assert @generic_secrets_repo.enabled?
      end

      test "returns true if enabled by the org" do
        @token_scanning_repo.enable(actor: @user)
        @org.config.enable(SecretScanning::Features::Org::GenericSecrets::CONFIG_KEY_USER_ENABLED, @user)
        if GitHub.flipper[SecretScanning::Features::FeatureFlagHelper::FeatureFlags::GENERIC_SECRETS_IN_SECURITY_CONFIGURATIONS].enabled?
          refute @generic_secrets_repo.enabled?
        else
          assert @generic_secrets_repo.enabled?
        end
      end

      test "returns true if enabled by the enterprise" do
        @token_scanning_repo.enable(actor: @user)
        @business.config.enable(SecretScanning::Features::Business::GenericSecrets::CONFIG_KEY_USER_ENABLED, @user)
        if GitHub.flipper[SecretScanning::Features::FeatureFlagHelper::FeatureFlags::GENERIC_SECRETS_IN_SECURITY_CONFIGURATIONS].enabled?
          refute @generic_secrets_repo.enabled?
        else
          assert @generic_secrets_repo.enabled?
        end
      end
    end

    context "staff_disable", skip_enterprise: true do
      test "staff lock" do
        @token_scanning_repo.enable(actor: @user)
        @generic_secrets_repo.enable(actor: @repo.owner)

        @generic_secrets_repo.staff_disable(actor: @repo.owner)
        assert @generic_secrets_repo.staff_disabled?
        refute @generic_secrets_repo.enabled?

        @generic_secrets_repo.staff_unlock(actor: @repo.owner)
        refute @generic_secrets_repo.staff_disabled?
        assert @generic_secrets_repo.enabled?
      end
    end

    context "show_user_feedback_link?" do
      test "false if not enabled" do
        @token_scanning_repo.enable(actor: @user)
        @generic_secrets_repo.disable(actor: @user)
        refute @generic_secrets_repo.show_user_feedback_link?(@user)
      end

      test "false if survey ff disabled" do
        disable_feature_flag(FeatureFlags::GENERIC_SECRETS_FEEDBACK_LINK)
        @token_scanning_repo.enable(actor: @user)
        @generic_secrets_repo.enable(actor: @user)
        refute @generic_secrets_repo.show_user_feedback_link?(@user)
      end

      test "false if user dismissed" do
        enable_feature_flag(FeatureFlags::GENERIC_SECRETS_FEEDBACK_LINK)
        User.any_instance.stubs(:dismissed_notice?).returns(true)
        @token_scanning_repo.enable(actor: @user)
        @generic_secrets_repo.enable(actor: @user)
        refute @generic_secrets_repo.show_user_feedback_link?(@user)
      end

      test "true when ff enabled, feature enabled, and not dismissed" do
        enable_feature_flag(FeatureFlags::GENERIC_SECRETS_FEEDBACK_LINK)
        User.any_instance.stubs(:dismissed_notice?).returns(false)
        @token_scanning_repo.enable(actor: @user)
        @generic_secrets_repo.enable(actor: @user)
        if GitHub.single_or_multi_tenant_enterprise?
          refute @generic_secrets_repo.show_user_feedback_link?(@user)
        else
          assert @generic_secrets_repo.show_user_feedback_link?(@user)
        end
      end
    end
  end
end
