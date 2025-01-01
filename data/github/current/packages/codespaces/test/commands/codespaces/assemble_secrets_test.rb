# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/secrets_test_helpers"
require "aws-sdk-ecr"

class Codespaces::AssembleSecretsTest < GitHub::TestCase
  include SecretsTestHelper

  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user)
    @github_token = "github-token"
    @codespace_token = "codespace-token"
  end

  test "it includes the default secrets", skip_enterprise: true do
    disable_feature_flag(:codespaces_no_default_dockerhub_credentials)

    secrets = Codespaces::AssembleSecrets.call(user: @user, github_token: @github_token, codespace_token: @codespace_token, repository: @repo, user_secrets: [], vscs_target_url: "https://foo.bar", vscs_target: :ppe)

    assert_secret(secrets, "GITHUB_TOKEN", @github_token)
    assert_secret(secrets, "GITHUB_CODESPACE_TOKEN", @codespace_token)
    assert_secret(secrets, "GITHUB_USER", @user.login)
    assert_secret(secrets, "GITHUB_SERVER_URL", GitHub.url)
    assert_secret(secrets, "GITHUB_API_URL", GitHub.api_url)
    assert_secret(secrets, "GITHUB_GRAPHQL_URL", GitHub.graphql_api_url)
    assert_secret(secrets, "GITHUB_REPOSITORY", @repo.name_with_owner)
    assert_secret(secrets, "INTERNAL_VSCS_TARGET_URL", "https://foo.bar")
    target_config = Codespaces::Vscs.config_for_target(:ppe)
    assert_secret(secrets, "GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN", Codespaces::Vscs.dev_tunnels_domain_for_target(:ppe))

    dockerhub_name = "#{GitHub.codespaces_dockerhub_registry[:username]}@#{GitHub.codespaces_dockerhub_registry[:url]}"
    dockerhub_value = GitHub.codespaces_dockerhub_registry[:password]
    assert_secret(secrets, dockerhub_name, dockerhub_value, type: Codespaces::Secret::TYPE_CONTAINER_REGISTRY)
  end

  test "it does not include github_token and codespace_token if not passed", skip_enterprise: true do
    disable_feature_flag(:codespaces_no_default_dockerhub_credentials)

    secrets = Codespaces::AssembleSecrets.call(user: @user, github_token: nil, codespace_token: nil, repository: @repo, user_secrets: [], vscs_target_url: "https://foo.bar")

    refute_secret(secrets, "GITHUB_TOKEN", type: Codespaces::Secret::TYPE_ENV_VAR)
    refute_secret(secrets, "GITHUB_CODESPACE_TOKEN", type: Codespaces::Secret::TYPE_ENV_VAR)

    assert_secret(secrets, "GITHUB_USER", @user.login)
    assert_secret(secrets, "GITHUB_SERVER_URL", GitHub.url)
    assert_secret(secrets, "GITHUB_API_URL", GitHub.api_url)
    assert_secret(secrets, "GITHUB_GRAPHQL_URL", GitHub.graphql_api_url)
    assert_secret(secrets, "GITHUB_REPOSITORY", @repo.name_with_owner)
    assert_secret(secrets, "INTERNAL_VSCS_TARGET_URL", "https://foo.bar")

    dockerhub_name = "#{GitHub.codespaces_dockerhub_registry[:username]}@#{GitHub.codespaces_dockerhub_registry[:url]}"
    dockerhub_value = GitHub.codespaces_dockerhub_registry[:password]
    assert_secret(secrets, dockerhub_name, dockerhub_value, type: Codespaces::Secret::TYPE_CONTAINER_REGISTRY)
  end

  test "it does not include GIT_COMMITTER secrets when gpg is disabled", skip_enterprise: true do
    @user.stubs(:gpg_authorization).returns(Configurable::GpgAuthorization::DISABLED)
    secrets = Codespaces::AssembleSecrets.call(user: @user, github_token: @github_token, codespace_token: @codespace_token, repository: @repo, user_secrets: [], vscs_target_url: "https://foo.bar")

    refute_secret(secrets, "GIT_COMMITTER_NAME", type: Codespaces::Secret::TYPE_ENV_VAR)
    refute_secret(secrets, "GIT_COMMITTER_EMAIL", type: Codespaces::Secret::TYPE_ENV_VAR)
  end

  test "it includes GIT_COMMITTER secrets when gpg is enabled for all repositories", skip_enterprise: true do
    @user.stubs(:gpg_authorization).returns(Configurable::GpgAuthorization::ALL_REPOSITORIES)
    secrets = Codespaces::AssembleSecrets.call(user: @user, github_token: @github_token, codespace_token: @codespace_token, repository: @repo, user_secrets: [], vscs_target_url: "https://foo.bar")

    assert_secret(secrets, "GIT_COMMITTER_NAME", GitHub.web_committer_name)
    assert_secret(secrets, "GIT_COMMITTER_EMAIL", GitHub.web_committer_email)
  end

  test "it includes GIT_COMMITTER secrets when gpg is enabled to all repositories", skip_enterprise: true do
    @user.stubs(:gpg_authorization).returns(Configurable::GpgAuthorization::ENABLED)
    @user.update_codespaces_repository_authorization(Configurable::CodespacesRepositoryAuthorization::ALL_REPOSITORIES, actor: @user)
    secrets = Codespaces::AssembleSecrets.call(user: @user, github_token: @github_token, codespace_token: @codespace_token, repository: @repo, user_secrets: [], vscs_target_url: "https://foo.bar")

    assert_secret(secrets, "GIT_COMMITTER_NAME", GitHub.web_committer_name)
    assert_secret(secrets, "GIT_COMMITTER_EMAIL", GitHub.web_committer_email)
  end

  test "it includes GIT_COMMITTER secrets when gpg is enabled to selected trusted repositories", skip_enterprise: true do
    @user.stubs(:gpg_authorization).returns(Configurable::GpgAuthorization::ENABLED)
    @user.update_codespaces_repository_authorization(Configurable::CodespacesRepositoryAuthorization::SELECTED_REPOSITORIES, actor: @user)

    trusted_repository_authorizations_mock = mock
    trusted_repository_authorizations_mock.stubs(:find_by).returns(true)
    @user.stubs(:trusted_repository_authorizations).returns(trusted_repository_authorizations_mock)

    secrets = Codespaces::AssembleSecrets.call(user: @user, github_token: @github_token, codespace_token: @codespace_token, repository: @repo, user_secrets: [], vscs_target_url: "https://foo.bar")

    assert_secret(secrets, "GIT_COMMITTER_NAME", GitHub.web_committer_name)
    assert_secret(secrets, "GIT_COMMITTER_EMAIL", GitHub.web_committer_email)
  end

  test "it does not include GIT_COMMITTER secrets when gpg is enabled but the repository is not trusted", skip_enterprise: true do
    @user.update_codespaces_repository_authorization(Configurable::CodespacesRepositoryAuthorization::SELECTED_REPOSITORIES, actor: @user)

    secrets = Codespaces::AssembleSecrets.call(user: @user, github_token: @github_token, codespace_token: @codespace_token, repository: @repo, user_secrets: [], vscs_target_url: "https://foo.bar")

    refute_secret(secrets, "GIT_COMMITTER_NAME", type: Codespaces::Secret::TYPE_ENV_VAR)
    refute_secret(secrets, "GIT_COMMITTER_EMAIL", type: Codespaces::Secret::TYPE_ENV_VAR)
  end

  test "it includes GIT_COMMITTER secrets when gpg is enabled for selected repositories including current", skip_enterprise: true do
    @user.stubs(:gpg_authorization).returns(Configurable::GpgAuthorization::SELECTED_REPOSITORIES)
    trusted_repository_authorizations_mock = mock
    trusted_repository_authorizations_mock.stubs(:find_by).returns(true)
    @user.stubs(:trusted_repository_authorizations).returns(trusted_repository_authorizations_mock)
    secrets = Codespaces::AssembleSecrets.call(user: @user, github_token: @github_token, codespace_token: @codespace_token, repository: @repo, user_secrets: [], vscs_target_url: "https://foo.bar")

    assert_secret(secrets, "GIT_COMMITTER_NAME", GitHub.web_committer_name)
    assert_secret(secrets, "GIT_COMMITTER_EMAIL", GitHub.web_committer_email)
  end

  test "it does not include GIT_COMMITTER secrets when gpg is enabled for selected repositories but NOT including current", skip_enterprise: true do
    @user.stubs(:gpg_authorization).returns(Configurable::GpgAuthorization::SELECTED_REPOSITORIES)
    trusted_repository_authorizations_mock = mock
    trusted_repository_authorizations_mock.stubs(:find_by).with(repository: @repo).returns(false)
    @user.stubs(:trusted_repository_authorizations).returns(trusted_repository_authorizations_mock)
    secrets = Codespaces::AssembleSecrets.call(user: @user, github_token: @github_token, codespace_token: @codespace_token, repository: @repo, user_secrets: [], vscs_target_url: "https://foo.bar")

    refute_secret(secrets, "GIT_COMMITTER_NAME", type: Codespaces::Secret::TYPE_ENV_VAR)
    refute_secret(secrets, "GIT_COMMITTER_EMAIL", type: Codespaces::Secret::TYPE_ENV_VAR)
  end

  test "it passes env vars through", skip_enterprise: true do
    secrets = Codespaces::AssembleSecrets.call(user: @user, github_token: @github_token, codespace_token: @codespace_token, repository: @repo, vscs_target_url: "", user_secrets: [
      Codespaces::Secret.new("MY_SECRETS_DEFINE_ME", encrypt_with_owner_next_global_id("some-value", @user), @user),
    ])

    assert_secret(secrets, "MY_SECRETS_DEFINE_ME", "some-value")
  end

  test "it doesn't require a codespace_token", skip_enterprise: true do
    secrets = Codespaces::AssembleSecrets.call(user: @user, github_token: @github_token, codespace_token: nil, repository: @repo, user_secrets: [], vscs_target_url: "")

    refute_secret(secrets, "GITHUB_CODESPACE_TOKEN")
  end

  test "it doesn't require a user", skip_enterprise: true do
    secrets = Codespaces::AssembleSecrets.call(user: nil, github_token: @github_token, codespace_token: @codespace_token, repository: @repo, user_secrets: [], vscs_target_url: "")

    refute_secret(secrets, "GITHUB_USER")
  end

  test "it passes an empty GITHUB_REPOSITORY if the repository is nil", skip_enterprise: true do
    secrets = Codespaces::AssembleSecrets.call(user: @user, github_token: @github_token, codespace_token: @codespace_token, repository: nil, vscs_target_url: "")

    assert_secret(secrets, "GITHUB_REPOSITORY", " ")
  end

  test "it parses container registry secrets", skip_enterprise: true do
    secrets = Codespaces::AssembleSecrets.call(user: @user, github_token: @github_token, codespace_token: @codespace_token, repository: @repo, vscs_target_url: "", user_secrets: [
      Codespaces::Secret.new("ACR_CONTAINER_REGISTRY_SERVER", encrypt_with_owner_next_global_id("myregistry.azurecr.io", @user), @user),
      Codespaces::Secret.new("ACR_CONTAINER_REGISTRY_USER", encrypt_with_owner_next_global_id("test-user", @user), @user),
      Codespaces::Secret.new("ACR_CONTAINER_REGISTRY_PASSWORD", encrypt_with_owner_next_global_id("test-password", @user), @user),
    ])

    secret_name = "test-user@myregistry.azurecr.io"
    assert_secret(secrets, secret_name, "test-password", type: Codespaces::Secret::TYPE_CONTAINER_REGISTRY)
  end

  test "it includes GHCR credentials", skip_enterprise: true do
    stub_path = "stub.github.com"
    GitHub.urls.stubs(:registry_host_name).returns(stub_path)

    secrets = Codespaces::AssembleSecrets.call(user: @user, github_token: @github_token, codespace_token: @codespace_token, repository: @repo, user_secrets: [], vscs_target_url: "")

    assert_secret(secrets, "#{@user.login}@#{stub_path}", @github_token, type: Codespaces::Secret::TYPE_CONTAINER_REGISTRY)
  end

  test "it includes correct GHCR domain name in credentials for Proxima", skip_enterprise: true do
    proxima_user = create(:emu)
    business = proxima_user.enterprise_managed_business
    repo = create(:repository, owner: proxima_user)

    on_multi_tenant_enterprise(tenant: business) do
      stub_path = "stub.github.com"
      GitHub::UrlBuilder.any_instance.stubs(:registry_host_name).returns(stub_path)

      secrets = Codespaces::AssembleSecrets.call(user: proxima_user, github_token: @github_token, codespace_token: @codespace_token, repository: repo, user_secrets: [], vscs_target_url: "")

      assert_secret(secrets, "#{proxima_user.display_login}@#{stub_path}", @github_token, type: Codespaces::Secret::TYPE_CONTAINER_REGISTRY)
    end
  end

  test "it includes GHCR credentials without a user", skip_enterprise: true do
    stub_path = "stub.github.com"
    GitHub.urls.stubs(:registry_host_name).returns(stub_path)

    secrets = Codespaces::AssembleSecrets.call(user: nil, github_token: @github_token, codespace_token: @codespace_token, repository: @repo, user_secrets: [], vscs_target_url: "")

    assert_secret(secrets, stub_path, @github_token, type: Codespaces::Secret::TYPE_CONTAINER_REGISTRY)
  end

  test "it does not override user-provided Docker Hub credentials", skip_enterprise: true do
    secrets = Codespaces::AssembleSecrets.call(user: @user, github_token: @github_token, codespace_token: @codespace_token, repository: @repo, vscs_target_url: "", user_secrets: [
      Codespaces::Secret.new("DOCKERHUB_CONTAINER_REGISTRY_SERVER", encrypt_with_owner_next_global_id(GitHub.codespaces_dockerhub_registry[:url], @user), @user),
      Codespaces::Secret.new("DOCKERHUB_CONTAINER_REGISTRY_USER", encrypt_with_owner_next_global_id("test-user", @user), @user),
      Codespaces::Secret.new("DOCKERHUB_CONTAINER_REGISTRY_PASSWORD", encrypt_with_owner_next_global_id("test-password", @user), @user),
    ])

    dockerhub_secrets = secrets.select { |secret| secret[:name].ends_with?(GitHub.codespaces_dockerhub_registry[:url]) && secret[:type] == Codespaces::Secret::TYPE_CONTAINER_REGISTRY }
    assert_equal 1, dockerhub_secrets.length
    assert_equal "test-user@#{GitHub.codespaces_dockerhub_registry[:url]}", dockerhub_secrets.first[:name]
    assert_equal "test-password", dockerhub_secrets.first[:value]
  end

  test "it does not provide Docker Hub credentials if no default credentials flag is enabled", skip_enterprise: true do
    enable_feature_flag(:codespaces_no_default_dockerhub_credentials)

    secrets = Codespaces::AssembleSecrets.call(user: @user, github_token: @github_token, codespace_token: @codespace_token, repository: @repo, vscs_target_url: "", user_secrets: [])

    dockerhub_secrets = secrets.select { |secret| secret[:name].ends_with?(GitHub.codespaces_dockerhub_registry[:url]) && secret[:type] == Codespaces::Secret::TYPE_CONTAINER_REGISTRY }
    assert_equal 0, dockerhub_secrets.length
  end

  test "it integrates with AWS ECR", skip_enterprise: true do
    server = "abc.dkr.ecr.us-east-1.amazonaws.com"
    Aws::ECR::Types::AuthorizationData.any_instance.stubs(:authorization_token).returns(
      Base64.encode64("some-user:some-password"),
    )
    Seahorse::Client::Response.any_instance.stubs(:authorization_data).returns([
      Aws::ECR::Types::AuthorizationData.new,
    ])
    Aws::ECR::Client.any_instance.stubs(:get_authorization_token).returns(Seahorse::Client::Response.new)
    secrets = Codespaces::AssembleSecrets.call(user: @user, github_token: @github_token, codespace_token: @codespace_token, repository: @repo, vscs_target_url: "", user_secrets: [
      Codespaces::Secret.new("ECR_CONTAINER_REGISTRY_SERVER", encrypt_with_owner_next_global_id(server, @user), @user),
      Codespaces::Secret.new("ECR_CONTAINER_REGISTRY_USER", encrypt_with_owner_next_global_id("access-key", @user), @user),
      Codespaces::Secret.new("ECR_CONTAINER_REGISTRY_PASSWORD", encrypt_with_owner_next_global_id("secret-key", @user), @user),
    ])

    assert_secret(secrets, "AWS@#{server}", "some-password", type: Codespaces::Secret::TYPE_CONTAINER_REGISTRY)
  end

  test "it turns zero-length values into 1 length values", skip_enterprise: true do
    secrets = Codespaces::AssembleSecrets.call(user: @user, github_token: @github_token, codespace_token: @codespace_token, repository: @repo, vscs_target_url: "", user_secrets: [
      Codespaces::Secret.new("MY_SECRETS_DEFINE_ME", encrypt_with_owner_next_global_id("", @user), @user),
    ])

    assert_secret(secrets, "MY_SECRETS_DEFINE_ME", " ")
  end

  def assert_secret(secrets, name, value, type: Codespaces::Secret::TYPE_ENV_VAR)
    refute_nil secrets.find { |secret| secret[:name] == name && secret[:value] == value && secret[:type] == type }
  end

  def refute_secret(secrets, name, type: Codespaces::Secret::TYPE_ENV_VAR)
    assert_nil secrets.find { |secret| secret[:name] == name && secret[:type] == type }
  end
end
