# typed: true
# frozen_string_literal: true

require "test_helper"

module SecretScanning::Features::User
  class UserLowerConfidencePatternsTest < GitHub::TestCase
    include SecretScanning::Features::FeatureFlagHelper

    fixtures do
      GitHub::Enterprise.ensure_business! if GitHub.single_business_environment?
      @user = create(:user)
      @business = create(:global_business)
      unless GitHub.enterprise?
        @emu = create(:emu)
      end
    end

    setup do
      @lower_confidence_patterns_user = SecretScanning::Features::User::LowerConfidencePatterns.new(@user)
    end

    context "initialize" do
      test "good input" do
        refute SecretScanning::Features::User::LowerConfidencePatterns.new(@user).nil?
      end
    end

    context "feature_available?" do
      test "always returns false" do
        refute @lower_confidence_patterns_user.feature_available?
      end
    end

    context "enabled?" do
      test "always returns false" do
        refute @lower_confidence_patterns_user.enabled?
      end
    end

    context "enabled_by_enterprise?" do
      context "with a non-enterprise-managed business", skip_enterprise: true do
        test "returns false, even if the business has enabled the feature" do
          SecretScanning::Features::Business::LowerConfidencePatterns.any_instance.stubs(:enabled?).returns(true)
          refute @lower_confidence_patterns_user.enabled_by_enterprise?
        end
      end

      context "with an enterprise-managed business", skip_enterprise: true do
        test "returns true if the business has enabled the feature" do
          emu_settings = SecretScanning::Features::User::LowerConfidencePatterns.new(@emu)
          refute emu_settings.enabled_by_enterprise?
          SecretScanning::Features::Business::LowerConfidencePatterns.any_instance.stubs(:enabled?).returns(true)
          assert emu_settings.enabled_by_enterprise?
        end
      end

      context "on GHES", enterprise_only: true do
        test "returns true if the global enterprise has enabled the feature" do
          refute @lower_confidence_patterns_user.enabled_by_enterprise?
          SecretScanning::Features::Business::LowerConfidencePatterns.any_instance.stubs(:enabled?).returns(true)
          assert @lower_confidence_patterns_user.enabled_by_enterprise?
        end
      end
    end

    context "enable" do
      test "does nothing" do
        refute @lower_confidence_patterns_user.enabled?
        @lower_confidence_patterns_user.enable(actor: @user)
        refute @lower_confidence_patterns_user.enabled?
      end
    end

    context "disable" do
      test "does nothing" do
        refute @lower_confidence_patterns_user.enabled?
        @lower_confidence_patterns_user.disable(actor: @user)
        refute @lower_confidence_patterns_user.enabled?
      end
    end
  end
end
