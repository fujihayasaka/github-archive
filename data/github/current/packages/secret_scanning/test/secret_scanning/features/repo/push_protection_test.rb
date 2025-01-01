# typed: true
# frozen_string_literal: true

require "test_helper"

module SecretScanning::Features::Repo
  class RepoPushProtectionTest < GitHub::TestCase
    include SecretScanning::Features::FeatureFlagHelper
    include RepoFeatureAvailabilityTest

    fixtures do
      @user = create(:user)
      @with_ghas = create_fixtures(opts: {
        mark_ghas_as_purchased: true,
        enable_ghas: true,
        enable_token_scanning: true,
      })

      @no_ghas = create_fixtures(opts: {
        mark_ghas_as_purchased: false,
        enable_token_scanning: true, # Still enables it for free public repos
      })

      @ghas_not_enabled = create_fixtures(opts: {
        mark_ghas_as_purchased: true,
        enable_ghas: false,
        enable_token_scanning: true, # Still enables it for free public repos
      })

      @no_token_scanning = create_fixtures(opts: {
        mark_ghas_as_purchased: true,
        enable_ghas: true,
        enable_token_scanning: false,
      })

      @secret_scanning_license_not_available = create_fixtures(opts: {
        mark_ghas_as_purchased: true,
        secret_scanning_license_available: false,
        enable_ghas: false,
        enable_token_scanning: true
      })

      @secret_scanning_license_available = create_fixtures(opts: {
        mark_ghas_as_purchased: true,
        secret_scanning_license_available: true,
        enable_ghas: false,
        enable_token_scanning: true
      })
    end

    setup do
      GitHub.stubs(:configuration_secret_scanning_enabled?).returns(true)
      GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(true)
      enable_feature_flag(FeatureFlags::PUSH_PROTECTION_FOR_FPR)
    end

    context "initialize" do
      test "good input" do
        repo = create(:repository)
        refute SecretScanning::Features::Repo::PushProtection.new(repo).nil?
      end
    end

    context "feature_available?" do
      context "on GHEC", skip_enterprise: true do
        test "when ghas has been purchased and secret-scanning is enabled" do
          check_fn = ->(repo) { SecretScanning::Features::Repo::PushProtection.new(repo).feature_available? }
          matrix = {
            user_public_repo: true,
            user_private_repo: false,
            user_archived_public_repo: false,
            user_archived_private_repo: false,

            emu_private_repo: true,
            emu_archived_repo: false,

            org_public_repo: true,
            org_private_repo: true,
            org_internal_repo: true,

            org_archived_public_repo: false,
            org_archived_private_repo: false,
            org_archived_internal_repo: false,
          }
          assert_availability_on_all_repos(check_fn:, test_fixtures: @with_ghas, matrix:)
        end

        test "when ghas has not been purchased" do
          check_fn = ->(repo) { SecretScanning::Features::Repo::PushProtection.new(repo).feature_available? }
          matrix = {
            user_public_repo: true,
            user_private_repo: false,
            user_archived_public_repo: false,
            user_archived_private_repo: false,

            emu_private_repo: false,
            emu_archived_repo: false,

            org_public_repo: true,
            org_private_repo: false,
            org_internal_repo: false,

            org_archived_public_repo: false,
            org_archived_private_repo: false,
            org_archived_internal_repo: false,
          }
          assert_availability_on_all_repos(check_fn:, test_fixtures: @no_ghas, matrix:)
        end

        test "when ghas has not been enabled" do
          check_fn = ->(repo) { SecretScanning::Features::Repo::PushProtection.new(repo).feature_available? }
          matrix = {
            user_public_repo: true,
            user_private_repo: false,
            user_archived_public_repo: false,
            user_archived_private_repo: false,

            emu_private_repo: false,
            emu_archived_repo: false,

            org_public_repo: true,
            org_private_repo: false,
            org_internal_repo: false,

            org_archived_public_repo: false,
            org_archived_private_repo: false,
            org_archived_internal_repo: false,
          }
          assert_availability_on_all_repos(check_fn:, test_fixtures: @ghas_not_enabled, matrix:)
        end

        test "when secret scanning is not enabled" do
          check_fn = ->(repo) { SecretScanning::Features::Repo::PushProtection.new(repo).feature_available? }
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
          assert_availability_on_all_repos(check_fn:, test_fixtures: @no_token_scanning, matrix:)
        end

        test "when flags are disabled" do
          disable_feature_flag(FeatureFlags::PUSH_PROTECTION_FOR_FPR)

          check_fn = ->(repo) { SecretScanning::Features::Repo::PushProtection.new(repo).feature_available? }
          matrix = {
            user_public_repo: false,
            user_private_repo: false,
            user_archived_public_repo: false,
            user_archived_private_repo: false,

            emu_private_repo: true,
            emu_archived_repo: false,

            org_public_repo: true,
            org_private_repo: true,
            org_internal_repo: true,

            org_archived_public_repo: false,
            org_archived_private_repo: false,
            org_archived_internal_repo: false,
          }
          assert_availability_on_all_repos(check_fn:, test_fixtures: @with_ghas, matrix:)
        end

        test "when sku split is enabled and secret scanning is not available" do
          SecretScanning::Features::AdvancedSecurityHelper.stubs(:secret_scanning_available?).returns(false)

          check_fn = ->(repo) { SecretScanning::Features::Repo::PushProtection.new(repo).feature_available? }
          matrix = {
            user_public_repo: true,
            user_private_repo: false,
            user_archived_public_repo: false,
            user_archived_private_repo: false,

            emu_private_repo: false,
            emu_archived_repo: false,

            org_public_repo: true,
            org_private_repo: false,
            org_internal_repo: false,

            org_archived_public_repo: false,
            org_archived_private_repo: false,
            org_archived_internal_repo: false,
          }
          assert_availability_on_all_repos(check_fn:, test_fixtures: @secret_scanning_license_not_available, matrix:)
        end

        test "when sku split is enabled and secret scanning is available" do
          SecretScanning::Features::AdvancedSecurityHelper.stubs(:secret_scanning_available?).returns(true)

          check_fn = ->(repo) { SecretScanning::Features::Repo::PushProtection.new(repo).feature_available? }
          matrix = {
            user_public_repo: true,
            user_private_repo: true,
            user_archived_public_repo: false,
            user_archived_private_repo: false,

            emu_private_repo: true,
            emu_archived_repo: false,

            org_public_repo: true,
            org_private_repo: true,
            org_internal_repo: true,

            org_archived_public_repo: false,
            org_archived_private_repo: false,
            org_archived_internal_repo: false,
          }
          assert_availability_on_all_repos(check_fn:, test_fixtures: @secret_scanning_license_available, matrix:)
        end
      end

      context "on GHES", enterprise_only: true do
        test "when ghas has been purchased and secret-scanning is enabled" do
          check_fn = ->(repo) { SecretScanning::Features::Repo::PushProtection.new(repo).feature_available? }
          matrix = {
            user_public_repo: true,
            user_private_repo: true,
            user_archived_public_repo: false,
            user_archived_private_repo: false,

            org_public_repo: true,
            org_private_repo: true,
            org_internal_repo: true,

            org_archived_public_repo: false,
            org_archived_private_repo: false,
            org_archived_internal_repo: false,
          }
          assert_availability_on_all_repos(check_fn:, test_fixtures: @with_ghas, matrix:)
        end

        test "when ghas has not been purchased" do
          check_fn = ->(repo) { SecretScanning::Features::Repo::PushProtection.new(repo).feature_available? }
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
          assert_availability_on_all_repos(check_fn:, test_fixtures: @no_ghas, matrix:)
        end

        test "when ghas has not been enabled" do
          check_fn = ->(repo) { SecretScanning::Features::Repo::PushProtection.new(repo).feature_available? }
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
          assert_availability_on_all_repos(check_fn:, test_fixtures: @ghas_not_enabled, matrix:)
        end

        test "when secret scanning is not enabled" do
          check_fn = ->(repo) { SecretScanning::Features::Repo::PushProtection.new(repo).feature_available? }
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
          assert_availability_on_all_repos(check_fn:, test_fixtures: @no_token_scanning, matrix:)
        end
      end
    end

    context "enabled? / enable / disable" do
      context "on GHEC", skip_enterprise: true do
        test "enablement" do
          @with_ghas.each do |_, repo|
            SecretScanning::Features::Repo::PushProtection.new(repo).enable(actor: repo.owner)
          end
          check_fn = ->(repo) { SecretScanning::Features::Repo::PushProtection.new(repo).enabled? }

          matrix = {
            user_public_repo: true,
            user_private_repo: false,
            user_archived_public_repo: false,
            user_archived_private_repo: false,

            emu_private_repo: true,
            emu_archived_repo: false,

            org_public_repo: true,
            org_private_repo: true,
            org_internal_repo: true,

            org_archived_public_repo: false,
            org_archived_private_repo: false,
            org_archived_internal_repo: false,
          }
          assert_availability_on_all_repos(check_fn:, test_fixtures: @with_ghas, matrix:)
        end

        test "disablement" do
          @with_ghas.each do |_, repo|
            SecretScanning::Features::Repo::PushProtection.new(repo).enable(actor: repo.owner)
            SecretScanning::Features::Repo::PushProtection.new(repo).disable(actor: repo.owner)
          end
          check_fn = ->(repo) { SecretScanning::Features::Repo::PushProtection.new(repo).enabled? }

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

        test "when ghas is not purchased" do
          # simple test just to drive the same checks happening in feature_available?
          @no_ghas.each do |_, repo|
            SecretScanning::Features::Repo::PushProtection.new(repo).enable(actor: repo.owner)
          end
          check_fn = ->(repo) { SecretScanning::Features::Repo::PushProtection.new(repo).enabled? }

          matrix = {
            user_public_repo: true,
            user_private_repo: false,
            user_archived_public_repo: false,
            user_archived_private_repo: false,

            emu_private_repo: false,
            emu_archived_repo: false,

            org_public_repo: true,
            org_private_repo: false,
            org_internal_repo: false,

            org_archived_public_repo: false,
            org_archived_private_repo: false,
            org_archived_internal_repo: false,
          }
          assert_availability_on_all_repos(check_fn:, test_fixtures: @no_ghas, matrix:)
        end
      end
    end

    test "disabled if repo is importing" do
      repo = @with_ghas[:org_private_repo]
      repo.stubs(:is_importing?).returns(true)
      SecretScanning::Features::Repo::PushProtection.new(repo).enable(actor: repo.owner)

      refute SecretScanning::Features::Repo::PushProtection.new(repo).enabled?
    end

    test "supports skipping import check" do
      repo = @with_ghas[:org_private_repo]
      repo.stubs(:is_importing?).returns(true)
      SecretScanning::Features::Repo::PushProtection.new(repo).enable(actor: repo.owner)

      assert SecretScanning::Features::Repo::PushProtection.new(repo).enabled?(ignore_import: true)
    end

    context "feedback_banner_enabled?" do
      test "returns true if feature flag is enabled" do
        enable_feature_flag(FeatureFlags::PUSH_PROTECTION_FEEDBACK_BANNER)

        repo = @with_ghas[:org_private_repo]
        assert SecretScanning::Features::Repo::PushProtection.new(repo).feedback_banner_enabled?
      end

      test "returns false if feature flag is disabled" do
        disable_feature_flag(FeatureFlags::PUSH_PROTECTION_FEEDBACK_BANNER)

        repo = @with_ghas[:org_private_repo]
        refute SecretScanning::Features::Repo::PushProtection.new(repo).feedback_banner_enabled?
      end
    end
  end
end
