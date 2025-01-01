# typed: true
# frozen_string_literal: true

require "test_helper"

module SecretScanning::Features::Repo
  class RepoDelegatedClosuresTest < GitHub::TestCase
    include SecretScanning::Features::FeatureFlagHelper

    setup do
      @business = create(:business)
      @business.stubs(:advanced_security_purchased?).returns(true)
      @org = create(:business_plus_org, business: @business)
      @user = create(:user)
      @repo = create(:repository, owner: @org)
      @delegated_closures_repo = SecretScanning::Features::Repo::DelegatedClosures.new(@repo)

      @org.stubs(:advanced_security_purchased?).returns(true)
      SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(true)
      GitHub.stubs(:configuration_secret_scanning_enabled?).returns(true)
      GitHub.flipper[FeatureFlags::SHOW_CLOSURE_REQUESTS_ORG_SETTING].enable
    end

    context "initialize" do
      test "good input" do
        refute_nil @delegated_closures_repo
      end
    end

    context "feature_available?" do
      test "returns false if the repo does not have token scanning available" do
        SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(false)
        refute @delegated_closures_repo.feature_available?
      end

      test "returns false for repos in free orgs without GHAS purchased" do
        free_org = create(:organization)
        free_org.stubs(:advanced_security_purchased?).returns(false)
        free_repo = create(:repository, owner: free_org)
        refute SecretScanning::Features::Repo::DelegatedClosures.new(free_repo).feature_available?
      end

      test "returns false if the feature flag is disabled" do
        GitHub.flipper[FeatureFlags::SHOW_CLOSURE_REQUESTS_ORG_SETTING].disable
        refute @delegated_closures_repo.feature_available?
      end

      test "returns true if the repo's org has purchased GHAS" do
        assert @delegated_closures_repo.feature_available?
      end
    end

    context "enabled?" do
      test "returns false if feature isn't available" do
        @delegated_closures_repo.stubs(:feature_available?).returns(false)
        @delegated_closures_repo.enable(actor: @user)
        refute @delegated_closures_repo.enabled?
      end

      test "returns true if enabled for the org" do
        refute @delegated_closures_repo.enabled?
        SecretScanning::Features::Org::DelegatedClosures.any_instance.stubs(:enabled?).returns(true)
        assert @delegated_closures_repo.enabled?
      end

      test "returns repo feature enablement status" do
        @delegated_closures_repo.enable(actor: @user)
        assert @delegated_closures_repo.enabled?
        @delegated_closures_repo.disable(actor: @user)
        refute @delegated_closures_repo.enabled?
      end
    end
  end
end
