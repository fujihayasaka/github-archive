# typed: true
# frozen_string_literal: true

require "github-kredz"
require "test_helper"
require "test_helpers/fake_kredz_response"

class SecretsTest < GitHub::TestCase
  include DogstatsTestHelpers

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @owner = create(:user)
    @installed_github_app = create(:integration, default_permissions: { "checks" => :write }, name: "Great App", owner: @owner, url: "http://great-app.com")

    @org = create(:business_organization, admin: @owner)
    @org_member = create(:user)
    @org.add_member(@org_member)

    @repo = create(:private_repository, owner: @owner)
    @org_repo = create(:repository, owner: @org)

    @rando = create(:user)
    @rando_github_app = create(:integration, default_permissions: { "checks" => :write }, name: "Another App", owner: @owner, url: "http://another-app.com")

    @repository_secrets = [
        GitHub::Launch::Services::Credz::Credential.new(name: "1234"),
        GitHub::Launch::Services::Credz::Credential.new(name: "foobaz"),
        GitHub::Launch::Services::Credz::Credential.new(name: "override"),
    ]

    @organization_secrets = [
      GitHub::Launch::Services::Credz::Credential.new(name: "override"),
      GitHub::Launch::Services::Credz::Credential.new(name: "org-secret"),
    ]

    @repository_secrets_with_value = [
      GitHub::Launch::Services::Credz::Credential.new(name: "1234", value: "repo-secret-1"),
      GitHub::Launch::Services::Credz::Credential.new(name: "foobaz", value: "repo-secret-2"),
      GitHub::Launch::Services::Credz::Credential.new(name: "override", value: "repo-secret-3"),
    ]

    @organization_secrets_with_value = [
      GitHub::Launch::Services::Credz::Credential.new(name: "override", value: "org-secret-1"),
      GitHub::Launch::Services::Credz::Credential.new(name: "org-secret", value: "org-secret-2"),
    ]

    env = create(:environment, name: "PROD", repository: @repo)
    cred_owner = GitHub::Launch::Services::Credz::CredentialOwner.new(
      environment: GitHub::Launch::Services::Credz::Environment.new(
        global_id: env.global_relay_id,
        repository_id: env.repository.id,
        new_global_id: GitHub.enterprise? ? env.global_relay_id : env.next_global_id,
      ),
    )

    @environment_secrets = [
      GitHub::Launch::Services::Credz::Credential.new(name: "ENV_SECRET_1", owner: cred_owner)
    ]

    @key_name = "custom-tasks-key"
  end

  setup do
    Failbot.reports.clear
  end

  context "#github_public_key", skip_enterprise: true do
    test "returns key and id scoped to given owner for given key_name" do
      id, public_key = Secrets.github_public_key(owner: @owner, key_name: @key_name)

      refute_nil id
      refute_empty public_key
    end

    test "Returns blank key and id if diet earthsmoke key export fails" do
      DietEarthsmoke::Key.expects(:new)
        .raises(DietEarthsmoke::KeyParseError.new("Unable to parse key"))

      id, public_key = Secrets.github_public_key(owner: @owner, key_name: @key_name)

      assert_empty id
      assert_empty public_key
    end
  end

  context "#embed", skip_enterprise: true do
    test "embeds secrets" do
      expected = String.new(
        "\x02" +
        "\xDE\xAD\xBE\xEF\xDE\xAD\xBE\xEF" +
        "\x68\x65\x6c\x6c\x6f\x2c\x20\x77\x6f\x72\x6c\x64",
        encoding: Encoding::ASCII_8BIT
      )
      assert_equal expected, Secrets.embed(0xDEADBEEFDEADBEEF, "hello, world")
    end
  end

  context "#for_app with Kredz" do
    test "returns secrets for a given integration and owner" do
      GitHub::KredzClient::Credz.expects(:list_credentials)
        .with(app: @installed_github_app, owner: @org, actor: @org_member)
        .returns(build_kredz_response(GitHub::Launch::Services::Credz::ListResponse.new(credentials: @organization_secrets)))

      secrets = Secrets.for_app(@installed_github_app, owner: @org, actor: @org_member)
      assert @organization_secrets.all? { |s| secrets.include?(s) }
    end

    test "raises exception if Credz call fails" do
      GitHub::KredzClient::Credz.expects(:list_credentials)
        .with(app: @installed_github_app, owner: @org, actor: @org_member)
        .returns(build_kredz_response({}, error_code: :unavailable, error_message: "Service unavailable"))

      exception = assert_raises Secrets::Error do
        Secrets.for_app(@installed_github_app, owner: @org, actor: @org_member)
      end

      assert_equal "Secrets service unavailable", exception.message
    end

    test "returns empty list if no secrets exist for the given integration and owner" do
      GitHub::KredzClient::Credz.expects(:list_credentials)
        .with(app: @rando_github_app, owner: @rando, actor: @rando)
        .returns(build_kredz_response(GitHub::Launch::Services::Credz::ListResponse.new(credentials: [])))

      secrets = Secrets.for_app(@rando_github_app, owner: @rando, actor: @rando)
      assert_empty secrets
    end
  end

  context "#for_repository with Kredz" do
    test "returns secrets for a given org, repo and integration" do
      GitHub::KredzClient::Credz.expects(:list_repository_secrets)
        .with(app: @installed_github_app, repository: @org_repo, actor: @org_member, environments: [], include_value: false)
        .returns(build_kredz_response(GitHub::Launch::Services::Credz::ListSecretsForRepositoryResponse.new(
          repository_secrets: @repository_secrets,
          organization_secrets: @organization_secrets,
          environment_secrets: @environment_secrets,
        )))

      secrets = Secrets.for_repository(@org_repo, actor: @org_member, app: @installed_github_app)

      assert secrets.key? :repository_secrets
      assert secrets.key? :organization_secrets

      assert @organization_secrets.all? { |s| secrets[:organization_secrets].map { |h| h[:name] }.include?(s.name) }
      assert @repository_secrets.all? { |s| secrets[:repository_secrets].map { |h| h[:name] }.include?(s.name) }
      assert @environment_secrets.all? { |s| secrets[:environment_secrets].map { |h| h[:name] }.include?(s.name) }
    end

    test "returns secrets for a given org, repo and integration with included values" do
      GitHub::KredzClient::Credz.expects(:list_repository_secrets)
        .with(app: @installed_github_app, repository: @org_repo, actor: @org_member, environments: [], include_value: true)
        .returns(build_kredz_response(GitHub::Launch::Services::Credz::ListSecretsForRepositoryResponse.new(
          repository_secrets: @repository_secrets_with_value,
          organization_secrets: @organization_secrets_with_value,
          environment_secrets: [],
        )))

      secrets = Secrets.for_repository(@org_repo, actor: @org_member, app: @installed_github_app, include_value: true)

      assert secrets.key? :repository_secrets
      assert secrets.key? :organization_secrets

      assert @repository_secrets_with_value.all? { |s| secrets[:repository_secrets].map { |h| h[:name] }.include?(s.name) }
      assert @organization_secrets_with_value.all? { |s| secrets[:organization_secrets].map { |h| h[:name] }.include?(s.name) }
    end

    test "raises exception if Credz call fails" do
      GitHub::KredzClient::Credz.expects(:list_repository_secrets)
        .with(app: @installed_github_app, repository: @org_repo, actor: @org_member, environments: [], include_value: false)
        .returns(build_kredz_response({}, error_code: :unavailable, error_message: "Service unavailable"))

      exception = assert_raises Secrets::Error do
        Secrets.for_repository(@org_repo, actor: @org_member, app: @installed_github_app)
      end

      assert_equal "Secrets service unavailable", exception.message
    end
  end

  context "#secret_count_for_environments with Kredz" do
    test "handles no environments without credz" do
      @repo.stubs(:can_use_environments?).returns(false)
      secret_counts = Secrets.secret_count_for_environments(@repo, app: @installed_github_app, environments: @repo.environments)
      assert_empty secret_counts
    end

    test "returns secret counts" do
      repo_with_env = create(:repository, owner: @owner)
      repo_with_env.stubs(:can_use_environments?).returns(true)
      env = create(:environment, name: "Staging", repository: repo_with_env)

      env_global_id = GitHub.enterprise? ? env.global_relay_id : env.next_global_id
      counts_response = [
        GitHub::Launch::Services::Credz::SecretCount.new(owner_global_id: env_global_id, owner_next_global_id: env_global_id, count: 3),
      ]

      GitHub::KredzClient::Credz.expects(:get_secret_counts)
        .with(app: @installed_github_app, owner_ids: [env_global_id], owner_type: GitHub::KredzClient::Credz::CREDENTIAL_OWNER_ENVIRONMENT_TYPE)
        .returns(build_kredz_response(GitHub::Launch::Services::Credz::SecretCountsResponse.new(
          secret_counts: counts_response,
        )))

      secret_counts = Secrets.secret_count_for_environments(repo_with_env, app: @installed_github_app, environments: repo_with_env.environments)
      assert_equal 1, secret_counts.size
      assert_equal env.global_relay_id, secret_counts[0].owner_global_id
      assert_equal 3, secret_counts[0].count
    end
  end

  context "#fetch with Kredz" do
    test "fetches a secret" do
      GitHub::KredzClient::Credz.expects(:fetch_credential)
        .with(key: "org-secret", app: @installed_github_app, owner: @org, actor: @org_member, include_value: false)
        .returns(
          build_kredz_response(GitHub::Launch::Services::Credz::FetchResponse.new(
            credential: GitHub::Launch::Services::Credz::Credential.new(name: "org-secret")
          ))
        )

      Secrets.fetch(name: "org-secret", app: @installed_github_app, owner: @org, actor: @org_member)
    end

    test "records metrics about the fetch" do
      GitHub::KredzClient::Credz.expects(:fetch_credential)
        .with(key: "org-secret", app: @installed_github_app, owner: @org, actor: @org_member, include_value: false)
        .returns(
          build_kredz_response(GitHub::Launch::Services::Credz::FetchResponse.new(
            credential: GitHub::Launch::Services::Credz::Credential.new(name: "org-secret")
          ))
        )

      Secrets.fetch(name: "org-secret", app: @installed_github_app, owner: @org, actor: @org_member)

      assert_dogstats_timing(1, "secrets.kredz.fetch", tags: ["app:#{@installed_github_app.name}", "status:200", "succeeded:true"])
    end
  end

  context "#update with Kredz" do
    test "updates a secret" do
      GitHub::KredzClient::Credz.expects(:update_credential)
        .with(
          app: @installed_github_app,
          owner: @org,
          actor: @org_member,
          key: "org-secret",
          value: "",
          visibility: GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_SELECTED_REPOS,
          selected_repositories: [@org_repo],
        )
        .returns(
          build_kredz_response(GitHub::Launch::Services::Credz::UpdateResponse.new(
            credential: GitHub::Launch::Services::Credz::Credential.new(name: "org-secret")
          ))
        )

      GlobalInstrumenter.expects(:instrument).with("org_secret.update", {
        app: @installed_github_app,
        owner: @org,
        actor: @org_member,
        name: "org-secret",
        selected_repositories: [@org_repo],
        state: "UPDATED",
      }).once

      Secrets.update(
        name: "org-secret",
        app: @installed_github_app,
        owner: @org,
        actor: @org_member,
        visibility: GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_SELECTED_REPOS,
        selected_repositories: [@org_repo],
      )
    end

    test "records metrics about the update" do
      GitHub::KredzClient::Credz.expects(:update_credential)
        .with(
          app: @installed_github_app,
          owner: @org,
          actor: @org_member,
          key: "org-secret",
          value: "",
          visibility: GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_SELECTED_REPOS,
          selected_repositories: [@org_repo],
        )
        .returns(
          build_kredz_response(GitHub::Launch::Services::Credz::UpdateResponse.new(
            credential: GitHub::Launch::Services::Credz::Credential.new(name: "org-secret")
          ))
        )

      Secrets.update(
        name: "org-secret",
        app: @installed_github_app,
        owner: @org,
        actor: @org_member,
        visibility: GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_SELECTED_REPOS,
        selected_repositories: [@org_repo],
      )

      assert_dogstats_timing(1, "secrets.kredz.update", tags: ["app:#{@installed_github_app.name}", "status:200", "succeeded:true"])
    end
  end

  context "#store with Kredz" do
    test "stores a secret" do
      GitHub::KredzClient::Credz.expects(:store_credential)
        .with(
          app: @installed_github_app,
          owner: @org,
          actor: @org_member,
          key: "org-secret",
          value: "some-secret",
          visibility: GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_SELECTED_REPOS,
          selected_repositories: [@org_repo],
        )
        .returns(
          build_kredz_response(GitHub::Launch::Services::Credz::UpdateResponse.new(
            credential: GitHub::Launch::Services::Credz::Credential.new(name: "org-secret")
          ))
        )

      GlobalInstrumenter.expects(:instrument).with("org_secret.create", {
        app: @installed_github_app,
        owner: @org,
        actor: @org_member,
        name: "org-secret",
        selected_repositories: [@org_repo],
        state: "CREATED",
      }).once

      Secrets.store(
        name: "org-secret",
        app: @installed_github_app,
        owner: @org,
        actor: @org_member,
        value: "some-secret",
        visibility: GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_SELECTED_REPOS,
        selected_repositories: [@org_repo],
      )
    end

    test "records metrics about the store" do
      GitHub::KredzClient::Credz.expects(:store_credential)
        .with(
          app: @installed_github_app,
          owner: @org,
          actor: @org_member,
          key: "org-secret",
          value: "some-secret",
          visibility: GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_SELECTED_REPOS,
          selected_repositories: [@org_repo],
        )
        .returns(
          build_kredz_response(GitHub::Launch::Services::Credz::UpdateResponse.new(
            credential: GitHub::Launch::Services::Credz::Credential.new(name: "org-secret")
          ))
        )

      Secrets.store(
        name: "org-secret",
        app: @installed_github_app,
        owner: @org,
        actor: @org_member,
        value: "some-secret",
        visibility: GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_SELECTED_REPOS,
        selected_repositories: [@org_repo],
      )

      assert_dogstats_timing(1, "secrets.kredz.store", tags: ["app:#{@installed_github_app.name}", "status:200", "succeeded:true"])
    end

    test "already_exists errors not logged to sentry" do
      GitHub::KredzClient::Credz.stubs(:store_credential).returns(build_kredz_response({}, error_code: :already_exists, error_message: "Secret already exists"))

      exception = assert_raises Secrets::Error do
        Secrets.store(
          name: "org-secret",
          app: @installed_github_app,
          owner: @org,
          actor: @org_member,
          value: "some-secret",
          visibility: GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_SELECTED_REPOS,
          selected_repositories: [@org_repo],
        )
      end

      assert_equal "Already exists - Secret already exists", exception.message
      assert_equal 0, Failbot.reports.size
    end

    test "out_of_range errors not logged to sentry" do
      GitHub::KredzClient::Credz.stubs(:store_credential).returns(build_kredz_response({}, error_code: :out_of_range, error_message: "Failed to add secret, cannot have more than 100 secrets"))

      exception = assert_raises Secrets::Error do
        Secrets.store(
          name: "org-secret",
          app: @installed_github_app,
          owner: @org,
          actor: @org_member,
          value: "some-secret",
          visibility: GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_SELECTED_REPOS,
          selected_repositories: [@org_repo],
        )
      end

      assert_equal "Secrets::Error", exception.message
      assert_equal 0, Failbot.reports.size
    end
  end

  context "#create with Kredz" do
    test "already_exists errors not logged to sentry" do
      GitHub::KredzClient::Credz.stubs(:create_credential).returns(build_kredz_response({}, error_code: :already_exists, error_message: "Secret already exists"))

      exception = assert_raises Secrets::Error do
        Secrets.create(
          name: "org-secret",
          app: @installed_github_app,
          owner: @org,
          actor: @org_member,
          value: "some-secret",
          visibility: GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_SELECTED_REPOS,
          selected_repositories: [@org_repo],
        )
      end

      assert_equal "Already exists - Secret already exists", exception.message
      assert_equal 0, Failbot.reports.size
    end

    test "out_of_range errors not logged to sentry" do
      GitHub::KredzClient::Credz.stubs(:create_credential).returns(build_kredz_response({}, error_code: :out_of_range, error_message: "Failed to add secret, cannot have more than 100 secrets"))

      exception = assert_raises Secrets::Error do
        Secrets.create(
          name: "org-secret",
          app: @installed_github_app,
          owner: @org,
          actor: @org_member,
          value: "some-secret",
          visibility: GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_SELECTED_REPOS,
          selected_repositories: [@org_repo],
        )
      end

      assert_equal "Secrets::Error", exception.message
      assert_equal 0, Failbot.reports.size
    end
  end

  context "#delete with Kredz" do
    test "deletes a secret" do
      GitHub::KredzClient::Credz.expects(:delete_credential)
        .with(key: "org-secret", app: @installed_github_app, owner: @org, actor: @org_member)
        .returns(
          build_kredz_response(GitHub::Launch::Services::Credz::DeleteResponse.new(success: true))
        )

      GlobalInstrumenter.expects(:instrument).with("org_secret.remove", {
        app: @installed_github_app,
        owner: @org,
        actor: @org_member,
        name: "org-secret",
        selected_repositories: [],
        state: "DELETED",
      }).once

      Secrets.delete(name: "org-secret", app: @installed_github_app, owner: @org, actor: @org_member)
    end

    test "records metrics about the delete" do
      GitHub::KredzClient::Credz.expects(:delete_credential)
        .with(key: "org-secret", app: @installed_github_app, owner: @org, actor: @org_member)
        .returns(
          build_kredz_response(GitHub::Launch::Services::Credz::DeleteResponse.new(success: true))
        )

      Secrets.delete(name: "org-secret", app: @installed_github_app, owner: @org, actor: @org_member)

      assert_dogstats_timing(1, "secrets.kredz.delete", tags: ["app:#{@installed_github_app.name}", "status:200", "succeeded:true"])
    end
  end

  context "#list with Kredz" do
    test "lists secrets" do
      GitHub::KredzClient::Credz.expects(:list_credentials)
        .with(app: @installed_github_app, owner: @org, actor: @org_member)
        .returns(build_kredz_response(GitHub::Launch::Services::Credz::ListResponse.new(credentials: @organization_secrets)))

      secrets = Secrets.list(app: @installed_github_app, owner: @org, actor: @org_member)
      assert @organization_secrets.all? { |s| secrets.credentials.include?(s) }
    end

    test "records metrics about the list" do
      GitHub::KredzClient::Credz.expects(:list_credentials)
        .with(app: @installed_github_app, owner: @org, actor: @org_member)
        .returns(build_kredz_response(GitHub::Launch::Services::Credz::ListResponse.new(credentials: @organization_secrets)))

      secrets = Secrets.list(app: @installed_github_app, owner: @org, actor: @org_member)
      assert @organization_secrets.all? { |s| secrets.credentials.include?(s) }

      assert_dogstats_timing(1, "secrets.kredz.list", tags: ["app:#{@installed_github_app.name}", "status:200", "succeeded:true"])
    end
  end

  context "#list_repository with Kredz" do
    test "lists secrets for a repository" do
      GitHub::KredzClient::Credz.expects(:list_repository_secrets)
        .with(app: @installed_github_app, repository: @org_repo, environments: Environment.none, actor: @org_member, include_value: false)
        .returns(build_kredz_response(GitHub::Launch::Services::Credz::ListSecretsForRepositoryResponse.new(
          repository_secrets: @repository_secrets,
          organization_secrets: @organization_secrets,
          environment_secrets: @environment_secrets,
        )))

      secrets = Secrets.list_repository(app: @installed_github_app, repository: @org_repo, environments: Environment.none, actor: @org_member)

      assert @organization_secrets.all? { |s| secrets.organization_secrets.include?(s) }
      assert @repository_secrets.all? { |s| secrets.repository_secrets.include?(s) }
      assert @environment_secrets.all? { |s| secrets.environment_secrets.include?(s) }
    end

    test "lists secrets for a repository with included values" do
      GitHub::KredzClient::Credz.expects(:list_repository_secrets)
        .with(app: @installed_github_app, repository: @org_repo, environments: Environment.none, actor: @org_member, include_value: true)
        .returns(build_kredz_response(GitHub::Launch::Services::Credz::ListSecretsForRepositoryResponse.new(
          repository_secrets: @repository_secrets_with_value,
          organization_secrets: @organization_secrets_with_value,
          environment_secrets: [],
        )))

      secrets = Secrets.list_repository(app: @installed_github_app, repository: @org_repo, environments: Environment.none, actor: @org_member, include_value: true)

      assert @organization_secrets_with_value.all? { |s| secrets.organization_secrets.include?(s) }
      assert @repository_secrets_with_value.all? { |s| secrets.repository_secrets.include?(s) }
    end

    test "records metrics about the list for repository" do
      GitHub::KredzClient::Credz.expects(:list_repository_secrets)
        .with(app: @installed_github_app, repository: @org_repo, environments: Environment.none, actor: @org_member, include_value: false)
        .returns(build_kredz_response(GitHub::Launch::Services::Credz::ListSecretsForRepositoryResponse.new(
          repository_secrets: @repository_secrets,
          organization_secrets: @organization_secrets,
          environment_secrets: @environment_secrets,
        )))

      secrets = Secrets.list_repository(app: @installed_github_app, repository: @org_repo, environments: Environment.none, actor: @org_member)

      assert @organization_secrets.all? { |s| secrets.organization_secrets.include?(s) }
      assert @repository_secrets.all? { |s| secrets.repository_secrets.include?(s) }
      assert @environment_secrets.all? { |s| secrets.environment_secrets.include?(s) }

      assert_dogstats_timing(1, "secrets.kredz.list_repository", tags: ["app:#{@installed_github_app.name}", "status:200", "succeeded:true"])
    end
  end

  def build_kredz_response(resp, error_code: nil, error_message: nil)
    FakeKredzResponse.new(data: resp, error_code: error_code, error_message: error_message)
  end
end
