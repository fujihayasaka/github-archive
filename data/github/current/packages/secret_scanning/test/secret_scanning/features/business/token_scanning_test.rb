# typed: true
# frozen_string_literal: true

require "test_helper"

module SecretScanning::Features::Business
  class BusinessTokenScanningTest < GitHub::TestCase
    include SecretScanning::Features::FeatureFlagHelper


    setup do
      @user = create(:user)
      @business = create(:business)
      @token_scanning = SecretScanning::Features::Business::TokenScanning.new(@business)
      GitHub.stubs(:configuration_secret_scanning_enabled?).returns(true)

      # Add business admin
      @business.add_owner(@user, actor: @user)
    end

    context "initialize" do
      test "good input" do
        refute SecretScanning::Features::Business::TokenScanning.new(@business).nil?
      end
    end

    context "feature_available?" do
      test "false if global config disabled" do
        GitHub.stubs(:configuration_secret_scanning_enabled?).returns(false)
        refute @token_scanning.feature_available?
      end

      test "defaults to true" do
        assert @token_scanning.feature_available?
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
        @token_scanning.disable_secret_scanning_for_new_repos(actor: @user)

        refute @token_scanning.secret_scanning_enabled_for_new_repos?
      end
    end

    context "get_admins_to_notify" do
      test "return enterprise admins" do
        assert_same_elements @business.admins, @token_scanning.get_admins_to_notify
      end
    end
  end
end
