# typed: true
# frozen_string_literal: true

require "test_helper"

module SecretScanning::Features::Repo
  class ContentScanningTest < GitHub::TestCase
    include SecretScanning::Features::FeatureFlagHelper

    fixtures do
      @user = create(:user)
      @repo = create(:repository)
    end

    setup do
      @content_scanning = SecretScanning::Features::Repo::ContentScanning.new(@repo)
    end

    context "initialize" do
      test "good input" do
        refute SecretScanning::Features::Repo::ContentScanning.new(@repo).nil?
      end
    end

    context "feature_available?" do
      test "true if public repo and public scanning enabled", skip_enterprise: true do
        SecretScanning::Features::Repo::PublicScanning.any_instance.stubs(:enabled?).returns(true)
        Repository.any_instance..stubs(:public?).returns(true)
        assert @content_scanning.feature_available?
      end

      test "false if private repo and public scanning enabled" do
        SecretScanning::Features::Repo::PublicScanning.any_instance.stubs(:feature_available?).returns(false)
        Repository.any_instance.stubs(:public?).returns(false)
        refute @content_scanning.feature_available?
      end

      test "true if token scanning enabled", skip_enterprise: true do
        SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(true)
        Repository.any_instance.stubs(:public?).returns(false)
        assert @content_scanning.feature_available?
      end

      test "false if token scanning not enabled" do
        SecretScanning::Features::Repo::PublicScanning.any_instance.stubs(:enabled?).returns(false)
        SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(false)
        Repository.any_instance.stubs(:public?).returns(false)
        refute @content_scanning.feature_available?
      end
    end

    context "enabled?" do
      test "true if feature available" do
        SecretScanning::Features::Repo::ContentScanning.any_instance.stubs(:feature_available?).returns(true)
        assert @content_scanning.enabled?
      end

      test "false if feature not available" do
        SecretScanning::Features::Repo::ContentScanning.any_instance.stubs(:feature_available?).returns(false)
        refute @content_scanning.enabled?
      end

      test "true by default on enterprise", enterprise_only: true do
        SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(true)
        assert @content_scanning.enabled?
      end

      test "false if enterprise and explicitly enabled when repo is disabled", enterprise_only: true do
        GitHub.stubs(:secret_scanning_for_all_content_types_enabled?).returns(true)
        SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(false)
        refute @content_scanning.enabled?
      end

      test "false if enterprise and explicitly disabled when repo is enabled", enterprise_only: true do
        GitHub.stubs(:secret_scanning_for_all_content_types_enabled?).returns(false)
        SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(true)
        refute @content_scanning.enabled?
      end
    end
  end
end
