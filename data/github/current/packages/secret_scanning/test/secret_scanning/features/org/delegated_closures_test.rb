# typed: true
# frozen_string_literal: true

require "test_helper"

module SecretScanning::Features::Org
  class OrgDelegatedClosuresTest < GitHub::TestCase
    include SecretScanning::Features::FeatureFlagHelper

    setup do
      @business = create(:business)
      @business.stubs(:advanced_security_purchased?).returns(true)
      @org = create(:business_plus_org, business: @business)
      @user = create(:user)
      @delegated_closures_org = SecretScanning::Features::Org::DelegatedClosures.new(@org)

      @org.stubs(:advanced_security_purchased?).returns(true)
      SecretScanning::Features::Org::TokenScanning.any_instance.stubs(:enabled?).returns(true)
      GitHub.stubs(:configuration_secret_scanning_enabled?).returns(true)
      GitHub.flipper[FeatureFlags::SHOW_CLOSURE_REQUESTS_ORG_SETTING].enable
    end

    context "initialize" do
      test "good input" do
        refute_nil @delegated_closures_org
      end
    end

    context "feature_available?" do
      test "returns false if the org does not have token scanning enabled" do
        SecretScanning::Features::Org::TokenScanning.any_instance.stubs(:enabled?).returns(false)
        refute @delegated_closures_org.feature_available?
      end

      test "returns false for free orgs without GHAS purchased" do
        free_org = create(:organization)
        free_org.stubs(:advanced_security_purchased?).returns(false)
        refute SecretScanning::Features::Org::DelegatedClosures.new(free_org).feature_available?
      end

      test "returns false if the feature flag is disabled" do
        GitHub.flipper[FeatureFlags::SHOW_CLOSURE_REQUESTS_ORG_SETTING].disable
        refute @delegated_closures_org.feature_available?
      end

      test "returns true if org has purchased GHAS" do
        assert @delegated_closures_org.feature_available?
      end
    end

    context "enabled?" do
      test "returns false if feature isn't available" do
        @delegated_closures_org.stubs(:feature_available?).returns(false)
        @delegated_closures_org.enable(actor: @user)
        refute @delegated_closures_org.enabled?
      end

      test "returns feature enablement status" do
        @delegated_closures_org.enable(actor: @user)
        assert @delegated_closures_org.enabled?
        @delegated_closures_org.disable(actor: @user)
        refute @delegated_closures_org.enabled?
      end
    end
  end
end
