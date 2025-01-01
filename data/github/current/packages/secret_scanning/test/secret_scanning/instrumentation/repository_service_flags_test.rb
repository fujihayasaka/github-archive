# typed: true
# frozen_string_literal: true

require "test_helper"
module SecretScanning::Instrumentation
  class RepositoryServiceFlagsTest < GitHub::TestCase
    include SecretScanning::Features::FeatureFlagHelper

    fixtures do
      @org = create(:organization, login: "org")
      @public_repo = create(:repository, owner: @org)
      @private_repo = create(:private_repository, owner: @org)
      @github = create(:organization, login: "github")
      @github_repo = create(:repository, name: "repo", owner: @github)
      @actor = create(:user)
    end

    setup do
      SecretScanning::Features::Repo::ContentScanning.any_instance.stubs(:enabled?).returns(true)
      SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:historical_backfill_scan_enabled?).returns(true)
      SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(true)
      SecretScanning::Features::Repo::PublicScanning.any_instance.stubs(:enabled?).returns(true)
      SecretScanning::Features::Repo::PublicScanning.any_instance.stubs(:persist_results?).returns(true)
      SecretScanning::Features::Repo::CommitMetadataScanning.any_instance.stubs(:enabled?).returns(true)
      SecretScanning::Features::Repo::GenericSecrets.any_instance.stubs(:enabled?).returns(true)
    end

    context "initialize" do
      test "good input" do
        refute SecretScanning::Instrumentation::RepositoryServiceFlags.new(@public_repo).nil?
      end
    end

    context "issue_scanning_service_flags" do
      context "for public repos" do
        test "empty if issue scanning is disabled" do
          SecretScanning::Features::Repo::ContentScanning.any_instance.stubs(:enabled?).returns(false)

          assert_equal [], SecretScanning::Instrumentation::RepositoryServiceFlags.new(@public_repo).issue_scanning_service_flags
        end

        test "all flags" do
          SecretScanning::Features::Repo::ContentScanning.any_instance.stubs(:enabled?).returns(true)
          SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(true)
          SecretScanning::Features::Repo::LowerConfidencePatterns.any_instance.stubs(:enabled?).returns(true)
          @public_repo.owner.stubs(:advanced_security_purchased?).returns(true)
          GitHub.flipper[FeatureFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP].enable(@public_repo)

          expected_flags = ["login_revocation_for_credential_in_url_enabled",
                          "token_scanning_service_scan_ghas_public_repos",
                          ServiceFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP]

          assert_equal expected_flags, SecretScanning::Instrumentation::RepositoryServiceFlags.new(@public_repo).issue_scanning_service_flags
        end

        test "does not include flag for ghas public repo scanning if disabled" do
          SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(false)
          refute_includes SecretScanning::Instrumentation::RepositoryServiceFlags.new(@public_repo).issue_scanning_service_flags, "token_scanning_service_scan_ghas_public_repos"
        end

        test "does not include flag for ghas public repo scanning if ghas experience disabled for issues" do
          SecretScanning::Features::Repo::ContentScanning.any_instance.stubs(:enabled?).returns(false)
          SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(true)

          refute_includes SecretScanning::Instrumentation::RepositoryServiceFlags.new(@public_repo).issue_scanning_service_flags, "token_scanning_service_scan_ghas_public_repos"
        end

        test "includes flag for ghas public repo scanning if issue scanning and token scanning enabled" do
          SecretScanning::Features::Repo::ContentScanning.any_instance.stubs(:enabled?).returns(true)
          SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(true)

          assert_includes SecretScanning::Instrumentation::RepositoryServiceFlags.new(@public_repo).issue_scanning_service_flags, "token_scanning_service_scan_ghas_public_repos"
        end

        test "includes flag for low-confidence patterns if dark-ship feature flag is enabled" do
          GitHub.flipper[FeatureFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP].enable(@public_repo)
          assert_includes SecretScanning::Instrumentation::RepositoryServiceFlags.new(@public_repo).issue_scanning_service_flags, ServiceFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP
        end

        test "does not include flag for low-confidence patterns if dark-ship feature flag is disabled" do
          GitHub.flipper[FeatureFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP].disable(@public_repo)
          refute_includes SecretScanning::Instrumentation::RepositoryServiceFlags.new(@public_repo).issue_scanning_service_flags, ServiceFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP
        end
      end

      context "for non-public repos" do
        test "empty if issue scanning is disabled" do
          SecretScanning::Features::Repo::ContentScanning.any_instance.stubs(:enabled?).returns(false)

          assert_equal [], SecretScanning::Instrumentation::RepositoryServiceFlags.new(@private_repo).issue_scanning_service_flags
        end

        test "all flags" do
          SecretScanning::Features::Repo::ContentScanning.any_instance.stubs(:enabled?).returns(true)
          SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(true)
          SecretScanning::Features::Repo::LowerConfidencePatterns.any_instance.stubs(:enabled?).returns(true)
          GitHub.flipper[FeatureFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP].enable(@private_repo)
          expected_flags = ["login_revocation_for_credential_in_url_enabled",
                           ServiceFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP]

          assert_equal expected_flags, SecretScanning::Instrumentation::RepositoryServiceFlags.new(@private_repo).issue_scanning_service_flags
        end

        test "does not include flag for ghas public repo scanning if disabled" do
          SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(false)
          refute_includes SecretScanning::Instrumentation::RepositoryServiceFlags.new(@private_repo).issue_scanning_service_flags, "token_scanning_service_scan_ghas_public_repos"
        end

        test "includes flag for low-confidence patterns if dark-ship feature flag is enabled" do
          GitHub.flipper[FeatureFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP].enable(@private_repo)
          assert_includes SecretScanning::Instrumentation::RepositoryServiceFlags.new(@private_repo).issue_scanning_service_flags, ServiceFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP
        end

        test "does not include flag for low-confidence patterns if dark-ship feature flag is disabled" do
          GitHub.flipper[FeatureFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP].disable(@private_repo)
          refute_includes SecretScanning::Instrumentation::RepositoryServiceFlags.new(@private_repo).issue_scanning_service_flags, ServiceFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP
        end
      end
    end

    context "discussion_scanning_service_flags" do
      test "empty if discussion scanning is disabled" do
        SecretScanning::Features::Repo::ContentScanning.any_instance.stubs(:enabled?).returns(false)

        assert_equal [], SecretScanning::Instrumentation::RepositoryServiceFlags.new(@public_repo).discussion_scanning_service_flags
      end

      test "all flags" do
        SecretScanning::Features::Repo::ContentScanning.any_instance.stubs(:enabled?).returns(true)
        SecretScanning::Features::Repo::LowerConfidencePatterns.any_instance.stubs(:enabled?).returns(true)
        GitHub.flipper[FeatureFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP].enable(@public_repo)
        expected_flags = ["login_revocation_for_credential_in_url_enabled",
                          ServiceFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP]

        assert_equal expected_flags, SecretScanning::Instrumentation::RepositoryServiceFlags.new(@public_repo).discussion_scanning_service_flags
      end

      test "includes flag for low-confidence patterns if dark-ship feature flag is enabled" do
        GitHub.flipper[FeatureFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP].enable(@public_repo)
        assert_includes SecretScanning::Instrumentation::RepositoryServiceFlags.new(@public_repo).discussion_scanning_service_flags, ServiceFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP
      end

      test "does not include flag for low-confidence patterns if dark-ship feature flag is disabled" do
        GitHub.flipper[FeatureFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP].disable(@public_repo)
        refute_includes SecretScanning::Instrumentation::RepositoryServiceFlags.new(@public_repo).discussion_scanning_service_flags, ServiceFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP
      end
    end

    context "visibility_change_service_flags" do
      test "includes ingest feature flag when token scanning is enabled or public scanning is enabled" do
        GitHub.flipper[FeatureFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP].disable
        expected_flags = []
        service_flag_builder = SecretScanning::Instrumentation::RepositoryServiceFlags.new(@public_repo)
        token_scanning = service_flag_builder.instance_variable_get(:@token_scanning)
        public_scanning = service_flag_builder.instance_variable_get(:@public_scanning)
        token_scanning.stubs(:enabled?).returns(false)
        public_scanning.stubs(:enabled?).returns(false)

        visibility_change_service_flags = service_flag_builder.visibility_change_service_flags

        assert_equal expected_flags, visibility_change_service_flags
      end

      test "includes ingest feature flag when token scanning or public scanning is enabled" do
        GitHub.flipper[FeatureFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP].disable
        expected_flags = ["token_scanning_service_ingest"]
        service_flag_builder = SecretScanning::Instrumentation::RepositoryServiceFlags.new(@public_repo)
        token_scanning = service_flag_builder.instance_variable_get(:@token_scanning)
        public_scanning = service_flag_builder.instance_variable_get(:@public_scanning)
        token_scanning.stubs(:enabled?).returns(true)
        public_scanning.stubs(:enabled?).returns(false)

        visibility_change_service_flags = service_flag_builder.visibility_change_service_flags

        assert_equal expected_flags, visibility_change_service_flags
      end

      test "includes flag for low-confidence patterns if dark-ship feature flag is enabled" do
        GitHub.flipper[FeatureFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP].enable(@public_repo)
        assert_includes SecretScanning::Instrumentation::RepositoryServiceFlags.new(@public_repo).visibility_change_service_flags, ServiceFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP
      end

      test "does not include flag for low-confidence patterns if dark-ship feature flag is disabled" do
        GitHub.flipper[FeatureFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP].disable(@public_repo)
        refute_includes SecretScanning::Instrumentation::RepositoryServiceFlags.new(@public_repo).visibility_change_service_flags, ServiceFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP
      end
    end

    context "post_receive_service_flags" do
      test "all flags" do
        expected_flags = [
          "token_scanning_service_ingest",
          "token_scanning_service_scan_ghas_public_repos",
          "login_revocation_for_credential_in_url_enabled",
          "alerts_for_resolved_bypass",
          "token_scanning_service_commit_metadata_scan_enabled",
          "login_revocation_for_credential_in_commit_metadata_enabled",
          "secret_scanning_historical_backfill_scan",
          "secret_scanning_content_backfill_scan",
          "secret_scanning_generic_secrets_scan",
          "secret_scanning_write_results_for_public_scans",
          ServiceFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP,
          ServiceFlags::WIKI_INCREMENTAL_SCANS,
          ServiceFlags::WIKI_BACKFILL_SCANS
        ]

        GitHub.flipper[FeatureFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP].enable(@public_repo)
        SecretScanning::Features::Repo::LowerConfidencePatterns.any_instance.stubs(:enabled?).returns(true)
        SecretScanning::Features::Repo::WikiScanning.any_instance.stubs(:incremental_enabled?).returns(true)
        SecretScanning::Features::Repo::WikiScanning.any_instance.stubs(:backfill_enabled?).returns(true)

        post_receive_flags = SecretScanning::Instrumentation::RepositoryServiceFlags.new(@public_repo).post_receive_service_flags
        assert_equal expected_flags, post_receive_flags
      end

      test "ingest flag included for free public repo" do
        SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(false)
        SecretScanning::Features::Repo::PublicScanning.any_instance.stubs(:enabled?).returns(true)

        post_receive_flags = SecretScanning::Instrumentation::RepositoryServiceFlags.new(@public_repo).post_receive_service_flags
        assert_includes post_receive_flags, "token_scanning_service_ingest"
      end

      test "does not include GHAS public repo flag for private repo" do
        post_receive_flags = SecretScanning::Instrumentation::RepositoryServiceFlags.new(@private_repo).post_receive_service_flags
        refute_includes post_receive_flags, "token_scanning_service_scan_ghas_public_repos"
      end

      test "includes flag for gh or msft association" do
        post_receive_flags = SecretScanning::Instrumentation::RepositoryServiceFlags.new(@github_repo).post_receive_service_flags
        assert_includes post_receive_flags, "repo_is_associated_with_github_or_microsoft"
      end

      test "does not include historical backfill scan flag if disabled" do
        SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:historical_backfill_scan_enabled?).returns(false)

        post_receive_flags = SecretScanning::Instrumentation::RepositoryServiceFlags.new(@public_repo).post_receive_service_flags
        refute_includes post_receive_flags, "secret_scanning_historical_backfill_scan"
      end

      test "generic secrets scan flag not included if feature flag disabled" do
        SecretScanning::Features::Repo::GenericSecrets.any_instance.stubs(:enabled?).returns(false)

        post_receive_flags = SecretScanning::Instrumentation::RepositoryServiceFlags.new(@private_repo).post_receive_service_flags
        refute_includes post_receive_flags, "secret_scanning_generic_secrets_scan"
      end

      test "includes flag for low-confidence patterns if dark-ship feature flag is enabled" do
        GitHub.flipper[FeatureFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP].enable(@private_repo)
        assert_includes SecretScanning::Instrumentation::RepositoryServiceFlags.new(@private_repo).post_receive_service_flags, ServiceFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP
      end

      test "does not include flag for low-confidence patterns if dark-ship feature flag is disabled" do
        GitHub.flipper[FeatureFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP].disable(@private_repo)
        refute_includes SecretScanning::Instrumentation::RepositoryServiceFlags.new(@private_repo).post_receive_service_flags, ServiceFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP
      end

      test "includes flag for wiki incremental scans if feature flag is enabled" do
        SecretScanning::Features::Repo::WikiScanning.any_instance.stubs(:incremental_enabled?).returns(true)
        assert_includes SecretScanning::Instrumentation::RepositoryServiceFlags.new(@public_repo).post_receive_service_flags, ServiceFlags::WIKI_INCREMENTAL_SCANS
      end

      test "does not include flag for wiki incremental scans if feature flag is disabled" do
        SecretScanning::Features::Repo::WikiScanning.any_instance.stubs(:incremental_enabled?).returns(false)
        refute_includes SecretScanning::Instrumentation::RepositoryServiceFlags.new(@public_repo).post_receive_service_flags, ServiceFlags::WIKI_INCREMENTAL_SCANS
      end

      test "includes flag for wiki backfill scans if feature flag is enabled" do
        SecretScanning::Features::Repo::WikiScanning.any_instance.stubs(:backfill_enabled?).returns(true)
        assert_includes SecretScanning::Instrumentation::RepositoryServiceFlags.new(@public_repo).post_receive_service_flags, ServiceFlags::WIKI_BACKFILL_SCANS
      end

      test "does not include flag for wiki backfill scans if feature flag is disabled" do
        SecretScanning::Features::Repo::WikiScanning.any_instance.stubs(:backfill_enabled?).returns(false)
        refute_includes SecretScanning::Instrumentation::RepositoryServiceFlags.new(@public_repo).post_receive_service_flags, ServiceFlags::WIKI_BACKFILL_SCANS
      end
    end

    context "commit_comment_scanning_service_flags" do
      test "includes flag for low-confidence patterns if dark-ship feature flag is enabled" do
        GitHub.flipper[FeatureFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP].enable(@public_repo)
        assert_includes SecretScanning::Instrumentation::RepositoryServiceFlags.new(@public_repo).commit_comment_scanning_service_flags, ServiceFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP
      end

      test "does not include flag for low-confidence patterns if dark-ship feature flag is disabled" do
        GitHub.flipper[FeatureFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP].disable(@public_repo)
        refute_includes SecretScanning::Instrumentation::RepositoryServiceFlags.new(@public_repo).commit_comment_scanning_service_flags, ServiceFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP
      end
    end

    context "pull_request_scanning_service_flags" do
      test "includes flag for low-confidence patterns if dark-ship feature flag is enabled" do
        GitHub.flipper[FeatureFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP].enable(@public_repo)
        assert_includes SecretScanning::Instrumentation::RepositoryServiceFlags.new(@public_repo).pull_request_scanning_service_flags, ServiceFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP
      end

      test "does not include flag for low-confidence patterns if dark-ship feature flag is disabled" do
        GitHub.flipper[FeatureFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP].disable(@public_repo)
        refute_includes SecretScanning::Instrumentation::RepositoryServiceFlags.new(@public_repo).pull_request_scanning_service_flags, ServiceFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP
      end
    end

    context "scans_api_service_flags" do
      test "includes flag for low-confidence patterns if dark-ship feature flag is enabled" do
        GitHub.flipper[FeatureFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP].enable(@private_repo)
        assert_includes SecretScanning::Instrumentation::RepositoryServiceFlags.new(@private_repo).scans_api_service_flags, ServiceFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP
      end

      test "does not include flag for low-confidence patterns if dark-ship feature flag is disabled" do
        GitHub.flipper[FeatureFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP].disable(@private_repo)
        refute_includes SecretScanning::Instrumentation::RepositoryServiceFlags.new(@private_repo).scans_api_service_flags, ServiceFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP
      end
    end

    context "repo_update_flags" do
      test "includes public flag when public and feature available" do
        SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:feature_available?).returns(true)

        update_flags = SecretScanning::Instrumentation::RepositoryServiceFlags.new(@public_repo).repo_update_flags
        assert_includes update_flags, "token_scanning_service_scan_ghas_public_repos"
      end

      test "does not include public flag when feature is not available" do
        SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:feature_available?).returns(false)

        update_flags = SecretScanning::Instrumentation::RepositoryServiceFlags.new(@public_repo).repo_update_flags
        refute_includes update_flags, "token_scanning_service_scan_ghas_public_repos"
      end

      test "does not include public flags for a private repo" do
        SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:feature_available?).returns(true)

        update_flags = SecretScanning::Instrumentation::RepositoryServiceFlags.new(@private_repo).repo_update_flags
        refute_includes update_flags, "token_scanning_service_scan_ghas_public_repos"
      end

      test "includes flag for low-confidence patterns if dark-ship feature flag is enabled" do
        GitHub.flipper[FeatureFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP].enable(@private_repo)
        assert_includes SecretScanning::Instrumentation::RepositoryServiceFlags.new(@private_repo).repo_update_flags, ServiceFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP
      end

      test "does not include flag for low-confidence patterns if dark-ship feature flag is disabled" do
        GitHub.flipper[FeatureFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP].disable(@private_repo)
        refute_includes SecretScanning::Instrumentation::RepositoryServiceFlags.new(@private_repo).repo_update_flags, ServiceFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP
      end
    end
  end
end
