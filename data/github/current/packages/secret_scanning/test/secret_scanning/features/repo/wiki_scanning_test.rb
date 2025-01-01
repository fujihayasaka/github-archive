# typed: true
# frozen_string_literal: true

require "test_helper"

module SecretScanning::Features::Repo
  class WikiScanningTest < GitHub::TestCase
    fixtures do
      @user = create(:user)
      @repo = create(:repository)
      @repo.initialize_wiki(@repo.owner)

      # has_wiki enables the wiki feature on the repo but does not create the wiki in spokes
      @repo_without_wiki_in_spokes = create(:repository, has_wiki: true)
    end

    setup do
      @wiki_scanning = SecretScanning::Features::Repo::WikiScanning.new(@repo)
      @wiki_does_not_exist = SecretScanning::Features::Repo::WikiScanning.new(@repo_without_wiki_in_spokes)
    end

    context "initialize" do
      test "good input" do
        refute SecretScanning::Features::Repo::WikiScanning.new(@repo).nil?
      end
    end

    # remove skip_enterprise when cleaning up feature flag
    context "feature_available?", skip_enterprise: true do
      test "true if public scanning enabled" do
        SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(false)
        SecretScanning::Features::Repo::PublicScanning.any_instance.stubs(:enabled?).returns(true)
        assert @wiki_scanning.feature_available?
      end

      test "true if token scanning enabled" do
        SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(true)
        SecretScanning::Features::Repo::PublicScanning.any_instance.stubs(:enabled?).returns(false)
        assert @wiki_scanning.feature_available?
      end

      test "false if neither token scanning or public scanning is enabled" do
        SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(false)
        SecretScanning::Features::Repo::PublicScanning.any_instance.stubs(:enabled?).returns(false)
        refute @wiki_scanning.feature_available?
      end

      test "false if wiki does not exist for this repo" do
        SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(true)
        SecretScanning::Features::Repo::PublicScanning.any_instance.stubs(:enabled?).returns(true)
        refute @wiki_does_not_exist.feature_available?
      end

      test "true if wiki exists but not wikis are not currently enabled" do
        repo_with_disabled_wiki = create(:repository, has_wiki: false)
        repo_with_disabled_wiki.initialize_wiki(repo_with_disabled_wiki.owner)

        SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(true)
        SecretScanning::Features::Repo::PublicScanning.any_instance.stubs(:enabled?).returns(true)
        assert SecretScanning::Features::Repo::WikiScanning.new(repo_with_disabled_wiki).feature_available?
      end
    end

    context "enabled?" do
      test "true if feature is available and incremental and backfill are enabled" do
        SecretScanning::Features::Repo::WikiScanning.any_instance.stubs(:incremental_enabled?).returns(true)
        SecretScanning::Features::Repo::WikiScanning.any_instance.stubs(:backfill_enabled?).returns(true)
        SecretScanning::Features::Repo::WikiScanning.any_instance.stubs(:feature_available?).returns(true)
        assert @wiki_scanning.enabled?
      end

      test "false if feature is not available" do
        SecretScanning::Features::Repo::WikiScanning.any_instance.stubs(:incremental_enabled?).returns(true)
        SecretScanning::Features::Repo::WikiScanning.any_instance.stubs(:backfill_enabled?).returns(true)
        SecretScanning::Features::Repo::WikiScanning.any_instance.stubs(:feature_available?).returns(false)
        refute @wiki_scanning.enabled?
      end

      test "false if feature is incremental scanning is not enabled" do
        SecretScanning::Features::Repo::WikiScanning.any_instance.stubs(:incremental_enabled?).returns(false)
        SecretScanning::Features::Repo::WikiScanning.any_instance.stubs(:backfill_enabled?).returns(true)
        SecretScanning::Features::Repo::WikiScanning.any_instance.stubs(:feature_available?).returns(true)
        refute @wiki_scanning.enabled?
      end

      test "false if feature is backfill scanning is not enabled" do
        SecretScanning::Features::Repo::WikiScanning.any_instance.stubs(:incremental_enabled?).returns(true)
        SecretScanning::Features::Repo::WikiScanning.any_instance.stubs(:backfill_enabled?).returns(false)
        SecretScanning::Features::Repo::WikiScanning.any_instance.stubs(:feature_available?).returns(true)
        refute @wiki_scanning.enabled?
      end
    end

    context "incremental_enabled?", skip_enterprise: true do
      test "true if feature flag is on" do
        SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(true)
        SecretScanning::Features::Repo::PublicScanning.any_instance.stubs(:enabled?).returns(true)
        enable_feature_flag(SecretScanning::Features::FeatureFlagHelper::FeatureFlags::WIKI_INCREMENTAL_SCANS, @repo)
        assert @wiki_scanning.incremental_enabled?
      end

      test "false if feature flag is off" do
        SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(true)
        SecretScanning::Features::Repo::PublicScanning.any_instance.stubs(:enabled?).returns(true)
        disable_feature_flag(SecretScanning::Features::FeatureFlagHelper::FeatureFlags::WIKI_INCREMENTAL_SCANS, @repo)
        refute @wiki_scanning.incremental_enabled?
      end

      test "false if wiki does not exist even if feature flag is enabled" do
        SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(true)
        SecretScanning::Features::Repo::PublicScanning.any_instance.stubs(:enabled?).returns(true)
        enable_feature_flag(SecretScanning::Features::FeatureFlagHelper::FeatureFlags::WIKI_INCREMENTAL_SCANS, @repo)
        refute @wiki_does_not_exist.feature_available?
      end
    end

    context "backfill_enabled?", skip_enterprise: true do
      test "true if feature flag is on" do
        SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(true)
        SecretScanning::Features::Repo::PublicScanning.any_instance.stubs(:enabled?).returns(true)
        enable_feature_flag(SecretScanning::Features::FeatureFlagHelper::FeatureFlags::WIKI_BACKFILL_SCANS, @repo)

        assert @wiki_scanning.backfill_enabled?
      end

      test "false if feature flag is off" do
        SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(true)
        SecretScanning::Features::Repo::PublicScanning.any_instance.stubs(:enabled?).returns(true)
        disable_feature_flag(SecretScanning::Features::FeatureFlagHelper::FeatureFlags::WIKI_BACKFILL_SCANS, @repo)

        refute @wiki_scanning.backfill_enabled?
      end

      test "false if wiki does not exist even if feature flag is enabled" do
        SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(true)
        SecretScanning::Features::Repo::PublicScanning.any_instance.stubs(:enabled?).returns(true)
        enable_feature_flag(SecretScanning::Features::FeatureFlagHelper::FeatureFlags::WIKI_BACKFILL_SCANS, @repo)
        refute @wiki_does_not_exist.feature_available?
      end
    end

    context "backfill_on_push_enabled?", skip_enterprise: true do
      test "true if feature flag is on" do
        SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(true)
        SecretScanning::Features::Repo::PublicScanning.any_instance.stubs(:enabled?).returns(true)
        enable_feature_flag(SecretScanning::Features::FeatureFlagHelper::FeatureFlags::WIKI_BACKFILL_ON_PUSH, @repo)
        assert @wiki_scanning.backfill_on_push_enabled?
      end

      test "false if feature flag is off" do
        SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(true)
        SecretScanning::Features::Repo::PublicScanning.any_instance.stubs(:enabled?).returns(true)
        disable_feature_flag(SecretScanning::Features::FeatureFlagHelper::FeatureFlags::WIKI_BACKFILL_ON_PUSH, @repo)
        refute @wiki_scanning.backfill_on_push_enabled?
      end

      test "false if wiki does not exist even if feature flag is enabled" do
        SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(true)
        SecretScanning::Features::Repo::PublicScanning.any_instance.stubs(:enabled?).returns(true)
        enable_feature_flag(SecretScanning::Features::FeatureFlagHelper::FeatureFlags::WIKI_BACKFILL_ON_PUSH, @repo)
        refute @wiki_does_not_exist.backfill_on_push_enabled?
      end
    end

    context "incremental_wiki_scans_queue_enabled?", skip_enterprise: true do
      test "true if feature flag is on" do
        SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(true)
        SecretScanning::Features::Repo::PublicScanning.any_instance.stubs(:enabled?).returns(true)
        enable_feature_flag(SecretScanning::Features::FeatureFlagHelper::FeatureFlags::WIKI_INCREMENTAL_SCANS_QUEUE, @repo)
        assert @wiki_scanning.incremental_wiki_scans_queue_enabled?
      end

      test "false if feature flag is off" do
        SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(true)
        SecretScanning::Features::Repo::PublicScanning.any_instance.stubs(:enabled?).returns(true)
        disable_feature_flag(SecretScanning::Features::FeatureFlagHelper::FeatureFlags::WIKI_INCREMENTAL_SCANS_QUEUE, @repo)
        refute @wiki_scanning.incremental_wiki_scans_queue_enabled?
      end

      test "false if wiki does not exist even if feature flag is enabled" do
        SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(true)
        SecretScanning::Features::Repo::PublicScanning.any_instance.stubs(:enabled?).returns(true)
        enable_feature_flag(SecretScanning::Features::FeatureFlagHelper::FeatureFlags::WIKI_INCREMENTAL_SCANS_QUEUE, @repo)
        refute @wiki_does_not_exist.incremental_wiki_scans_queue_enabled?
      end
    end

  end


end
