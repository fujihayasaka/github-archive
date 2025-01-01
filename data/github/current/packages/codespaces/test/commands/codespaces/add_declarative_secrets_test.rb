# typed: true
# frozen_string_literal: true

require "github/launch_client"
require "test_helper"
require "test_helpers/fake_kredz"
require "test_helpers/secrets_test_helpers"
require "test_helpers/launch_test_helpers"

class Codespaces::AddDeclarativeSecretsTest < GitHub::TestCase
  include LaunchTestHelpers
  include SecretsTestHelper

  fixtures do
    make_trusted_oauth_apps_owner
    @integration = create(:codespaces_integration)
    @user = create(:user)
    @repo = create(:repository)
    @key_id = 1234
  end

  setup do
    DietEarthsmoke::KeyVersion.any_instance.stubs(:id).returns(@key_id)
    DietEarthsmoke::KeyExportResponse.any_instance.stubs(:current_key_id).returns(@key_id)
    @existing_secret = {
      app: @integration,
      name: "SECRET",
      value: encrypt_with_owner_next_global_id("super secret string", @user),
      owner: @user,
      selected_repositories: [],
    }
  end

  test "creating a brand new secret" do
    FakeKredz.with_no_secrets do
      credential = GitHub::Launch::Services::Credz::Credential.new(
        name: "TAMATOA",
        created_at: Google::Protobuf::Timestamp.new(seconds: 123456),
        updated_at: Google::Protobuf::Timestamp.new(seconds: 123456),
      )
      encrypted_value = encrypt_with_owner_next_global_id("shiny", @user)
      expected_value = Base64.strict_encode64(embed(@key_id, Base64.strict_decode64(encrypted_value)))
      GitHub::KredzClient::Credz.expects(:create_credential).with(
        app:   ::Apps::Internal.integration(:codespaces_production),
        owner:  @user,
        actor: @user,
        key: "TAMATOA",
        value: expected_value,
        visibility: GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_SELECTED_REPOS,
        selected_repositories: [@repo.global_relay_id],
      ).returns(FakeKredzResponse.new(data: GitHub::Launch::Services::Credz::CreateResponse.new(stored: true, credential: credential)))
      Codespaces::AddDeclarativeSecrets.call(
        user: @user,
        repository: @repo,
        secrets_data: {
          "TAMATOA" => encrypted_value
        }
      )
    end
  end

  test "associating an existing secret to a repository" do
    FakeKredz.with_secrets(@existing_secret) do
      credential = GitHub::Launch::Services::Credz::Credential.new(
        name: "SECRET",
        created_at: Google::Protobuf::Timestamp.new(seconds: 123456),
        updated_at: Google::Protobuf::Timestamp.new(seconds: 123456),
      )
      GitHub::KredzClient::Credz.expects(:update_credential).with(
        app:   ::Apps::Internal.integration(:codespaces_production),
        owner:  @user,
        actor: @user,
        key: "SECRET",
        value: "",
        visibility: GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_SELECTED_REPOS,
        selected_repositories: [@repo.global_relay_id],
      ).returns(FakeKredzResponse.new(data: GitHub::Launch::Services::Credz::UpdateResponse.new(updated: true, credential: credential)))
      Codespaces::AddDeclarativeSecrets.call(
        user: @user,
        repository: @repo,
        secrets_data: {
          "SECRET" => true
        }
      )
    end
  end
end
