# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/fake_kredz"
require "test_helpers/secrets_test_helpers"

module Codespaces
  class CreateEnvironmentTest < GitHub::TestCase
    include SecretsTestHelper
    include DogstatsTestHelpers
    include GitHub::LoggerHelper

    fixtures do
      make_trusted_oauth_apps_owner
      @integration = create(:codespaces_integration)
      create(:codespaces_vm_secrets_integration)
      @monalisa = create(:paid_user, name: "monalisa")
      @repo = create(:repository, owner: @monalisa, from_example: :simple)
      @codespace = create(:codespace, owner: @monalisa, repository: @repo)
      disable_feature_flag(:disable_codespaces_secrets)
    end

    setup do
      @user_secret = {
        app: @integration,
        name: "USER_SECRET",
        value: encrypt_with_owner_next_global_id("super secret string", @monalisa),
        owner: @monalisa,
        selected_repositories: [@repo.global_relay_id],
      }

      @container_registry_server_secret = {
        app: @integration,
        name: "FOO_CONTAINER_REGISTRY_SERVER",
        value: encrypt_with_owner_next_global_id("fake-registry.com", @monalisa),
        owner: @monalisa,
        selected_repositories: [@repo.global_relay_id],
      }

      @container_registry_username_secret = {
        app: @integration,
        name: "FOO_CONTAINER_REGISTRY_USER",
        value: encrypt_with_owner_next_global_id("monalisa", @monalisa),
        owner: @monalisa,
        selected_repositories: [@repo.global_relay_id],
      }

      @container_registry_password_secret = {
        app: @integration,
        name: "FOO_CONTAINER_REGISTRY_PASSWORD",
        value: encrypt_with_owner_next_global_id("p@ssw0rd", @monalisa),
        owner: @monalisa,
        selected_repositories: [@repo.global_relay_id],
      }

      @container_registry_server_secret_no_prefix = {
        app: @integration,
        name: "CONTAINER_REGISTRY_SERVER",
        value: encrypt_with_owner_next_global_id("other-fake-registry.com", @monalisa),
        owner: @monalisa,
        selected_repositories: [@repo.global_relay_id],
      }

      @container_registry_username_secret_no_prefix = {
        app: @integration,
        name: "CONTAINER_REGISTRY_USER",
        value: encrypt_with_owner_next_global_id("monalisa", @monalisa),
        owner: @monalisa,
        selected_repositories: [@repo.global_relay_id],
      }

      @container_registry_password_secret_no_prefix = {
        app: @integration,
        name: "CONTAINER_REGISTRY_PASSWORD",
        value: encrypt_with_owner_next_global_id("p@ssw0rd", @monalisa),
        owner: @monalisa,
        selected_repositories: [@repo.global_relay_id],
      }

      @dockerhub_registry_server_secret = {
        app: @integration,
        name: "DOCKERHUB_CONTAINER_REGISTRY_SERVER",
        value: encrypt_with_owner_next_global_id("https://index.docker.io/v1/", @monalisa),
        owner: @monalisa,
        selected_repositories: [@repo.global_relay_id],
      }

      @dockerhub_registry_username_secret = {
        app: @integration,
        name: "DOCKERHUB_CONTAINER_REGISTRY_USER",
        value: encrypt_with_owner_next_global_id("monalisa", @monalisa),
        owner: @monalisa,
        selected_repositories: [@repo.global_relay_id],
      }

      @dockerhub_registry_password_secret = {
        app: @integration,
        name: "DOCKERHUB_CONTAINER_REGISTRY_PASSWORD",
        value: encrypt_with_owner_next_global_id("p@ssw0rd", @monalisa),
        owner: @monalisa,
        selected_repositories: [@repo.global_relay_id],
      }
    end

    context "create", skip_enterprise: true do
      test "creates the environment" do
        FakeVSOServer.reset!
        FakeKredz.with_no_secrets do
          Codespaces::CreateEnvironment.call(@codespace, github_token: "")
        end

        environment = FakeVSOServer.environments_created.last
        assert_equal @codespace.name, environment["friendlyName"]
        assert_equal @codespace.moniker, environment["seed"]["moniker"]
      end

      test "returns an internal timeout error wrapping the original on timeout" do
        Codespaces::VscsClient.any_instance.stubs(:create_environment).raises(Codespaces::Client::TimeoutError.new("BOOM!"))
        assert_raises Codespaces::CreateEnvironment::TimeoutError do
          FakeKredz.with_no_secrets do
            Codespaces::CreateEnvironment.call(@codespace, github_token: "")
          end
        end
      end

      test "it mints a codespace token when calling create_environment and sends it as a secret" do
        Codespaces::Tokens.stubs(:mint_codespace_token).returns("codespace_token")

        FakeKredz.with_no_secrets do
          Codespaces::CreateEnvironment.call(@codespace, github_token: "github_token")
        end

        env = FakeVSOServer.environments_created.last
        codespace_token_secret = env["secrets"].find { |s| s["name"] == "GITHUB_CODESPACE_TOKEN" }
        assert_equal "codespace_token", codespace_token_secret["value"]
      end
    end

    context "sku", skip_enterprise: true do
      test "provisions 'standardLinux32gb' machines for preview-enrolled orgs’ plans" do
        FakeVSOServer.reset!

        org = create(:organization, admin: @monalisa)
        repo = create(:repository, owner: org)
        codespace = create(:codespace, owner: @monalisa, repository: repo, ref: repo.default_branch)

        FakeKredz.with_no_secrets do
          Codespaces::CreateEnvironment.call(codespace, github_token: "")
        end

        environment = FakeVSOServer.environments_created.last
        assert_equal "standardLinux32gb", environment["skuName"]
      end

      test "provisions 'standardLinux32gb' machines (the default) for non-preview-enrolled orgs’ plans" do
        FakeVSOServer.reset!

        org = create(:organization, admin: @monalisa)
        repo = create(:repository, owner: org)
        codespace = create(:codespace, owner: @monalisa, repository: repo, ref: repo.default_branch, enable_org_access: false)

        FakeKredz.with_no_secrets do
          Codespaces::CreateEnvironment.call(codespace, github_token: "")
        end

        environment = FakeVSOServer.environments_created.last
        assert_equal "standardLinux32gb", environment["skuName"]
      end

      test "provisions 'standardLinux32gb' machines (the default) for users’ plans" do
        FakeVSOServer.reset!

        repo = create(:repository, owner: @monalisa)
        codespace = create(:codespace, owner: @monalisa, repository: repo, ref: repo.default_branch)

        FakeKredz.with_no_secrets do
          Codespaces::CreateEnvironment.call(codespace, github_token: "")
        end

        environment = FakeVSOServer.environments_created.last
        assert_equal "standardLinux32gb", environment["skuName"]
      end

      test "provisions dynamic sku when passed in to environment options" do
        FakeVSOServer.reset!

        repo = create(:repository, owner: @monalisa)
        codespace = create(:codespace, owner: @monalisa, repository: repo, ref: repo.default_branch, sku_name: "extremeLinux")

        FakeKredz.with_no_secrets do
          Codespaces::CreateEnvironment.call(codespace, environment_options: {}, github_token: "")
        end

        environment = FakeVSOServer.environments_created.last
        assert_equal "extremeLinux", environment["skuName"]
      end
    end

    context "secrets", skip_enterprise: true do
      test "If user has secrets, they are sent to create call" do
        FakeVSOServer.reset!

        FakeKredz.with_secrets(@user_secret) do
          Codespaces::CreateEnvironment.call(@codespace, github_token: "")

          environment = FakeVSOServer.environments_created.last
          user_secret = environment["secrets"].find { |s| s["name"] == "USER_SECRET" }
          refute_nil user_secret
          assert_equal "super secret string", user_secret["value"]
        end
      end

      test "user secrets are sent to create call for read-only codespaces" do
        FakeVSOServer.reset!

        readonly_codespace = create(:codespace, owner: @monalisa)
        readonly_secret = {
          app: @integration,
          name: "READONLY_SECRET",
          value: encrypt_with_owner_next_global_id("super secret string", @monalisa),
          owner: @monalisa,
          selected_repositories: [readonly_codespace.repository.global_relay_id],
        }
        FakeKredz.with_secrets(readonly_secret) do
          Codespaces::CreateEnvironment.call(readonly_codespace, github_token: "")

          environment = FakeVSOServer.environments_created.last
          user_secret = environment["secrets"].find { |s| s["name"] == "READONLY_SECRET" }
          refute_nil user_secret
          assert_equal "super secret string", user_secret["value"]
        end
      end

      test "No secrets are sent if user has none" do
        FakeVSOServer.reset!

        FakeKredz.with_no_secrets do
          Codespaces::Tokens.stubs(:mint_codespace_token).returns("")
          Codespaces::CreateEnvironment.call(@codespace, github_token: "")

          rando_codespace = create(:codespace)
          expected_secrets = Codespaces::AssembleSecrets.call(user: @codespace.owner, github_token: "", codespace_token: "", repository: nil, user_secrets: [], vscs_target_url: "")

          environment = FakeVSOServer.environments_created.last

          assert_equal expected_secrets.count, environment["secrets"].count
        end
      end

      test "Secrets aren't given for a codespace for a different repo" do
        FakeVSOServer.reset!

        repo = create(:repository, owner: @monalisa)
        other_codespace = create(:codespace, owner: @monalisa, repository: repo)

        FakeKredz.with_secrets(@user_secret) do
          Codespaces::CreateEnvironment.call(other_codespace, github_token: "")

          environment = FakeVSOServer.environments_created.last
          user_secret = environment["secrets"].find { |s| s["name"] == "USER_SECRET" }
          assert_nil user_secret
        end
      end

      test "Sends ContainerRegistry type secret if secrets are configured for that" do
        FakeVSOServer.reset!

        FakeKredz.with_secrets(@container_registry_server_secret, @container_registry_username_secret, @container_registry_password_secret) do
          Codespaces::CreateEnvironment.call(@codespace, github_token: "")

          environment = FakeVSOServer.environments_created.last
          registry_secret = environment["secrets"].find { |s| s["type"] == Codespaces::Secret::TYPE_CONTAINER_REGISTRY && s["name"] == "monalisa@fake-registry.com" }
          refute_nil registry_secret
          assert_equal "p@ssw0rd", registry_secret["value"]
        end
      end

      test "Sends ContainerRegistry type secret without the optional username when not provided" do
        FakeVSOServer.reset!

        FakeKredz.with_secrets(@container_registry_server_secret, @container_registry_password_secret) do
          Codespaces::CreateEnvironment.call(@codespace, github_token: "")

          environment = FakeVSOServer.environments_created.last
          registry_secret = environment["secrets"].find { |s| s["type"] == Codespaces::Secret::TYPE_CONTAINER_REGISTRY && s["name"] == "fake-registry.com" }
          refute_nil registry_secret
          assert_equal "p@ssw0rd", registry_secret["value"]
        end
      end

      test "Doesn't send ContainerRegistry type or any components as secrets when server is not provided" do
        FakeVSOServer.reset!

        FakeKredz.with_secrets(@container_registry_username_secret, @container_registry_password_secret) do
          Codespaces::CreateEnvironment.call(@codespace, github_token: "")

          environment = FakeVSOServer.environments_created.last
          assert_nil environment["secrets"].find { |s| s["type"] == Codespaces::Secret::TYPE_CONTAINER_REGISTRY && s["value"] == "p@ssw0rd" }
          assert_nil environment["secrets"].find { |s| s["name"] == "FOO_CONTAINER_REGISTRY_USER" }
          assert_nil environment["secrets"].find { |s| s["name"] == "FOO_CONTAINER_REGISTRY_PASSWORD" }
        end
      end

      test "Doesn't send ContainerRegistry type of any components as secrets when password is not provided" do
        FakeVSOServer.reset!

        FakeKredz.with_secrets(@container_registry_server_secret, @container_registry_username_secret) do
          Codespaces::CreateEnvironment.call(@codespace, github_token: "")

          environment = FakeVSOServer.environments_created.last
          assert_nil environment["secrets"].find { |s| s["type"] == Codespaces::Secret::TYPE_CONTAINER_REGISTRY && s["name"] == "monalisa@fake-registry.com" }
          assert_nil environment["secrets"].find { |s| s["name"] == "FOO_CONTAINER_REGISTRY_SERVER" }
          assert_nil environment["secrets"].find { |s| s["name"] == "FOO_CONTAINER_REGISTRY_USER" }
        end
      end

      test "Sends ContainerRegistry type secret even if there's no prefix" do
        FakeVSOServer.reset!

        FakeKredz.with_secrets(@container_registry_server_secret_no_prefix, @container_registry_username_secret_no_prefix, @container_registry_password_secret_no_prefix) do
          Codespaces::CreateEnvironment.call(@codespace, github_token: "")

          environment = FakeVSOServer.environments_created.last
          registry_secret = environment["secrets"].find { |s| s["type"] == Codespaces::Secret::TYPE_CONTAINER_REGISTRY && s["name"] == "monalisa@other-fake-registry.com" }
          refute_nil registry_secret
          assert_equal "p@ssw0rd", registry_secret["value"]
        end
      end

      test "EnvironmentVariable secrets followed by ContainerRegistry secrets both end up in the create request" do
        FakeVSOServer.reset!

        FakeKredz.with_secrets(@user_secret, @container_registry_server_secret, @container_registry_username_secret, @container_registry_password_secret) do
          Codespaces::CreateEnvironment.call(@codespace, github_token: "")

          environment = FakeVSOServer.environments_created.last
          user_secret = environment["secrets"].find { |s| s["name"] == "USER_SECRET" }
          refute_nil user_secret
          registry_secret = environment["secrets"].find { |s| s["type"] == Codespaces::Secret::TYPE_CONTAINER_REGISTRY && s["name"] == "monalisa@fake-registry.com" }
          refute_nil registry_secret
          assert_equal "p@ssw0rd", registry_secret["value"]
        end
      end

      test "ContainerRegistry secrets followed by EnvironmentVariables secrets both end up in the create request" do
        FakeVSOServer.reset!

        FakeKredz.with_secrets(@container_registry_server_secret, @container_registry_username_secret, @container_registry_password_secret, @user_secret) do
          Codespaces::CreateEnvironment.call(@codespace, github_token: "")

          environment = FakeVSOServer.environments_created.last
          user_secret = environment["secrets"].find { |s| s["name"] == "USER_SECRET" }
          refute_nil user_secret
          registry_secret = environment["secrets"].find { |s| s["type"] == Codespaces::Secret::TYPE_CONTAINER_REGISTRY && s["name"] == "monalisa@fake-registry.com" }
          refute_nil registry_secret
          assert_equal "p@ssw0rd", registry_secret["value"]
        end
      end

      test "Multiple ContainerRegistry secrets all end up in the create request" do
        FakeVSOServer.reset!

        FakeKredz.with_secrets(
          @container_registry_server_secret,
          @container_registry_username_secret,
          @container_registry_password_secret,
          @container_registry_server_secret_no_prefix,
          @container_registry_username_secret_no_prefix,
          @container_registry_password_secret_no_prefix) do
          Codespaces::CreateEnvironment.call(@codespace, github_token: "")

          environment = FakeVSOServer.environments_created.last
          registry_secret = environment["secrets"].find { |s| s["type"] == Codespaces::Secret::TYPE_CONTAINER_REGISTRY && s["name"] == "monalisa@fake-registry.com" }
          refute_nil registry_secret
          assert_equal "p@ssw0rd", registry_secret["value"]
          other_registry_secret = environment["secrets"].find { |s| s["type"] == Codespaces::Secret::TYPE_CONTAINER_REGISTRY && s["name"] == "monalisa@other-fake-registry.com" }
          refute_nil other_registry_secret
          assert_equal "p@ssw0rd", other_registry_secret["value"]
        end
      end

      test "Doesn't send default dockerhub login if user provided their own" do
        FakeVSOServer.reset!

        FakeKredz.with_secrets(@dockerhub_registry_server_secret, @dockerhub_registry_username_secret, @dockerhub_registry_password_secret) do
          Codespaces::CreateEnvironment.call(@codespace, github_token: "")

          environment = FakeVSOServer.environments_created.last
          assert_nil environment["secrets"].find { |s| s["type"] == Codespaces::Secret::TYPE_CONTAINER_REGISTRY && s["name"] == "codespacesdev@https://index.docker.io/v1/" }
        end
      end

      test "Sends default dockerhub login if user didn't provide their own" do
        disable_feature_flag(:codespaces_no_default_dockerhub_credentials)

        FakeVSOServer.reset!

        FakeKredz.with_secrets(@container_registry_server_secret, @container_registry_username_secret, @container_registry_password_secret) do
          Codespaces::CreateEnvironment.call(@codespace, github_token: "")

          environment = FakeVSOServer.environments_created.last
          dockerhub_secret = environment["secrets"].find { |s| s["type"] == Codespaces::Secret::TYPE_CONTAINER_REGISTRY && s["name"] == "codespacesdev@https://index.docker.io/v1/" }
          refute_nil dockerhub_secret
          assert_equal GitHub.codespaces_dockerhub_registry[:password], dockerhub_secret["value"]
        end
      end

      test "failed secrets requests get retried and eventually raise" do
        Codespaces::Secret.expects(:assemble).with(@codespace, host_setup: true).raises(Secrets::Error.new("Secrets Error", nil, nil)).times(4)

        assert_raises(Secrets::Error) do
          Codespaces::CreateEnvironment.call(@codespace, github_token: "")
        end
      end

      test "failed secrets requests produce failure metric" do
        Codespaces::Secret.expects(:assemble).with(@codespace, host_setup: true).raises(Secrets::Error.new("Secrets Error", nil, nil)).times(4)

        assert_raises(Secrets::Error) do
          Codespaces::CreateEnvironment.call(@codespace, github_token: "")
        end

        assert_dogstats_increment(1, "codespaces.create.secrets", tags: ["outcome:failure", "attempts:4"])
      end

      test "record stats on successful secrets request" do
        Codespaces::Secret.expects(:assemble).with(@codespace, host_setup: true).returns([])

        Codespaces::CreateEnvironment.call(@codespace, github_token: "")

        assert_dogstats_increment(1, "codespaces.create.secrets", tags: ["outcome:success", "attempts:1"])
      end

      test "captures secret length" do
        FakeKredz.with_secrets(@user_secret) do
          Codespaces::CreateEnvironment.call(@codespace, github_token: "")
          assert_dogstats_gauge_value("super secret string".length, "codespaces.secrets.value.length")
          assert_dogstats_gauge_value("USER_SECRET".length, "codespaces.secrets.key.length")
        end
      end

      test "captures number of secrets" do
        FakeKredz.with_secrets(@user_secret) do
          Codespaces::CreateEnvironment.call(@codespace, github_token: "")
          assert_dogstats_gauge_value(1, "codespaces.secrets.count")
        end
      end
    end

    context "git removal/reinit for unpublished codespaces" do
      test "removal but not reinit enabled for blank unpublished codespace" do
        unpublished_codespace = create(:unpublished_codespace)
        unpublished_codespace.stubs(:template).returns(Codespaces::Template::FIRST_PARTY_TEMPLATES[:blank])

        FakeKredz.with_no_secrets do
          Codespaces::CreateEnvironment.call(unpublished_codespace, github_token: "")
        end
        environment = FakeVSOServer.environments_created.last
        assert environment.dig("features", "removeRepoGit")
        refute environment.dig("features", "reinitRepoGit")
      end

      test "removal and reinit enabled for non-blank unpublished codespaces" do
        unpublished_codespace = create(:unpublished_codespace)

        FakeKredz.with_no_secrets do
          Codespaces::CreateEnvironment.call(unpublished_codespace, github_token: "")
        end
        environment = FakeVSOServer.environments_created.last
        assert environment.dig("features", "removeRepoGit")
        assert environment.dig("features", "reinitRepoGit")
      end

      test "disabled for published codespaces" do
        FakeKredz.with_no_secrets do
          Codespaces::CreateEnvironment.call(@codespace, github_token: "")
        end
        environment = FakeVSOServer.environments_created.last
        refute environment.dig("features", "removeRepoGit")
        refute environment.dig("features", "reinitRepoGit")
      end

      test "enables git removal for a repo that was a template repo but no longer is by the time we call CreateEnvironment" do
        unpublished_codespace = create(:unpublished_codespace)
        # We will return nil if the codespace's template repository has been de-templatized by the time we call this
        # so this is simulating that.
        unpublished_codespace.stubs(:template).returns(nil)

        FakeKredz.with_no_secrets do
          Codespaces::CreateEnvironment.call(unpublished_codespace, github_token: "")
        end
        environment = FakeVSOServer.environments_created.last
        assert environment.dig("features", "removeRepoGit")
        assert environment.dig("features", "reinitRepoGit")
      end
    end

    context "devcontainer.json", skip_enterprise: true do
      test "passes a .devcontainer/devcontainer.json file's data if present" do
        FakeVSOServer.reset!
        json_data = "{\n  \"name\": \"Custom Container Name\",\n  \"devPort\": 1234\n}\n"

        @codespace.repository.refs.find("master").append_commit({ message: "Add .devcontainer/devcontainer.json", committer: @monalisa }, @monalisa) do |files|
          files.add(".devcontainer/devcontainer.json", json_data)
        end
        @codespace.update!(oid: @codespace.repository.refs.find("master").sha)

        FakeKredz.with_no_secrets do
          Codespaces::CreateEnvironment.call(@codespace, github_token: "")
        end
        environment = FakeVSOServer.environments_created.last

        assert environment["hasDevcontainerJson"]
        assert_equal json_data, environment["devcontainerJson"]
      end

      test "passes a .devcontainer.json file's data if present" do
        json_data = "{\n  \"name\": \"Custom Container Name\",\n  \"devPort\": 1234\n}\n"

        @codespace.repository.refs.find("master").append_commit({ message: "Add .devcontainer.json", committer: @monalisa }, @monalisa) do |files|
          files.add(".devcontainer.json", json_data)
        end
        @codespace.update!(oid: @codespace.repository.refs.find("master").sha)

        FakeKredz.with_no_secrets do
          Codespaces::CreateEnvironment.call(@codespace, github_token: "")
        end
        environment = FakeVSOServer.environments_created.last

        assert environment["hasDevcontainerJson"]
        assert_equal json_data, environment["devcontainerJson"]
      end

      test "prefers .devcontainer/devcontainer.json to .devcontainer.json when both are present" do
        json_data = "{\n  \"name\": \"Custom Container Name\",\n  \"devPort\": 1234\n}\n"
        other_json_data = "{\n  \"name\": \"This Should Be Ignored\",\n  \"devPort\": 5678\n}\n"

        @codespace.repository.refs.find("master").append_commit({ message: "Add .devcontainer.json", committer: @monalisa }, @monalisa) do |files|
          files.add(".devcontainer/devcontainer.json", json_data)
          files.add(".devcontainer.json", other_json_data)
        end
        @codespace.update!(oid: @codespace.repository.refs.find("master").sha)

        FakeKredz.with_no_secrets do
          Codespaces::CreateEnvironment.call(@codespace, github_token: "")
        end
        environment = FakeVSOServer.environments_created.last

        assert environment["hasDevcontainerJson"]
        assert_equal json_data, environment["devcontainerJson"]
      end

      test "passes nothing if no devcontainer file is present" do
        FakeKredz.with_no_secrets do
          Codespaces::CreateEnvironment.call(@codespace, github_token: "")
        end
        environment = FakeVSOServer.environments_created.last

        refute environment["hasDevcontainerJson"]
        assert_nil environment["devcontainerJson"]
      end

      test "provisions with custom devcontainer.json path for org repo" do
        FakeVSOServer.reset!

        org = create(:organization, admin: @monalisa)
        repo = create(:repository, owner: org, from_example: :simple)

        repo.refs.find(repo.default_branch).append_commit({ message: "add devcontainer json file", committer: repo.owner }, repo.owner) do |files|
          files.add(".devcontainer/foobar/devcontainer.json", "{\"foo\":\"bar\"}")
        end

        codespace = create(:codespace, owner: @monalisa, repository: repo, ref: repo.default_branch, devcontainer_path: ".devcontainer/foobar/devcontainer.json")

        FakeKredz.with_no_secrets do
          Codespaces::CreateEnvironment.call(codespace, github_token: "", environment_options: { devcontainerPath: ".devcontainer/foobar/devcontainer.json" })
        end

        environment = FakeVSOServer.environments_created.last
        assert_equal "{\"foo\":\"bar\"}", environment["devcontainerJson"]
        assert_equal ".devcontainer/foobar/devcontainer.json", environment["devcontainerPath"]
      end

      test "it saves the devcontainer_path of the codespace to the environment options if set" do
        FakeVSOServer.reset!


        repo = create(:repository, owner: @monalisa, from_example: :simple)

        repo.refs.find(repo.default_branch).append_commit({ message: "add devcontainer json file", committer: repo.owner }, repo.owner) do |files|
          files.add(".devcontainer/baz/devcontainer.json", "{\"foo\":\"bar\"}")
        end

        codespace = create(:codespace, owner: @monalisa, repository: repo, ref: repo.default_branch, devcontainer_path: ".devcontainer/baz/devcontainer.json")

        Codespaces::VscsClient.any_instance.expects(:create_environment)
          .with(codespace.location, codespace.repository, has_entry(:environment_options, has_entry(:devcontainerPath, ".devcontainer/baz/devcontainer.json")))
          .once

        FakeKredz.with_no_secrets do
          Codespaces::CreateEnvironment.call(codespace, github_token: "")
        end
      end

      test "provisions with custom devcontainer.json path for user repo" do
        FakeVSOServer.reset!

        repo = create(:repository, owner: @monalisa, from_example: :simple)

        repo.refs.find(repo.default_branch).append_commit({ message: "add devcontainer json file", committer: repo.owner }, repo.owner) do |files|
          files.add(".devcontainer/foobar/devcontainer.json", "{\"foo\":\"bar\"}")
        end

        codespace = create(:codespace, owner: @monalisa, repository: repo, ref: repo.default_branch, devcontainer_path: ".devcontainer/foobar/devcontainer.json")

        FakeKredz.with_no_secrets do
          Codespaces::CreateEnvironment.call(codespace, github_token: "", environment_options: { devcontainerPath: ".devcontainer/foobar/devcontainer.json" })
        end

        environment = FakeVSOServer.environments_created.last
        assert_equal "{\"foo\":\"bar\"}", environment["devcontainerJson"]
      end

      test "provisions with default devcontainer.json path if one was found and sets devcontainerPath to the found config" do
        FakeVSOServer.reset!

        repo = create(:repository, owner: @monalisa, from_example: :simple)

        repo.refs.find(repo.default_branch).append_commit({ message: "add devcontainer json file", committer: repo.owner }, repo.owner) do |files|
          files.add(".devcontainer.json", "{\"foo\":\"bar\"}")
        end

        codespace = create(:codespace, owner: @monalisa, repository: repo, ref: repo.default_branch)

        FakeKredz.with_no_secrets do
          Codespaces::CreateEnvironment.call(codespace, github_token: "", environment_options: {})
        end

        environment = FakeVSOServer.environments_created.last
        assert_equal ".devcontainer.json", environment["devcontainerPath"]
        assert_equal "{\"foo\":\"bar\"}", environment["devcontainerJson"]
      end

      test "raises errors for invalid custom devcontainer paths" do
        FakeVSOServer.reset!

        repo = create(:repository, owner: @monalisa, from_example: :simple)

        dc_path = ".devcontainer/foobar/devcontainer.json"
        codespace = create(:codespace, owner: @monalisa, repository: repo, ref: repo.default_branch, devcontainer_path: dc_path)

        # file does not exist
        FakeKredz.with_no_secrets do
          assert_raises_with_message Codespaces::DevContainer::ReadError, /\.devcontainer\/foobar\/devcontainer.json does not exist in this repository/ do
            Codespaces::CreateEnvironment.call(codespace, github_token: "", environment_options: { devcontainerPath: dc_path })
          end
        end

        # invalid file path
        assert_raises_with_message ActiveRecord::RecordInvalid, /Devcontainer path is invalid/ do
          create(:codespace, owner: @monalisa, repository: repo, ref: repo.default_branch, devcontainer_path: ".devcontainer/foobar.devcontainer.json")
        end
      end

      test "does not raise errors for non-readable custom devcontainer paths" do
        FakeVSOServer.reset!

        repo = create(:repository, owner: @monalisa, from_example: :simple)

        dc_path = ".devcontainer/foobar/devcontainer.json"
        codespace = create(:codespace, owner: @monalisa, repository: repo, ref: repo.default_branch, devcontainer_path: dc_path)

        # file exists but is not valid json
        repo.refs.find(repo.default_branch).append_commit({ message: "add devcontainer json file", committer: repo.owner }, repo.owner) do |files|
          files.add(dc_path, "{")
        end
        codespace = create(:codespace, owner: @monalisa, repository: repo, ref: repo.default_branch, devcontainer_path: dc_path)

        expected_log_data = {
          "code.function" => "parse",
          "code.namespace" => "Codespaces::DevContainer",
          "gh.codespaces.devcontainer_path" => dc_path,
          "gh.repo.name_with_owner" => repo.name_with_display_owner,
          "gh.user.id" => codespace.owner_id,
        }

        FakeKredz.with_no_secrets do
          assert_logged **expected_log_data do
            Codespaces::CreateEnvironment.call(codespace, github_token: "", environment_options: { devcontainerPath: dc_path })
          end
        end
      end
    end

    context "billableOwner parameter", skip_enterprise: true do
      test "when the billable owner is an org" do
        org = create(:codespaces_organization, admin: @monalisa, plan: GitHub::Plan.business)
        repo = create(:repository, owner: org)
        codespace = create(:codespace, owner: @monalisa, repository: repo, ref: repo.default_branch)

        FakeKredz.with_no_secrets do
          Codespaces::CreateEnvironment.call(codespace, github_token: "")
        end
        environment = FakeVSOServer.environments_created.last

        refute_nil environment["billableOwner"]
        assert_equal "Organization", environment["billableOwner"]["type"]
        assert_equal org.id, environment["billableOwner"]["id"]
        assert_equal org.login, environment["billableOwner"]["login"]
      end

      test "when the billable owner is a user" do
        codespace = create(:codespace, :unprovisioned, owner: @monalisa, repository: @repo)

        FakeKredz.with_no_secrets do
          Codespaces::CreateEnvironment.call(codespace, github_token: "")
        end
        environment = FakeVSOServer.environments_created.last

        refute_nil environment["billableOwner"]
        assert_equal "User", environment["billableOwner"]["type"]
        assert_equal @monalisa.id, environment["billableOwner"]["id"]
        assert_equal @monalisa.login, environment["billableOwner"]["login"]
      end
    end

    context "secrets killswitch", skip_enterprise: true do
      test "killswitch flag disables codespaces secrets" do
        enable_feature_flag(:disable_codespaces_secrets)

        Codespaces::Secret.expects(:for_codespace).never

        FakeVSOServer.reset!

        FakeKredz.with_secrets(@user_secret) do
          Codespaces::CreateEnvironment.call(@codespace, github_token: "")
        end
      end
    end
  end
end
