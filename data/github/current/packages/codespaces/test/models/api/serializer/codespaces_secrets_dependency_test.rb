# typed: true
# frozen_string_literal: true

require "test_helpers/api_serializer_helper"
require "github/kredz_client"
require "github-kredz"
require "test_helpers/fake_kredz"
require "test_helpers/secrets_test_helpers"

class CodespacesSecretsSerializersTest < Api::SerializerTestCase
  include PlatformTestHelpers::InterfaceHelpers
  include SecretsTestHelper

  fixtures do
    make_trusted_oauth_apps_owner
  end

  context "codespaces_user_secret_hash" do
    test "payload returns valid data" do
      api_user = create(:user, login: "api-user")
      repo = create(:repository, owner: api_user)
      FakeKredz.with_secrets({
        app: create(:codespaces_integration),
        owner: api_user,
        name: "TEST_SECRET_NAME",
        visibility: GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_SELECTED_REPOS,
        selected_repositories: [repo.global_relay_id],
        value: encrypt_with_owner_next_global_id("this is super secret", api_user)
      }) do
        secret = Codespaces::UserSecret.for(api_user).first
        serialized_output = Api::Serializer.serialize(:codespaces_user_secret_hash, secret)
        output = GitHub::JSON.parse(GitHub::JSON.encode(serialized_output))

        assert output["created_at"]
        assert output["updated_at"]
        assert_equal output["name"], "TEST_SECRET_NAME"
        assert_equal output["visibility"], GitHub::KredzClient::Credz::TO_VISIBILITY_MAP[GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_SELECTED_REPOS]
        assert_equal output["selected_repositories_url"], "https://api.github.com/user/codespaces/secrets/TEST_SECRET_NAME/repositories"
      end
    end

    test "sets updated_at to equal created_at even if it's nil" do
      api_user = create(:user, login: "api-user")
      FakeKredz.with_secrets({
        app: create(:codespaces_integration),
        owner: api_user,
        name: "TEST_SECRET_NAME",
        visibility: GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_SELECTED_REPOS,
        value: encrypt_with_owner_next_global_id("this is super secret", api_user)
      }) do
        secret = Codespaces::UserSecret.for(api_user).first
        secret.updated_at = nil
        serialized_output = Api::Serializer.serialize(:codespaces_user_secret_hash, secret)
        output = GitHub::JSON.parse(GitHub::JSON.encode(serialized_output))

        assert output["updated_at"], secret.created_at
      end
    end
  end

  context "#codespaces_user_secrets_hash" do
    test "payload returns valid data as list" do
      api_user = create(:user, login: "api-user")
      repo = create(:repository, owner: api_user)
      integration = create(:codespaces_integration)
      FakeKredz.with_secrets({
        app: integration,
        owner: api_user,
        name: "SECRET_ONE",
        visibility: GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_SELECTED_REPOS,
        selected_repositories: [repo.global_relay_id],
        value: encrypt_with_owner_next_global_id("one super secret", api_user)
      }, {
        app: integration,
        owner: api_user,
        name: "SECRET_TWO",
        visibility: GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_SELECTED_REPOS,
        selected_repositories: [],
        value: encrypt_with_owner_next_global_id("two super secrets", api_user)
      }) do
        secrets = Api::App.new!.paginate_rel(
          Codespaces::UserSecret.for(api_user),
          { per_page: 30, page: 1 }
        )
        serialized_output = Api::Serializer.serialize(:codespaces_user_secrets_hash, { secrets: secrets, total_count: secrets.total_entries })
        output = GitHub::JSON.parse(GitHub::JSON.encode(serialized_output))

        assert_equal output["total_count"], 2
        assert output["secrets"][0]["created_at"]
        assert output["secrets"][0]["updated_at"]
        assert_equal output["secrets"][0]["name"], "SECRET_ONE"
        assert_equal output["secrets"][0]["visibility"], "selected"
        assert_equal output["secrets"][0]["selected_repositories_url"], "https://api.github.com/user/codespaces/secrets/SECRET_ONE/repositories"
        assert output["secrets"][1]["created_at"]
        assert output["secrets"][1]["updated_at"]
        assert_equal output["secrets"][1]["name"], "SECRET_TWO"
        assert_equal output["secrets"][1]["visibility"], "selected"
        assert_equal output["secrets"][1]["selected_repositories_url"], "https://api.github.com/user/codespaces/secrets/SECRET_TWO/repositories"
      end
    end
  end
end unless GitHub.enterprise?
