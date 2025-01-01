# typed: true
# frozen_string_literal: true

require "test_helper"

module SecretScanning::Features::Repo
  class CommitMetadataScanningTest < GitHub::TestCase
    include SecretScanning::Features::FeatureFlagHelper

    fixtures do
      @user = create(:user)
      @repo = create(:repository)
    end

    setup do
      @commit_comment_scanning = SecretScanning::Features::Repo::CommitMetadataScanning.new(@repo)
    end

    context "initialize" do
      test "good input" do
        refute SecretScanning::Features::Repo::CommitMetadataScanning.new(@repo).nil?
      end
    end

    context "feature_available?" do
      test "true if public scanning enabled" do
        SecretScanning::Features::Repo::PublicScanning.any_instance.stubs(:enabled?).returns(true)
        assert @commit_comment_scanning.feature_available?
      end

      test "false if public scanning not enabled", skip_enterprise: true do
        SecretScanning::Features::Repo::PublicScanning.any_instance.stubs(:enabled?).returns(false)
        refute @commit_comment_scanning.feature_available?
      end
    end

    context "enabled?" do
      test "true if feature available" do
        SecretScanning::Features::Repo::PublicScanning.any_instance.stubs(:enabled?).returns(true)
        assert @commit_comment_scanning.enabled?
      end

      test "false if feature not available" do
        SecretScanning::Features::Repo::PublicScanning.any_instance.stubs(:enabled?).returns(false)
        refute @commit_comment_scanning.enabled?
      end
    end
  end
end
