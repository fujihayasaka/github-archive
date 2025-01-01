# typed: true
# frozen_string_literal: true

require "test_helper"

module SecretScanning::Features::Owner
  class OwnerTokenScanningTest < GitHub::TestCase
    include SecretScanning::Features::FeatureFlagHelper

    fixtures do
      @business = create(:business)
      @user = create(:user)
    end

    setup do
      @org = create(:business_plus_org, business: @business)
      @org_token_scanning = SecretScanning::Features::Owner::TokenScanning.new(@org)
      GitHub.stubs(:configuration_secret_scanning_enabled?).returns(true)
    end

    context "initialize" do
      test "good input" do
        refute SecretScanning::Features::Owner::TokenScanning.new(@org).nil?
        refute SecretScanning::Features::Owner::TokenScanning.new(@user).nil?
      end
    end

    context "feature_available? (org)" do
      test "returns true if all conditions are met" do
        assert @org_token_scanning.feature_available?
      end

      test "false if global config disabled" do
        GitHub.stubs(:configuration_secret_scanning_enabled?).returns(false)

        refute @org_token_scanning.feature_available?
      end
    end
  end
end
