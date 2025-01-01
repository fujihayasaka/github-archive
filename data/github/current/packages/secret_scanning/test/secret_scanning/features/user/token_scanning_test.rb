# typed: true
# frozen_string_literal: true

require "test_helper"

module SecretScanning::Features::User
  class UserTokenScanningTest < GitHub::TestCase
    include SecretScanning::Features::FeatureFlagHelper

    fixtures do
      @user = create(:user)
    end

    setup do
      @user_token_scanning = SecretScanning::Features::User::TokenScanning.new(@user)
      @user.config.disable(SecretScanning::Features::User::TokenScanning::SECRET_SCANNING_NEW_REPOS_KEY, @user)
      GitHub.stubs(:configuration_secret_scanning_enabled?).returns(true)

      AdvancedSecurity::Features::User::AdvancedSecurity.any_instance.stubs(:feature_available?).returns(true)
    end

    context "initialize" do
      test "good input" do
        refute @user_token_scanning.nil?
      end
    end

    context "config" do
      test "enable/disable secret scanning for new repos" do
        refute @user_token_scanning.secret_scanning_enabled_for_new_repos?

        @user_token_scanning.enable_secret_scanning_for_new_repos(actor: @user)
        assert @user_token_scanning.secret_scanning_enabled_for_new_repos?

        @user_token_scanning.disable_secret_scanning_for_new_repos(actor: @user)
        refute @user_token_scanning.secret_scanning_enabled_for_new_repos?
      end

    end

    context "feature_available?" do
      test "returns true if all conditions are met" do
        assert @user_token_scanning.feature_available?
      end

      test "false if global config disabled" do
        GitHub.stubs(:configuration_secret_scanning_enabled?).returns(false)
        refute @user_token_scanning.feature_available?
      end

      test "false if advanced security is not purchased" do
        AdvancedSecurity::Features::User::AdvancedSecurity.any_instance.stubs(:feature_available?).returns(false)
        refute @user_token_scanning.feature_available?
      end
    end

    context "enabled?" do
      test "true if feature available" do
        @user_token_scanning.stubs(:feature_available?).returns(true)
        assert @user_token_scanning.enabled?
      end

      test "false if feature unavailable" do
        @user_token_scanning.stubs(:feature_available?).returns(false)
        refute @user_token_scanning.enabled?
      end
    end
  end
end
