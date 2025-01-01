# typed: true
# frozen_string_literal: true

require "github/launch_client"
require "test_helper"
require "test_helpers/fake_kredz"
require "test_helpers/secrets_test_helpers"

module Codespaces
  class CreatePrebuildInstanceTest < GitHub::TestCase
    include SecretsTestHelper
    include CodespacesPlanFixtures

    fixtures do
      make_trusted_oauth_apps_owner
      @user = create(:user)
      enable_feature_flag(:codespaces_developer, @user)
      @org = create(:codespaces_organization, admin: @user)
      @repo = create(:repository, owner: @org)
      @integration = create(:codespaces_integration)
      @pool = "testpool123"
      @secret_value = "super secret string"
      disable_feature_flag(:codespaces_billing_free)
    end

    context "#validate!", skip_enterprise: true do
      test "raises when passing a vscs_target_url but the user isn't a codespaces developer" do
        assert_raises Codespaces::ValidatePrebuildAccess::AuthorizationError do
          Codespaces::CreatePrebuildInstance.call(
            repository: @repo,
            pool_code: @pool,
            location: "EastUs",
            vscs_target_url: "http://myevilurl.com/evil"
          )
        end
      end

      test "raises when passing a vscs_target_url but the vscs_target isn't `local`" do
        enable_feature_flag(:codespaces_developer)

        assert_raises Codespaces::CreatePrebuildInstance::InvalidTarget do
          Codespaces::CreatePrebuildInstance.call(
            repository: @repo,
            pool_code: @pool,
            location: "EastUs",
            vscs_target_url: "localhost:3000",
            vscs_target: "ppe"
          )
        end
      end

      test "does not raise error when passing a vscs_target_url and the vscs_target `local`" do
        enable_feature_flag(:codespaces_developer)
        repo_secret = create_secret(@repo)

        vscs_target_host = "vscstest.ngrok.io"

        FakeKredz.with_secrets(repo_secret) do
          FakeVSOServer.reset!
          Codespaces::CreatePrebuildInstance.call(
            repository: @repo,
            pool_code: "test",
            location: "WestUs2",
            vscs_target_url: "https://#{vscs_target_host}",
            vscs_target: "local"
          )
        end
        request = FakeVSOServer.requests.last
        assert_includes request.env["HTTP_HOST"], vscs_target_host
      end

      test "raises when the org hasn't enabled codespaces" do
        org = create(:codespaces_organization, plan: GitHub::Plan.free, admin: @user)
        repo = create(:repository, owner: org)

        assert_raises Codespaces::ValidatePrebuildAccess::AuthorizationError do
          Codespaces::CreatePrebuildInstance.call(
            repository: repo,
            pool_code: @pool,
            location: "EastUs"
          )
        end
      end
    end

    context "#perform", skip_enterprise: true do
      test "to vscs's prebuild instance endpoint" do
        repo_secret = create_secret(@repo)

        FakeKredz.with_secrets(repo_secret) do
          pool = "testpool123"
          FakeVSOServer.reset!

          Codespaces::CreatePrebuildInstance.call(
            repository: @repo,
            pool_code: pool,
            location: "EastUs"
          )
          request = FakeVSOServer.requests.last
          request_body = GitHub::JSON.parse(request.body)
          assert_equal "/api/v2/prebuilds/pools/#{pool}/instances", request.path
          secrets = request_body["secrets"]
          refute_nil secrets
          assert secrets.length > 0
        end
      end

      Codespaces::GetPrebuildSecrets::PREBUILD_PAT_SECRET_KEYS.each do |secret_key|
        test "filters out #{secret_key} from repo secrets" do
          repo_secret = create_secret(@repo, secret_key)

          FakeKredz.with_secrets(repo_secret) do
            FakeVSOServer.reset!
            Codespaces::CreatePrebuildInstance.call(
              repository: @repo,
              pool_code: "test",
              location: "EastUs"
            )
            request = FakeVSOServer.requests.last
            request_body = GitHub::JSON.parse(request.body)
            secrets = request_body["secrets"]
            assert_nil secrets.find { |s| s["name"] == secret_key }
          end
        end

        test "filters out #{secret_key} from org secrets" do
          org_secret = create_secret(@org, secret_key)

          FakeKredz.with_secrets(org_secret) do
            FakeVSOServer.reset!
            Codespaces::CreatePrebuildInstance.call(
              repository: @repo,
              pool_code: "test",
              location: "EastUs"
            )
            request = FakeVSOServer.requests.last
            request_body = GitHub::JSON.parse(request.body)
            secrets = request_body["secrets"]
            assert_nil secrets.find { |s| s["name"] == secret_key }
          end
        end

        test "Includes `GITHUB_TOKEN` as #{secret_key} in secrets" do
          repo_secret = create_secret(@repo, secret_key)

          FakeKredz.with_secrets(repo_secret) do
            FakeVSOServer.reset!
            Codespaces::CreatePrebuildInstance.call(
              repository: @repo,
              pool_code: "test",
              location: "EastUs"
            )
            request = FakeVSOServer.requests.last
            request_body = GitHub::JSON.parse(request.body)
            secrets = request_body["secrets"]
            github_token_secret = secrets.find { |s| s["name"] == "GITHUB_TOKEN" }
            assert_equal @secret_value, github_token_secret["value"]
          end
        end
      end

      test "handles both kinds of secrets being defined" do
        repo_secret = create_secret(@repo, Codespaces::GetPrebuildSecrets::PREBUILD_PAT_SECRET_KEY)
        other_repo_secret = create_secret(@repo, Codespaces::GetPrebuildSecrets::LEGACY_PREBUILD_PAT_SECRET_KEY)

        FakeKredz.with_secrets(repo_secret) do
          FakeVSOServer.reset!
          Codespaces::CreatePrebuildInstance.call(
            repository: @repo,
            pool_code: "test",
            location: "EastUs"
          )
          request = FakeVSOServer.requests.last
          request_body = GitHub::JSON.parse(request.body)
          secrets = request_body["secrets"]
          assert_nil secrets.find { |s| s["name"] == Codespaces::GetPrebuildSecrets::PREBUILD_PAT_SECRET_KEY }
          assert_nil secrets.find { |s| s["name"] == Codespaces::GetPrebuildSecrets::LEGACY_PREBUILD_PAT_SECRET_KEY }
        end
      end
    end

    def create_secret(owner, secret_name = Codespaces::GetPrebuildSecrets::PREBUILD_PAT_SECRET_KEY)
      {
        app: @integration,
        name: secret_name,
        value: encrypt_with_owner_next_global_id(@secret_value, owner),
        owner: owner,
        selected_repositories: [@repo.global_relay_id],
      }
    end
  end
end
