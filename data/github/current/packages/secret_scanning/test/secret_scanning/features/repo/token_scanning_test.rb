# typed: true
# frozen_string_literal: true

require "test_helper"

module SecretScanning::Features::Repo
  class RepoTokenScanningTest < GitHub::TestCase
    include SecretScanning::Features::FeatureFlagHelper
    include RepoFeatureAvailabilityTest

    fixtures do
      @with_ghas = create_fixtures(opts: {
        mark_ghas_as_purchased: true,
        enable_ghas: true,
      })
      @without_ghas = create_fixtures(opts: { mark_ghas_as_purchased: false })
    end

    setup do
      GitHub.stubs(:configuration_secret_scanning_enabled?).returns(true)
      GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(true)
      GitHub.flipper[FeatureFlags::READ_PUBLIC_REPO_ALERTS].enable
    end

    context "feature_available?" do
      context "on GHEC", skip_enterprise: true do
        test "when ghas has been purchased" do
          check_fn = ->(repo) { SecretScanning::Features::Repo::TokenScanning.new(repo).feature_available? }
          matrix = {
            user_public_repo: true,
            user_private_repo: false,
            user_archived_public_repo: true,
            user_archived_private_repo: false,

            emu_private_repo: true,
            emu_archived_repo: true,

            org_public_repo: true,
            org_private_repo: true,
            org_internal_repo: true,

            org_archived_public_repo: true,
            org_archived_private_repo: true,
            org_archived_internal_repo: true,
          }
          assert_availability_on_all_repos(check_fn:, test_fixtures: @with_ghas, matrix:)
        end

        test "everything is unavailable when feature is globally disabled" do
          GitHub.stubs(:configuration_secret_scanning_enabled?).returns(false)

          check_fn = ->(repo) { SecretScanning::Features::Repo::TokenScanning.new(repo).feature_available? }
          matrix = {
            user_public_repo: false,
            user_private_repo: false,
            user_archived_public_repo: false,
            user_archived_private_repo: false,

            emu_private_repo: false,
            emu_archived_repo: false,

            org_public_repo: false,
            org_private_repo: false,
            org_internal_repo: false,

            org_archived_public_repo: false,
            org_archived_private_repo: false,
            org_archived_internal_repo: false,
          }
          assert_availability_on_all_repos(check_fn:, test_fixtures: @with_ghas, matrix:)
        end

        test "feature availability when GHAS is not enabled" do
          check_fn = ->(repo) { SecretScanning::Features::Repo::TokenScanning.new(repo).feature_available? }
          matrix = {
            user_public_repo: true,
            user_private_repo: false,
            user_archived_public_repo: true,
            user_archived_private_repo: false,

            emu_private_repo: false,
            emu_archived_repo: false,

            org_public_repo: true,
            org_private_repo: false,
            org_internal_repo: false,

            org_archived_public_repo: true,
            org_archived_private_repo: false,
            org_archived_internal_repo: false,
          }
          assert_availability_on_all_repos(check_fn:, test_fixtures: @without_ghas, matrix:)
        end

        test "when feature flag is disabled and ghas has been purchased" do
          # Because advanced-security is purchased, we still have access to alerts
          GitHub.flipper[FeatureFlags::READ_PUBLIC_REPO_ALERTS].disable

          check_fn = ->(repo) { SecretScanning::Features::Repo::TokenScanning.new(repo).feature_available? }
          matrix = {
            user_public_repo: false,
            user_private_repo: false,
            user_archived_public_repo: false,
            user_archived_private_repo: false,

            emu_private_repo: true,
            emu_archived_repo: true,

            org_public_repo: true,
            org_private_repo: true,
            org_internal_repo: true,

            org_archived_public_repo: true,
            org_archived_private_repo: true,
            org_archived_internal_repo: true,
          }
          assert_availability_on_all_repos(check_fn:, test_fixtures: @with_ghas, matrix:)
        end
      end

      context "on GHES", enterprise_only: true do
        test "when ghas has been purchased" do
          check_fn = ->(repo) { SecretScanning::Features::Repo::TokenScanning.new(repo).feature_available? }
          matrix = {
            user_public_repo: true,
            user_private_repo: true,
            user_archived_public_repo: true,
            user_archived_private_repo: true,

            org_public_repo: true,
            org_private_repo: true,
            org_internal_repo: true,

            org_archived_public_repo: true,
            org_archived_private_repo: true,
            org_archived_internal_repo: true,
          }
          assert_availability_on_all_repos(check_fn:, test_fixtures: @with_ghas, matrix:)
        end

        test "everything is unavailable when feature is globally disabled" do
          GitHub.stubs(:configuration_secret_scanning_enabled?).returns(false)

          check_fn = ->(repo) { SecretScanning::Features::Repo::TokenScanning.new(repo).feature_available? }
          matrix = {
            user_public_repo: false,
            user_private_repo: false,
            user_archived_public_repo: false,
            user_archived_private_repo: false,

            org_public_repo: false,
            org_private_repo: false,
            org_internal_repo: false,

            org_archived_public_repo: false,
            org_archived_private_repo: false,
            org_archived_internal_repo: false,
          }
          assert_availability_on_all_repos(check_fn:, test_fixtures: @with_ghas, matrix:)
        end

        test "when advanced security is not purchased" do
          GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(false)

          check_fn = ->(repo) { SecretScanning::Features::Repo::TokenScanning.new(repo).feature_available? }
          matrix = {
            user_public_repo: true,
            user_private_repo: false,
            user_archived_public_repo: true,
            user_archived_private_repo: false,

            org_public_repo: true,
            org_private_repo: false,
            org_internal_repo: false,

            org_archived_public_repo: true,
            org_archived_private_repo: false,
            org_archived_internal_repo: false,
          }
          assert_availability_on_all_repos(check_fn:, test_fixtures: @without_ghas, matrix:)
        end
      end
    end

    context "stafftools_available?" do
      test "returns true if all conditions are met", skip_enterprise: true  do
        check_fn = ->(repo) { SecretScanning::Features::Repo::TokenScanning.new(repo).stafftools_available? }
        matrix = {
          user_public_repo: true,
          user_private_repo: false,
          user_archived_public_repo: true,
          user_archived_private_repo: false,

          emu_private_repo: true,
          emu_archived_repo: true,

          org_public_repo: true,
          org_private_repo: true,
          org_internal_repo: true,

          org_archived_public_repo: true,
          org_archived_private_repo: true,
          org_archived_internal_repo: true,
        }
        assert_availability_on_all_repos(check_fn:, test_fixtures: @with_ghas, matrix:)
      end

      test "false if global config disabled", skip_enterprise: true do
        GitHub.stubs(:configuration_secret_scanning_enabled?).returns(false)

        check_fn = ->(repo) { SecretScanning::Features::Repo::TokenScanning.new(repo).stafftools_available? }
        matrix = {
          user_public_repo: false,
          user_private_repo: false,
          user_archived_public_repo: false,
          user_archived_private_repo: false,

          emu_private_repo: false,
          emu_archived_repo: false,

          org_public_repo: false,
          org_private_repo: false,
          org_internal_repo: false,

          org_archived_public_repo: false,
          org_archived_private_repo: false,
          org_archived_internal_repo: false,
        }
        assert_availability_on_all_repos(check_fn:, test_fixtures: @with_ghas, matrix:)
      end

      test "false if GHAS not purchased", skip_enterprise: true do
        check_fn = ->(repo) { SecretScanning::Features::Repo::TokenScanning.new(repo).stafftools_available? }
        matrix = {
          user_public_repo: true,
          user_private_repo: false,
          user_archived_public_repo: true,
          user_archived_private_repo: false,

          emu_private_repo: false,
          emu_archived_repo: false,

          org_public_repo: true,
          org_private_repo: false,
          org_internal_repo: false,

          org_archived_public_repo: true,
          org_archived_private_repo: false,
          org_archived_internal_repo: false,
        }
        assert_availability_on_all_repos(check_fn:, test_fixtures: @without_ghas, matrix:)
      end

      test "whether the repo is staff locked does not change availability", skip_enterprise: true do
        @with_ghas.each do |_, repo|
          SecretScanning::Features::Repo::TokenScanning.new(repo).staff_disable(actor: repo.owner)
        end

        check_fn = ->(repo) { SecretScanning::Features::Repo::TokenScanning.new(repo).stafftools_available? }
        matrix = {
          user_public_repo: true,
          user_private_repo: false,
          user_archived_public_repo: true,
          user_archived_private_repo: false,

          emu_private_repo: true,
          emu_archived_repo: true,

          org_public_repo: true,
          org_private_repo: true,
          org_internal_repo: true,

          org_archived_public_repo: true,
          org_archived_private_repo: true,
          org_archived_internal_repo: true,
        }
        assert_availability_on_all_repos(check_fn:, test_fixtures: @with_ghas, matrix:)
      end

      test "false on GHES", enterprise_only: true do
        check_fn = ->(repo) { SecretScanning::Features::Repo::TokenScanning.new(repo).stafftools_available? }
        matrix = {
          user_public_repo: false,
          user_private_repo: false,
          user_archived_public_repo: false,
          user_archived_private_repo: false,

          org_public_repo: false,
          org_private_repo: false,
          org_internal_repo: false,

          org_archived_public_repo: false,
          org_archived_private_repo: false,
          org_archived_internal_repo: false,
        }
        assert_availability_on_all_repos(check_fn:, test_fixtures: @with_ghas, matrix:)
      end
    end

    context "enable / disable" do
      context "on GHEC", skip_enterprise: true do
        test "repo enablement" do
          @with_ghas.each do |_, repo|
            SecretScanning::Features::Repo::TokenScanning.new(repo).enable(actor: repo.owner)
          end

          check_fn = ->(repo) { SecretScanning::Features::Repo::TokenScanning.new(repo).enabled? }
          matrix = {
            user_public_repo: true,
            user_private_repo: false,
            user_archived_public_repo: true,
            user_archived_private_repo: false,

            emu_private_repo: true,
            emu_archived_repo: true,

            org_public_repo: true,
            org_private_repo: true,
            org_internal_repo: true,

            org_archived_public_repo: true,
            org_archived_private_repo: true,
            org_archived_internal_repo: true,
          }
          assert_availability_on_all_repos(check_fn:, test_fixtures: @with_ghas, matrix:)
        end

        test "repo disablement" do
          @with_ghas.each do |_, repo|
            SecretScanning::Features::Repo::TokenScanning.new(repo).enable(actor: repo.owner)
            SecretScanning::Features::Repo::TokenScanning.new(repo).disable(actor: repo.owner)
          end

          check_fn = ->(repo) { SecretScanning::Features::Repo::TokenScanning.new(repo).enabled? }
          matrix = {
            user_public_repo: false,
            user_private_repo: false,
            user_archived_public_repo: false,
            user_archived_private_repo: false,

            emu_private_repo: false,
            emu_archived_repo: false,

            org_public_repo: false,
            org_private_repo: false,
            org_internal_repo: false,

            org_archived_public_repo: false,
            org_archived_private_repo: false,
            org_archived_internal_repo: false,
          }
          assert_availability_on_all_repos(check_fn:, test_fixtures: @with_ghas, matrix:)
        end

        test "repo enablement without ghas" do
          @without_ghas.each do |_, repo|
            SecretScanning::Features::Repo::TokenScanning.new(repo).enable(actor: repo.owner)
          end

          check_fn = ->(repo) { SecretScanning::Features::Repo::TokenScanning.new(repo).enabled? }
          matrix = {
            user_public_repo: true,
            user_private_repo: false,
            user_archived_public_repo: true,
            user_archived_private_repo: false,

            emu_private_repo: false,
            emu_archived_repo: false,

            org_public_repo: true,
            org_private_repo: false,
            org_internal_repo: false,

            org_archived_public_repo: true,
            org_archived_private_repo: false,
            org_archived_internal_repo: false,
          }
          assert_availability_on_all_repos(check_fn:, test_fixtures: @without_ghas, matrix:)
        end

        test "repo enablement when the feature is disabled" do
          GitHub.stubs(:configuration_secret_scanning_enabled?).returns(false)

          @with_ghas.each do |_, repo|
            SecretScanning::Features::Repo::TokenScanning.new(repo).enable(actor: repo.owner)
          end

          check_fn = ->(repo) { SecretScanning::Features::Repo::TokenScanning.new(repo).enabled? }
          matrix = {
            user_public_repo: false,
            user_private_repo: false,
            user_archived_public_repo: false,
            user_archived_private_repo: false,

            emu_private_repo: false,
            emu_archived_repo: false,

            org_public_repo: false,
            org_private_repo: false,
            org_internal_repo: false,

            org_archived_public_repo: false,
            org_archived_private_repo: false,
            org_archived_internal_repo: false,
          }
          assert_availability_on_all_repos(check_fn:, test_fixtures: @with_ghas, matrix:)
        end

        test "repo enablement when staff disabled" do
          @with_ghas.each do |_, repo|
            SecretScanning::Features::Repo::TokenScanning.new(repo).enable(actor: repo.owner)
            SecretScanning::Features::Repo::TokenScanning.new(repo).staff_disable(actor: repo.owner)
          end

          check_fn = ->(repo) { SecretScanning::Features::Repo::TokenScanning.new(repo).enabled? }
          matrix = {
            user_public_repo: false,
            user_private_repo: false,
            user_archived_public_repo: false,
            user_archived_private_repo: false,

            emu_private_repo: false,
            emu_archived_repo: false,

            org_public_repo: false,
            org_private_repo: false,
            org_internal_repo: false,

            org_archived_public_repo: false,
            org_archived_private_repo: false,
            org_archived_internal_repo: false,
          }
          assert_availability_on_all_repos(check_fn:, test_fixtures: @with_ghas, matrix:)
        end

        test "repo enablement when staff network disabled" do
          @with_ghas.each do |_, repo|
            SecretScanning::Features::Repo::TokenScanning.new(repo).enable(actor: repo.owner)
            SecretScanning::Features::Repo::TokenScanning.new(repo).staff_network_disable(actor: repo.owner)
          end

          check_fn = ->(repo) { SecretScanning::Features::Repo::TokenScanning.new(repo).enabled? }
          matrix = {
            user_public_repo: false,
            user_private_repo: false,
            user_archived_public_repo: false,
            user_archived_private_repo: false,

            emu_private_repo: false,
            emu_archived_repo: false,

            org_public_repo: false,
            org_private_repo: false,
            org_internal_repo: false,

            org_archived_public_repo: false,
            org_archived_private_repo: false,
            org_archived_internal_repo: false,
          }
          assert_availability_on_all_repos(check_fn:, test_fixtures: @with_ghas, matrix:)
        end
      end

      context "on GHES", enterprise_only: true do
        test "repo enablement" do
          @with_ghas.each do |_, repo|
            SecretScanning::Features::Repo::TokenScanning.new(repo).enable(actor: repo.owner)
          end

          check_fn = ->(repo) { SecretScanning::Features::Repo::TokenScanning.new(repo).enabled? }
          matrix = {
            user_public_repo: true,
            user_private_repo: true,
            user_archived_public_repo: true,
            user_archived_private_repo: true,

            org_public_repo: true,
            org_private_repo: true,
            org_internal_repo: true,

            org_archived_public_repo: true,
            org_archived_private_repo: true,
            org_archived_internal_repo: true,
          }
          assert_availability_on_all_repos(check_fn:, test_fixtures: @with_ghas, matrix:)
        end

        test "repo disablement" do
          @with_ghas.each do |_, repo|
            SecretScanning::Features::Repo::TokenScanning.new(repo).enable(actor: repo.owner)
            SecretScanning::Features::Repo::TokenScanning.new(repo).disable(actor: repo.owner)
          end

          check_fn = ->(repo) { SecretScanning::Features::Repo::TokenScanning.new(repo).enabled? }
          matrix = {
            user_public_repo: false,
            user_private_repo: false,
            user_archived_public_repo: false,
            user_archived_private_repo: false,

            org_public_repo: false,
            org_private_repo: false,
            org_internal_repo: false,

            org_archived_public_repo: false,
            org_archived_private_repo: false,
            org_archived_internal_repo: false,
          }
          assert_availability_on_all_repos(check_fn:, test_fixtures: @with_ghas, matrix:)
        end

        test "repo enablement without ghas" do
          GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(false)
          @without_ghas.each do |_, repo|
            SecretScanning::Features::Repo::TokenScanning.new(repo).enable(actor: repo.owner)
          end

          check_fn = ->(repo) { SecretScanning::Features::Repo::TokenScanning.new(repo).enabled? }
          matrix = {
            user_public_repo: true,
            user_private_repo: false,
            user_archived_public_repo: true,
            user_archived_private_repo: false,

            org_public_repo: true,
            org_private_repo: false,
            org_internal_repo: false,

            org_archived_public_repo: true,
            org_archived_private_repo: false,
            org_archived_internal_repo: false,
          }
          assert_availability_on_all_repos(check_fn:, test_fixtures: @without_ghas, matrix:)
        end

        test "repo enablement when the feature is disabled" do
          GitHub.stubs(:configuration_secret_scanning_enabled?).returns(false)

          @with_ghas.each do |_, repo|
            SecretScanning::Features::Repo::TokenScanning.new(repo).enable(actor: repo.owner)
          end

          check_fn = ->(repo) { SecretScanning::Features::Repo::TokenScanning.new(repo).enabled? }
          matrix = {
            user_public_repo: false,
            user_private_repo: false,
            user_archived_public_repo: false,
            user_archived_private_repo: false,

            org_public_repo: false,
            org_private_repo: false,
            org_internal_repo: false,

            org_archived_public_repo: false,
            org_archived_private_repo: false,
            org_archived_internal_repo: false,
          }
          assert_availability_on_all_repos(check_fn:, test_fixtures: @with_ghas, matrix:)
        end
      end
    end

    context "staff_unlock", skip_enterprise: true do
      test "remove staff lock" do
        repo = @with_ghas[:org_private_repo]

        feature = SecretScanning::Features::Repo::TokenScanning.new(repo)

        feature.staff_disable(actor: repo.owner)
        feature.enable(actor: repo.owner)
        refute feature.enabled?

        feature.staff_unlock(actor: repo.owner)
        assert feature.enabled?
      end
    end

    context "staff_network_unlock", skip_enterprise: true do
      test "removes staff network lock" do
        repo = @with_ghas[:org_private_repo]

        feature = SecretScanning::Features::Repo::TokenScanning.new(repo)

        feature.staff_network_disable(actor: repo.owner)
        feature.enable(actor: repo.owner)
        refute feature.enabled?

        feature.staff_network_unlock(actor: repo.owner)
        assert feature.enabled?
      end
    end

    context "feedback_link_enabled" do
      test "true if feature flag enabled" do
        GitHub.flipper[FeatureFlags::FEEDBACK_LINK].enable

        repo = @with_ghas[:org_private_repo]
        feature = SecretScanning::Features::Repo::TokenScanning.new(repo)
        assert feature.feedback_link_enabled?
      end

      test "false if feature flag disabled" do
        GitHub.flipper[FeatureFlags::FEEDBACK_LINK].disable

        repo = @with_ghas[:org_private_repo]
        feature = SecretScanning::Features::Repo::TokenScanning.new(repo)
        refute feature.feedback_link_enabled?
      end
    end

    context "historical_backfill_scan_enabled?" do
      test "true if feature flag enabled", skip_enterprise: true do
        GitHub.flipper[FeatureFlags::HISTORICAL_BACKFILL_SCAN].enable
        repo = @with_ghas[:user_public_repo]
        feature = SecretScanning::Features::Repo::TokenScanning.new(repo)

        assert feature.historical_backfill_scan_enabled?
      end

      test "false if feature flag disabled", skip_enterprise: true do
        GitHub.flipper[FeatureFlags::HISTORICAL_BACKFILL_SCAN].disable
        repo = @with_ghas[:user_public_repo]
        feature = SecretScanning::Features::Repo::TokenScanning.new(repo)

        refute feature.historical_backfill_scan_enabled?
      end

      test "false if private repo", skip_enterprise: true do
        GitHub.flipper[FeatureFlags::HISTORICAL_BACKFILL_SCAN].disable
        repo = @with_ghas[:user_private_repo]
        feature = SecretScanning::Features::Repo::TokenScanning.new(repo)

        refute feature.historical_backfill_scan_enabled?
      end

      test "false if GHES", enterprise_only: true do
        GitHub.flipper[FeatureFlags::HISTORICAL_BACKFILL_SCAN].disable
        repo = @with_ghas[:user_public_repo]
        feature = SecretScanning::Features::Repo::TokenScanning.new(repo)

        refute feature.historical_backfill_scan_enabled?
      end

      test "false if GHAS repo", skip_enterprise: true do
        GitHub.flipper[FeatureFlags::HISTORICAL_BACKFILL_SCAN].disable
        repo = @with_ghas[:org_private_repo]
        feature = SecretScanning::Features::Repo::TokenScanning.new(repo)

        refute feature.historical_backfill_scan_enabled?
      end
    end

    context "view_alerts_allowed?" do
      test "false if no actor" do
        repo = @with_ghas[:org_private_repo]
        feature = SecretScanning::Features::Repo::TokenScanning.new(repo)
        refute feature.view_alerts_allowed?(nil)
      end

      test "false if feature not available" do
        GitHub.stubs(:configuration_secret_scanning_enabled?).returns(false)

        repo = @with_ghas[:org_private_repo]
        feature = SecretScanning::Features::Repo::TokenScanning.new(repo)
        refute feature.view_alerts_allowed?(repo.owner)
      end

      test "false if not allowed" do
        Repository.any_instance.stubs(:can_view_secret_scanning_alerts?).returns(false)

        repo = @with_ghas[:org_private_repo]
        feature = SecretScanning::Features::Repo::TokenScanning.new(repo)
        refute feature.view_alerts_allowed?(repo.owner)
      end

      test "true if allowed" do
        Repository.any_instance.stubs(:can_view_secret_scanning_alerts?).returns(true)

        repo = @with_ghas[:org_private_repo]
        feature = SecretScanning::Features::Repo::TokenScanning.new(repo)
        assert feature.view_alerts_allowed?(repo.owner)
      end

      context "resolve_alerts_allowed?" do
        test "false if no actor" do
          repo = @with_ghas[:org_private_repo]
          feature = SecretScanning::Features::Repo::TokenScanning.new(repo)
          refute feature.resolve_alerts_allowed?(nil, ["abcd1234"])
        end

        test "false if feature not available" do
          GitHub.stubs(:configuration_secret_scanning_enabled?).returns(false)

          repo = @with_ghas[:org_private_repo]
          feature = SecretScanning::Features::Repo::TokenScanning.new(repo)
          refute feature.resolve_alerts_allowed?(repo.owner, ["abcd1234"])
        end

        test "false if not allowed" do
          Repository.any_instance.stubs(:can_resolve_secret_scanning_alerts?).returns(false)

          repo = @with_ghas[:org_private_repo]
          feature = SecretScanning::Features::Repo::TokenScanning.new(repo)
          refute feature.resolve_alerts_allowed?(repo.owner, ["abcd1234"])
        end

        test "true if allowed" do
          Repository.any_instance.stubs(:can_resolve_secret_scanning_alerts?).returns(true)

          repo = @with_ghas[:org_private_repo]
          feature = SecretScanning::Features::Repo::TokenScanning.new(repo)
          assert feature.resolve_alerts_allowed?(repo.owner, ["abcd1234"])
        end
      end
    end

    context "show_page_serialize_location_refactor_enabled?" do
      test "true if feature flag enabled" do
        repo = @with_ghas[:org_private_repo]

        feature = SecretScanning::Features::Repo::TokenScanning.new(repo)
        feature.enable(actor: repo.owner)

        GitHub.flipper[FeatureFlags::SHOW_PAGE_SERIALIZE_LOCATION_REFACTOR].enable
        assert feature.show_page_serialize_location_refactor_enabled?
      end

      test "false if feature flag disabled" do
        repo = @with_ghas[:org_private_repo]

        feature = SecretScanning::Features::Repo::TokenScanning.new(repo)
        feature.enable(actor: repo.owner)

        GitHub.flipper[FeatureFlags::SHOW_PAGE_SERIALIZE_LOCATION_REFACTOR].disable
        refute feature.show_page_serialize_location_refactor_enabled?
      end
    end

    context "one_click_reporting_enabled?" do
      test "false on unsupported token type" do
        repo = @with_ghas[:org_private_repo]
        token_scanning_feature = SecretScanning::Features::Repo::TokenScanning.new(repo)
        token = GitHub::Proto::SecretScanning::Api::V2::Token.new(token_type: "AWS_KEYID")
        alert = GitHub::TokenScanning::Service::Token.new(token, repo)

        refute token_scanning_feature.one_click_reporting_enabled?(alert)
      end
      test "true on supported token type" do
        repo = @with_ghas[:org_private_repo]
        token_scanning_feature = SecretScanning::Features::Repo::TokenScanning.new(repo)
        token_scanning_feature.enable(actor: repo.owner)
        token = GitHub::Proto::SecretScanning::Api::V2::Token.new(token_type: "GITHUB_TOKEN_V2")
        alert = GitHub::TokenScanning::Service::Token.new(token, repo)

        available = token_scanning_feature.one_click_reporting_enabled?(alert)

        if GitHub.single_tenant_enterprise?
          refute available
        else
          assert available
        end
      end
      test "false on supported token type but token scanning not enabled" do
        repo = @with_ghas[:org_private_repo]
        token_scanning_feature = SecretScanning::Features::Repo::TokenScanning.new(repo)
        token_scanning_feature.disable(actor: repo.owner)
        token = GitHub::Proto::SecretScanning::Api::V2::Token.new(token_type: "GITHUB_TOKEN_V2")
        alert = GitHub::TokenScanning::Service::Token.new(token, repo)

        available = token_scanning_feature.one_click_reporting_enabled?(alert)

        refute available
      end
      test "false on a supported token type on a user public repo" do
        repo = @with_ghas[:user_public_repo]
        token_scanning_feature = SecretScanning::Features::Repo::TokenScanning.new(repo)
        token_scanning_feature.enable(actor: repo.owner)
        token = GitHub::Proto::SecretScanning::Api::V2::Token.new(token_type: "GITHUB_TOKEN_V2")
        alert = GitHub::TokenScanning::Service::Token.new(token, repo)

        available = token_scanning_feature.one_click_reporting_enabled?(alert)

        refute available
      end
      test "false on a supported token type on an org public repo" do
        repo = @with_ghas[:org_public_repo]
        token_scanning_feature = SecretScanning::Features::Repo::TokenScanning.new(repo)
        token_scanning_feature.enable(actor: repo.owner)
        token = GitHub::Proto::SecretScanning::Api::V2::Token.new(token_type: "GITHUB_TOKEN_V2")
        alert = GitHub::TokenScanning::Service::Token.new(token, repo)

        available = token_scanning_feature.one_click_reporting_enabled?(alert)

        refute available
      end
    end

    context "ai_assisted_remediation_guidance_enabled?" do
      test "false when ff disabled" do
        repo = @with_ghas[:org_private_repo]
        token_scanning_feature = SecretScanning::Features::Repo::TokenScanning.new(repo)
        token_scanning_feature.enable(actor: repo.owner)
        GitHub.flipper[FeatureFlags::AI_ASSISTED_REMEDIATION_GUIDANCE_FOR_GH_PATS].disable

        refute token_scanning_feature.ai_assisted_remediation_guidance_enabled?
      end
      test "false when secret scanning disabled" do
        repo = @with_ghas[:org_private_repo]
        token_scanning_feature = SecretScanning::Features::Repo::TokenScanning.new(repo)
        token_scanning_feature.disable(actor: repo.owner)
        GitHub.flipper[FeatureFlags::AI_ASSISTED_REMEDIATION_GUIDANCE_FOR_GH_PATS].enable

        refute token_scanning_feature.ai_assisted_remediation_guidance_enabled?
      end
      test "false when public" do
        repo = @with_ghas[:org_public_repo]
        token_scanning_feature = SecretScanning::Features::Repo::TokenScanning.new(repo)
        token_scanning_feature.enable(actor: repo.owner)
        GitHub.flipper[FeatureFlags::AI_ASSISTED_REMEDIATION_GUIDANCE_FOR_GH_PATS].enable

        refute token_scanning_feature.ai_assisted_remediation_guidance_enabled?
      end
      test "true when private, secret scanning enabled, and feature flag enabled" do
        repo = @with_ghas[:org_private_repo]
        token_scanning_feature = SecretScanning::Features::Repo::TokenScanning.new(repo)
        token_scanning_feature.enable(actor: repo.owner)
        GitHub.flipper[FeatureFlags::AI_ASSISTED_REMEDIATION_GUIDANCE_FOR_GH_PATS].enable

        assert token_scanning_feature.ai_assisted_remediation_guidance_enabled?
      end
    end


    context "display_alert_permissions_on_show_page?" do
      test "false when ff disabled" do
        repo = @with_ghas[:org_private_repo]
        token_scanning_feature = SecretScanning::Features::Repo::TokenScanning.new(repo)
        token_scanning_feature.enable(actor: repo.owner)
        GitHub.flipper[FeatureFlags::DISPLAY_ALERT_PERMISSIONS].disable

        refute token_scanning_feature.display_alert_permissions_on_show_page?
      end
      test "false when secret scanning disabled" do
        repo = @with_ghas[:org_private_repo]
        token_scanning_feature = SecretScanning::Features::Repo::TokenScanning.new(repo)
        token_scanning_feature.disable(actor: repo.owner)
        GitHub.flipper[FeatureFlags::DISPLAY_ALERT_PERMISSIONS].enable

        refute token_scanning_feature.display_alert_permissions_on_show_page?
      end
      test "false when public" do
        repo = @with_ghas[:org_public_repo]
        token_scanning_feature = SecretScanning::Features::Repo::TokenScanning.new(repo)
        token_scanning_feature.enable(actor: repo.owner)
        GitHub.flipper[FeatureFlags::DISPLAY_ALERT_PERMISSIONS].enable

        refute token_scanning_feature.display_alert_permissions_on_show_page?
      end
      test "true when private, secret scanning enabled, and feature flag enabled" do
        repo = @with_ghas[:org_private_repo]
        token_scanning_feature = SecretScanning::Features::Repo::TokenScanning.new(repo)
        token_scanning_feature.enable(actor: repo.owner)
        GitHub.flipper[FeatureFlags::DISPLAY_ALERT_PERMISSIONS].enable

        assert token_scanning_feature.display_alert_permissions_on_show_page?
      end
    end
  end
end
