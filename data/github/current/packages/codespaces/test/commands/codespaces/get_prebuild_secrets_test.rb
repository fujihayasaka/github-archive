# typed: true
# frozen_string_literal: true

require "github/launch_client"
require "test_helper"
require "test_helpers/fake_kredz"
require "test_helpers/secrets_test_helpers"

module Codespaces
  class GetPrebuildSecretsTest < GitHub::TestCase
    include SecretsTestHelper
    include CodespacesPlanFixtures
    include DogstatsTestHelpers


    fixtures do
      make_trusted_oauth_apps_owner
      @user = create(:user)
      enable_feature_flag(:codespaces_developer, @user)
      @org = create(:codespaces_organization, admin: @user)
      @repo = create(:repository, owner: @org)
      @integration = create(:codespaces_integration)
      @pool = "testpool123"
    end

    setup do
      @repo_secret = {
        app: @integration,
        name: Codespaces::GetPrebuildSecrets::PREBUILD_PAT_SECRET_KEY,
        value: encrypt_with_owner_next_global_id("super secret string", @repo),
        owner: @repo,
      }

      @legacy_repo_secret = {
        app: @integration,
        name: Codespaces::GetPrebuildSecrets::LEGACY_PREBUILD_PAT_SECRET_KEY,
        value: encrypt_with_owner_next_global_id("super secret string", @repo),
        owner: @repo,
      }

      @another_repo_secret = {
        app: @integration,
        name: "test",
        value: encrypt_with_owner_next_global_id("test", @repo),
        owner: @repo,
      }

      @org_secret = {
        app: @integration,
        name: Codespaces::GetPrebuildSecrets::PREBUILD_PAT_SECRET_KEY,
        value: encrypt_with_owner_next_global_id("super secret string", @org),
        owner: @org,
        selected_repositories: [@repo.global_relay_id],
      }

      @legacy_org_secret = {
        app: @integration,
        name: Codespaces::GetPrebuildSecrets::LEGACY_PREBUILD_PAT_SECRET_KEY,
        value: encrypt_with_owner_next_global_id("super secret string", @org),
        owner: @org,
        selected_repositories: [@repo.global_relay_id],
      }
    end

    context "#perform", skip_enterprise: true do

      test "returns expected secrets" do
        FakeKredz.with_secrets(@repo_secret, @another_repo_secret) do
          secrets_data = Codespaces::GetPrebuildSecrets.call(
            repository: @repo
          )

          secrets = secrets_data[:secrets]
          refute_nil secrets
          assert_equal 1, secrets.count
        end
      end

      test "filters out PREBUILD_PAT_SECRET_KEY from repo secrets" do
        FakeKredz.with_secrets(@repo_secret, @another_repo_secret) do
          secrets_data = Codespaces::GetPrebuildSecrets.call(
            repository: @repo
          )

          secrets = secrets_data[:secrets]
          assert_nil secrets.find { |s| s.name == Codespaces::GetPrebuildSecrets::PREBUILD_PAT_SECRET_KEY }
        end
      end

      test "filters out LEGACY_PREBUILD_PAT_SECRET_KEY from repo secrets" do
        FakeKredz.with_secrets(@legacy_repo_secret, @another_repo_secret) do
          secrets_data = Codespaces::GetPrebuildSecrets.call(
            repository: @repo
          )

          secrets = secrets_data[:secrets]
          assert_nil secrets.find { |s| s.name == Codespaces::GetPrebuildSecrets::LEGACY_PREBUILD_PAT_SECRET_KEY }
        end
      end

      test "filters out PREBUILD_PAT_SECRET_KEY from org secrets" do
        FakeKredz.with_secrets(@org_secret) do
          secrets_data = Codespaces::GetPrebuildSecrets.call(
            repository: @repo
          )

          secrets = secrets_data[:secrets]
          assert_nil secrets.find { |s| s["name"] == Codespaces::GetPrebuildSecrets::PREBUILD_PAT_SECRET_KEY }
        end
      end

      test "filters out LEGACY_PREBUILD_PAT_SECRET_KEY from org secrets" do
        FakeKredz.with_secrets(@legacy_org_secret) do
          secrets_data = Codespaces::GetPrebuildSecrets.call(
            repository: @repo
          )

          secrets = secrets_data[:secrets]
          assert_nil secrets.find { |s| s["name"] == Codespaces::GetPrebuildSecrets::LEGACY_PREBUILD_PAT_SECRET_KEY }
        end
      end

      test "Includes github_token as PREBUILD_PAT_SECRET_KEY" do
        FakeKredz.with_secrets(@repo_secret, @another_repo_secret, @legacy_repo_secret) do
          secrets_data = Codespaces::GetPrebuildSecrets.call(
            repository: @repo
          )

          github_token = secrets_data[:github_token]
          assert_equal "super secret string", github_token
        end
      end

      test "Includes github_token as LEGACY_PREBUILD_PAT_SECRET_KEY if no PREBUILD_PAT_SECRET_KEY" do
        FakeKredz.with_secrets(@legacy_repo_secret, @another_repo_secret) do
          secrets_data = Codespaces::GetPrebuildSecrets.call(
            repository: @repo
          )

          github_token = secrets_data[:github_token]
          assert_equal "super secret string", github_token
          assert_dogstats_increment 1, "codespaces.get_prebuild_secrets.decrypted_path_token.legacy_prebuild_pat"
        end
      end

      test "by default, does not raise error when PREBUILD_PAT_SECRET_KEY is not found" do
        repo_secret = {
          app: @integration,
          name: "OtherSecret",
          value: encrypt_with_owner_next_global_id("super secret string", @repo),
          owner: @repo,
        }
        FakeKredz.with_secrets(repo_secret) do
          assert_nothing_raised do
            Codespaces::GetPrebuildSecrets.call(repository: @repo)
          end
        end
      end

      test "mints a new github token if no PREBUILD_PAT_SECRET_KEY or LEGACY_PREBUILD_PAT_SECRET_KEY" do
        FakeKredz.with_secrets(@another_repo_secret) do
          secrets_data = Codespaces::GetPrebuildSecrets.call(
            repository: @repo,
            pat_secret_required: true
          )

          github_token = secrets_data[:github_token]
          assert github_token
        end
      end

    end
  end
end
