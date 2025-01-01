# typed: true
# frozen_string_literal: true

require "test_helper"

module SecretScanning::Features::Repo
  class RepoDelegatedBypassTest < GitHub::TestCase
    include SecretScanning::Features::FeatureFlagHelper

    setup do
      @business = create(:business)
      @business.stubs(:advanced_security_purchased?).returns(true)
      @org = create(:business_plus_org, business: @business)
      @user = create(:user)
      @repo = create(:private_repository, owner: @org)
      @push_protection_repo = SecretScanning::Features::Repo::PushProtection.new(@repo)
      @delegated_bypass_repo = SecretScanning::Features::Repo::DelegatedBypass.new(@repo)
      @token_scanning_repo = SecretScanning::Features::Repo::TokenScanning.new(@repo)
      @token_scanning_repo.enable(actor: @user)

      @org.stubs(:advanced_security_purchased?).returns(true)
      @repo.stubs(:advanced_security_enabled?).returns(true)
      GitHub.stubs(:configuration_secret_scanning_enabled?).returns(true)
    end

    context "initialize" do
      test "good input" do
        refute SecretScanning::Features::Repo::DelegatedBypass.new(@repo).nil?
      end
    end

    context "feature_available?", skip_enterprise: true do
      test "returns false if the owning organization has not purchased advanced security" do
        @org.stubs(:advanced_security_purchased?).returns(false)
        refute @delegated_bypass_repo.feature_available?
      end

      test "returns false if the owner has purchased advanced security but is not an organization" do
        @repo = create(:private_repository, owner: @user)
        @user.stubs(:advanced_security_purchased?).returns(true)
        refute SecretScanning::Features::Repo::DelegatedBypass.new(@repo).feature_available?
      end

      test "returns false if push protection is not enabled" do
        @push_protection_repo.disable(actor: @user)
        refute @delegated_bypass_repo.feature_available?
      end

      test "returns true if feature flag is enabled" do
        @push_protection_repo.enable(actor: @user)
        assert @delegated_bypass_repo.feature_available?
      end
    end

    context "enabled?", skip_enterprise: true do
      test "returns true if enabled by the repo, and false when disabled" do
        @push_protection_repo.enable(actor: @user)
        @delegated_bypass_repo.enable(actor: @user)
        assert @delegated_bypass_repo.enabled?
        @delegated_bypass_repo.disable(actor: @user)
        refute @delegated_bypass_repo.enabled?
      end

      test "returns true if enabled by the org" do
        @push_protection_repo.enable(actor: @user)
        SecretScanning::Features::Org::DelegatedBypass.new(@org).enable(actor: @user)
        assert @delegated_bypass_repo.enabled?
      end
    end

    context "can_view_requests_list?" do
      test "false if no actor" do
        refute @delegated_bypass_repo.can_view_requests_list?(nil)
      end

      test "false if feature not enabled" do
        @delegated_bypass_repo.disable(actor: @user)
        refute @delegated_bypass_repo.can_view_requests_list?(@user)
      end

      test "false if not allowed" do
        @push_protection_repo.enable(actor: @user)
        @delegated_bypass_repo.enable(actor: @user)
        Repository.any_instance.stubs(:can_view_delegated_bypass_requests_list?).returns(false)
        refute @delegated_bypass_repo.can_view_requests_list?(@user)
      end

      test "true if allowed" do
        @push_protection_repo.enable(actor: @user)
        @delegated_bypass_repo.enable(actor: @user)
        Repository.any_instance.stubs(:can_view_delegated_bypass_requests_list?).returns(true)
        assert @delegated_bypass_repo.can_view_requests_list?(@user)
      end
    end
  end
end
