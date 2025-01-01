# typed: true
# frozen_string_literal: true

require "test_helper"

module SecretScanning::Features::Org
  class OrgDelegatedBypassTest < GitHub::TestCase
    include SecretScanning::Features::FeatureFlagHelper

    setup do
      @business = create(:business)
      @business.stubs(:advanced_security_purchased?).returns(true)
      @org = create(:business_plus_org, business: @business)
      @user = create(:user)
      @delegated_bypass_org = SecretScanning::Features::Org::DelegatedBypass.new(@org)

      @org.stubs(:advanced_security_purchased?).returns(true)
      GitHub.stubs(:configuration_secret_scanning_enabled?).returns(true)
    end

    context "initialize" do
      test "good input" do
        refute SecretScanning::Features::Org::DelegatedBypass.new(@org).nil?
      end
    end

    context "feature_available?" do
      test "returns false if advanced security is not purchased" do
        @org.stubs(:advanced_security_purchased?).returns(false)
        refute @delegated_bypass_org.feature_available?
      end

      test "returns false if the org does not have push protection available" do
        SecretScanning::Features::Org::PushProtection.any_instance.stubs(:feature_available?).returns(false)
        refute @delegated_bypass_org.feature_available?
      end

      test "returns true if feature flag is enabled" do
        assert @delegated_bypass_org.feature_available?
      end
    end

    context "enabled?" do
      test "returns true if enabled by the org" do
        @org.config.enable(SecretScanning::Features::Org::DelegatedBypass::CONFIG_KEY_USER_ENABLED, @user)
        assert @delegated_bypass_org.enabled?
      end
    end
  end
end
