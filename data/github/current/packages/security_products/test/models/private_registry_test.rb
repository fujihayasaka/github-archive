# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/fake_kredz"
require "test_helpers/secrets_test_helpers"
require_relative "../../app/models/private_registry"

class PrivateRegistryTest < GitHub::TestCase
  include SecretsTestHelper

  fixtures do
    make_trusted_oauth_apps_owner
    @app = create(:private_registry_secrets_integration)

    @org1 = create(:organization)
    @org1_repo1 = create(:private_repository, owner: @org1)
    @org1_repo2 = create(:private_repository, owner: @org1)
    @org1_config1 = create(
      :private_registry_configuration,
      url: "https://maven.pkg.github.com/org1/repo1",
      owner_id: @org1.id,
      username: "maven_user1",
      secret_name: "MAVEN_REPOSITORY_PASSWORD",
    )
    @org1_config2 = create(
      :private_registry_configuration,
      url: "https://maven.pkg.github.com/org1/repo2",
      owner_id: @org1.id,
      username: "maven_user2",
      secret_name: "MAVEN_REPOSITORY_PASSWORD2",
    )

    @org2 = create(:organization)
    @org2_repo = create(:private_repository, owner: @org2)
    @org2_config = create(
      :private_registry_configuration,
      url: "https://maven.pkg.github.com/org2/*",
      owner_id: @org2.id,
      username: "maven_user",
      secret_name: "MAVEN_REPOSITORY_PASSWORD",
    )
  end

  setup do
    @org1_secret1 = {
      app: @app,
      owner: @org1,
      visibility: GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_SELECTED_REPOS,
      selected_repositories: [global_id(@org1_repo1)],
      name: "MAVEN_REPOSITORY_PASSWORD",
      value: encrypted_secret_value("password1", owner: @org1),
    }
    @org1_secret2 = {
      app: @app,
      owner: @org1,
      visibility: GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_SELECTED_REPOS,
      selected_repositories: [global_id(@org1_repo2)],
      name: "MAVEN_REPOSITORY_PASSWORD2",
      value: encrypted_secret_value("password2", owner: @org1),
    }

    @org2_secret = {
      app: @app,
      owner: @org2,
      visibility: GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_SELECTED_REPOS,
      selected_repositories: [global_id(@org2_repo)],
      name: "MAVEN_REPOSITORY_PASSWORD",
      value: encrypted_secret_value("the password", owner: @org2),
    }
  end

  context ".credentials_for_repository" do
    test "includes credentials owned by the app and organization and visible to the repository" do
      expected_credentials = [
        {
          type: "maven_repository",
          url: "https://maven.pkg.github.com/org1/repo1",
          username: "maven_user1",
          password: "password1"
        },
      ]

      FakeKredz.with_secrets(@org1_secret1, @org1_secret2, @org2_secret) do
        credentials = PrivateRegistry.credentials_for_repository(@org1_repo1, actor: @org1, include_value: true)
        assert_equal expected_credentials, credentials
      end
    end

    test "does not request secret value when include_value is false" do
      mock_response = FakeKredzResponse.new(data: FakeKredz::FakeKredzListRepositoryResponse.new([], []))
      mock = Minitest::Mock.new
      mock.expect(:call, mock_response) do |include_value:, **_kwargs|
        refute include_value, "expected :include_value to be false"
      end

      GitHub::KredzClient::Credz.stub(:list_repository_secrets, mock) do
        PrivateRegistry.credentials_for_repository(@org1_repo1, actor: @org1, include_value: false)
      end

      mock.verify
    end

    test "excludes credentials when configuration is present but Credz secret is missing" do
      FakeKredz.with_secrets(@org1_secret2, @org2_secret) do
        credentials = PrivateRegistry.credentials_for_repository(@org1_repo1, actor: @org1, include_value: false)
        assert_empty credentials
      end
    end

    test "excludes credentials when Credz secret is present but configuration is missing" do
      @org1_config1.destroy!

      FakeKredz.with_secrets(@org1_secret1, @org1_secret2, @org2_secret) do
        credentials = PrivateRegistry.credentials_for_repository(@org1_repo1, actor: @org1, include_value: false)
        assert_empty credentials
      end
    end

    test "logs error when Credz request fails" do
      error_response = FakeKredzResponse.new(error_code: :unavailable)
      GitHub::KredzClient::Credz.expects(:list_repository_secrets).returns(error_response)

      GitHub.logger.expects(:error).with do |msg, params|
        assert_match "Failed to list private registry secrets for repository", msg
        assert_equal "[503] Secrets service unavailable", params["exception.message"]
        assert_equal "Secrets::Error", params["exception.type"]
        assert_equal @org1_repo1.id, params["gh.repo.id"]
      end

      credentials = PrivateRegistry.credentials_for_repository(@org1_repo1, actor: @org1, include_value: false)
      assert_empty credentials
    end
  end

  def encrypted_secret_value(plaintext, owner:)
    if GitHub.enterprise?
      Base64.strict_encode64(plaintext)
    else
      encrypt_with_owner_next_global_id(plaintext, owner, key_name: Platform::EncryptionKeys::PRIVATE_REGISTRY_SECRETS)
    end
  end

  def global_id(obj)
    GitHub.enterprise? ? obj.global_relay_id : obj.next_global_id
  end
end
