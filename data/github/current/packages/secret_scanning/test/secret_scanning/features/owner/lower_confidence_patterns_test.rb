# typed: true
# frozen_string_literal: true

require "test_helper"

module SecretScanning::Features::Owner
  class OwnerLowerConfidencePatternsTest < GitHub::TestCase
    include SecretScanning::Features::FeatureFlagHelper

    fixtures do
      @business = create(:business)
      @user = create(:user)
      @org = create(:business_plus_org, business: @business)
    end

    setup do
      GitHub.stubs(:configuration_secret_scanning_enabled?).returns(true)
      @org.stubs(:advanced_security_purchased?).returns(true)
      @business.stubs(:advanced_security_purchased?).returns(true)

      @org_lower_confidence_patterns = SecretScanning::Features::Org::LowerConfidencePatterns.new(@org)
      @business_lower_confidence_patterns = SecretScanning::Features::Business::LowerConfidencePatterns.new(@business)
      @user_lower_confidence_patterns = SecretScanning::Features::User::LowerConfidencePatterns.new(@user)
    end

    context "initialize" do
      test "good input" do
        refute SecretScanning::Features::Owner::LowerConfidencePatterns.new(@business).nil?
        refute SecretScanning::Features::Owner::LowerConfidencePatterns.new(@org).nil?
        refute SecretScanning::Features::Owner::LowerConfidencePatterns.new(@user).nil?
      end
    end

    context "business owner delegates" do
      context "feature_available?" do
        test "without token scanning" do
          @owner_lower_confidence_patterns = SecretScanning::Features::Owner::LowerConfidencePatterns.new(@business)
          SecretScanning::Features::Business::TokenScanning.any_instance.stubs(:feature_available?).returns(false)
          refute @owner_lower_confidence_patterns.feature_available?
          refute @business_lower_confidence_patterns.feature_available?
        end
        test "with token scanning" do
          @owner_lower_confidence_patterns = SecretScanning::Features::Owner::LowerConfidencePatterns.new(@business)
          assert @owner_lower_confidence_patterns.feature_available?
          assert @business_lower_confidence_patterns.feature_available?
        end
      end
      test "enable/disable/enabled?" do
        @owner_lower_confidence_patterns = SecretScanning::Features::Owner::LowerConfidencePatterns.new(@business)
        refute @owner_lower_confidence_patterns.enabled?
        refute @business_lower_confidence_patterns.enabled?
        @owner_lower_confidence_patterns.enable(actor: @user)
        assert @owner_lower_confidence_patterns.enabled?
        assert @business_lower_confidence_patterns.enabled?
        @owner_lower_confidence_patterns.disable(actor: @user)
        refute @owner_lower_confidence_patterns.enabled?
        refute @business_lower_confidence_patterns.enabled?
      end
    end

    context "org owner delegates" do
      context "feature_available?" do
        test "without token scanning" do
          @owner_lower_confidence_patterns = SecretScanning::Features::Owner::LowerConfidencePatterns.new(@org)
          SecretScanning::Features::Org::TokenScanning.any_instance.stubs(:feature_available?).returns(false)
          refute @owner_lower_confidence_patterns.feature_available?
          refute @org_lower_confidence_patterns.feature_available?
        end
        test "with token scanning" do
          @owner_lower_confidence_patterns = SecretScanning::Features::Owner::LowerConfidencePatterns.new(@org)
          assert @owner_lower_confidence_patterns.feature_available?
          assert @org_lower_confidence_patterns.feature_available?
        end
      end
      test "enable/disable/enabled?" do
        @owner_lower_confidence_patterns = SecretScanning::Features::Owner::LowerConfidencePatterns.new(@org)
        refute @owner_lower_confidence_patterns.enabled?
        refute @org_lower_confidence_patterns.enabled?
        @owner_lower_confidence_patterns.enable(actor: @user)
        assert @owner_lower_confidence_patterns.enabled?
        assert @org_lower_confidence_patterns.enabled?
        @owner_lower_confidence_patterns.disable(actor: @user)
        refute @owner_lower_confidence_patterns.enabled?
        refute @org_lower_confidence_patterns.enabled?
      end
      test "enabled_by_owning_business?" do
        SecretScanning::Features::Business::LowerConfidencePatterns.any_instance.stubs(:enabled?).returns(true)
        @owner_lower_confidence_patterns = SecretScanning::Features::Owner::LowerConfidencePatterns.new(@org)
        if @owner_lower_confidence_patterns.show_security_config_ux?
          refute @owner_lower_confidence_patterns.enabled_by_owning_business?
          refute @org_lower_confidence_patterns.enabled_by_enterprise?
        else
          assert @owner_lower_confidence_patterns.enabled_by_owning_business?
          assert @org_lower_confidence_patterns.enabled_by_enterprise?
        end
        SecretScanning::Features::Business::LowerConfidencePatterns.any_instance.stubs(:enabled?).returns(false)
        refute @owner_lower_confidence_patterns.enabled_by_owning_business?
        refute @org_lower_confidence_patterns.enabled_by_enterprise?
      end
    end

    context "user owner (not supported) delegates" do
      context "feature_available?" do
        test "without token scanning" do
          @owner_lower_confidence_patterns = SecretScanning::Features::Owner::LowerConfidencePatterns.new(@user)
          SecretScanning::Features::User::TokenScanning.any_instance.stubs(:feature_available?).returns(false)
          refute @owner_lower_confidence_patterns.feature_available?
          refute @user_lower_confidence_patterns.feature_available?
        end
        test "even with token scanning" do
          @owner_lower_confidence_patterns = SecretScanning::Features::Owner::LowerConfidencePatterns.new(@user)
          SecretScanning::Features::User::TokenScanning.any_instance.stubs(:feature_available?).returns(true)
          refute @owner_lower_confidence_patterns.feature_available?
          refute @user_lower_confidence_patterns.feature_available?
        end
      end
      test "enable/disable/enabled?" do
        @owner_lower_confidence_patterns = SecretScanning::Features::Owner::LowerConfidencePatterns.new(@user)
        refute @owner_lower_confidence_patterns.enabled?
        refute @user_lower_confidence_patterns.enabled?
        @owner_lower_confidence_patterns.enable(actor: @user)
        refute @owner_lower_confidence_patterns.enabled?
        refute @user_lower_confidence_patterns.enabled?
        @owner_lower_confidence_patterns.disable(actor: @user)
        refute @owner_lower_confidence_patterns.enabled?
        refute @user_lower_confidence_patterns.enabled?
      end
    end
  end
end
