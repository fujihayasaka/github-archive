# typed: true
# frozen_string_literal: true

require "test_helper"

module SecretScanning::Features::Business
  class BusinessContentScanningTest < GitHub::TestCase
    include SecretScanning::Features::FeatureFlagHelper

    fixtures do
      @business = create(:business)
      @org = create(:business_plus_org, business: @business)
      @user = create(:user)
    end

    setup do
      @content_scanning = SecretScanning::Features::Business::ContentScanning.new(@business)
    end

    context "initialize" do
      test "good input" do
        refute SecretScanning::Features::Business::ContentScanning.new(@business).nil?
      end
    end

    context "feature_available?" do
      test "true if public scanning enabled", skip_enterprise: true do
        SecretScanning::Features::Business::PublicScanning.any_instance.stubs(:enabled?).returns(true)
        assert @content_scanning.feature_available?
      end

      test "true if token scanning enabled", skip_enterprise: true do
        SecretScanning::Features::Business::TokenScanning.any_instance.stubs(:enabled?).returns(true)
        assert @content_scanning.feature_available?
      end

      test "false if token scanning not enabled" do
        SecretScanning::Features::Business::PublicScanning.any_instance.stubs(:feature_available?).returns(false)
        SecretScanning::Features::Business::TokenScanning.any_instance.stubs(:enabled?).returns(false)
        refute @content_scanning.feature_available?
      end
    end

    context "enabled?" do
      test "true if feature available" do
        SecretScanning::Features::Business::ContentScanning.any_instance.stubs(:feature_available?).returns(true)
        assert @content_scanning.enabled?
      end

      test "false if feature not available" do
        SecretScanning::Features::Business::ContentScanning.any_instance.stubs(:feature_available?).returns(false)
        refute @content_scanning.enabled?
      end

      test "true by default on enterprise", enterprise_only: true do
        SecretScanning::Features::Business::TokenScanning.any_instance.stubs(:enabled?).returns(true)
        assert @content_scanning.enabled?
      end

      test "false if enterprise and explicitly enabled when repo is disabled", enterprise_only: true do
        GitHub.stubs(:secret_scanning_for_all_content_types_enabled?).returns(true)
        SecretScanning::Features::Business::TokenScanning.any_instance.stubs(:enabled?).returns(false)
        refute @content_scanning.enabled?
      end

      test "false if enterprise and explicitly disabled when repo is enabled", enterprise_only: true do
        GitHub.stubs(:secret_scanning_for_all_content_types_enabled?).returns(false)
        SecretScanning::Features::Business::TokenScanning.any_instance.stubs(:enabled?).returns(true)
        refute @content_scanning.enabled?
      end
    end
  end
end
