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

      test "returns false if feature flag is disabled, even if enabled" do
        GitHub.flipper[FeatureFlags::GENERIC_SECRETS_SCAN].disable
        @repo.config.enable(SecretScanning::Features::Repo::GenericSecrets::CONFIG_KEY_USER_ENABLED, @user)
        refute @generic_secrets_repo.feature_available?
      end

      test "returns true if feature flag is enabled" do
        GitHub.flipper[FeatureFlags::GENERIC_SECRETS_SCAN].enable
        @token_scanning_repo.enable(actor: @user)
        assert @generic_secrets_repo.feature_available?
      end
    end

    context "enabled?", skip_enterprise: true do
      test "returns false if the feature flag is disabled" do
        GitHub.flipper[FeatureFlags::GENERIC_SECRETS_SCAN].disable
        @token_scanning_repo.enable(actor: @user)
        @repo.config.enable(SecretScanning::Features::Repo::GenericSecrets::CONFIG_KEY_USER_ENABLED, @user)
        refute @generic_secrets_repo.enabled?
      end

      test "returns true if enabled by the repo" do
        GitHub.flipper[FeatureFlags::GENERIC_SECRETS_SCAN].enable
        @token_scanning_repo.enable(actor: @user)
        @repo.config.enable(SecretScanning::Features::Repo::GenericSecrets::CONFIG_KEY_USER_ENABLED, @user)
        assert @generic_secrets_repo.enabled?
      end

      test "returns true if enabled by the org" do
        GitHub.flipper[FeatureFlags::GENERIC_SECRETS_SCAN].enable
        @token_scanning_repo.enable(actor: @user)
        @org.config.enable(SecretScanning::Features::Org::GenericSecrets::CONFIG_KEY_USER_ENABLED, @user)
        assert @generic_secrets_repo.enabled?
      end

      test "returns true if enabled by the enterprise" do
        GitHub.flipper[FeatureFlags::GENERIC_SECRETS_SCAN].enable
        @token_scanning_repo.enable(actor: @user)
        @business.config.enable(SecretScanning::Features::Business::GenericSecrets::CONFIG_KEY_USER_ENABLED, @user)
        assert @generic_secrets_repo.enabled?
      end
    end

    context "show_user_feedback_link?" do
      test "false if not enabled" do
        GitHub.flipper[FeatureFlags::GENERIC_SECRETS_SCAN].enable
        @token_scanning_repo.enable(actor: @user)
        @generic_secrets_repo.disable(actor: @user)
        refute @generic_secrets_repo.show_user_feedback_link?(@user)
      end

      test "false if survey ff disabled" do
        GitHub.flipper[FeatureFlags::GENERIC_SECRETS_SCAN].enable
        GitHub.flipper[FeatureFlags::GENERIC_SECRETS_FEEDBACK_LINK].disable
        @token_scanning_repo.enable(actor: @user)
        @generic_secrets_repo.enable(actor: @user)
        refute @generic_secrets_repo.show_user_feedback_link?(@user)
      end

      test "false if user dismissed" do
        GitHub.flipper[FeatureFlags::GENERIC_SECRETS_SCAN].enable
        GitHub.flipper[FeatureFlags::GENERIC_SECRETS_FEEDBACK_LINK].enable
        User.any_instance.stubs(:dismissed_notice?).returns(true)
        @token_scanning_repo.enable(actor: @user)
        @generic_secrets_repo.enable(actor: @user)
        refute @generic_secrets_repo.show_user_feedback_link?(@user)
      end

      test "true when ff enabled, feature enabled, and not dismissed" do
        GitHub.flipper[FeatureFlags::GENERIC_SECRETS_SCAN].enable
        GitHub.flipper[FeatureFlags::GENERIC_SECRETS_FEEDBACK_LINK].enable
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
