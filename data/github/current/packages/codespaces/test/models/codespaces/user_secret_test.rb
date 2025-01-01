# typed: true
# frozen_string_literal: true

require "github-kredz"
require "github/kredz_client"
require "test_helper"
require "test_helpers/fake_kredz_response"
require "test_helpers/launch_test_helpers"

module Codespaces
  class UserSecretTest < GitHub::TestCase
    include LaunchTestHelpers

    self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
    fixtures do
      make_trusted_oauth_apps_owner
      create(:codespaces_integration)

      @user = create(:user)
      @repository = create(:repository, owner: @user)
      @inaccessible_repository = create(:private_repository)
      @key_id, _ = Secrets.github_public_key(owner: @user, key_name: Platform::EncryptionKeys::CODESPACES_SECRETS)
      @name = "seeeecret"
      @encrypted_value = "b2ggaGVsbG8gaG93IGlzIGl0"
      @attributes = {
        user: @user,
        key_id: @key_id,
        name: @name,
        encrypted_value: @encrypted_value,
        repository_ids: [@repository.id]
      }
    end

    context "validations", skip_enterprise: true do
      test "is valid with valid attributes" do
        DietEarthsmoke::KeyVersion.any_instance.stubs(:id).returns(@attributes[:key_id])
        DietEarthsmoke::KeyExportResponse.any_instance.stubs(:current_key_id).returns(@attributes[:key_id])

        assert Codespaces::UserSecret.new(@attributes).valid?(:new)
      end

      %i(user key_id name encrypted_value).each do |attr|
        test "requires #{attr}" do
          DietEarthsmoke::KeyVersion.any_instance.stubs(:id).returns(@attributes[:key_id])
          DietEarthsmoke::KeyExportResponse.any_instance.stubs(:current_key_id).returns(@attributes[:key_id])


          secret = Codespaces::UserSecret.new(@attributes.except(attr))
          refute secret.valid?(:new)
          assert secret.errors.include?(attr)
        end
      end

      test "handles empty list of selected repositories" do
        DietEarthsmoke::KeyVersion.any_instance.stubs(:id).returns(@attributes[:key_id])
        DietEarthsmoke::KeyExportResponse.any_instance.stubs(:current_key_id).returns(@attributes[:key_id])

        assert Codespaces::UserSecret.new(@attributes.merge(repository_ids: [])).valid?(:new)
      end

      test "valid if repository is associated with the user via team role" do
        repo = create(:private_repository, :minimal, owner: create(:enterprise_linked_organization))

        org = repo.owner
        write_team = create(:team, organization: org, name: "write-team")

        write_team_member = create(:user, login: "write-team-member")
        org.add_member(write_team_member)
        write_team.add_member(write_team_member)

        org.grant_org_role(assignee: write_team, role: OrganizationRole.all_repo_write_role)

        secret = Codespaces::UserSecret.new(@attributes.merge(
          user: write_team_member,
          repository_ids: [repo.id.to_s])
        )
        assert secret.valid?(:new)
      end

      test "repository_ids must must be accessible" do
        secret = Codespaces::UserSecret.new(@attributes.merge(repository_ids: [@inaccessible_repository.id]))
        refute secret.valid?(:new)
        assert secret.errors.include?(:repository_ids)
      end

      test "cap maximum number of selected repositories" do
        secret = Codespaces::UserSecret.new(@attributes.merge(repository_ids: (1..101).to_a))
        refute secret.valid?
        assert secret.errors.include?(:repository_ids)
      end

      test "handles blank key_id" do
        refute Codespaces::UserSecret.new(@attributes.merge(key_id: "")).valid?
      end

      test "rejects non-numeric key_ids" do
        refute Codespaces::UserSecret.new(@attributes.merge(key_id: "hi there")).valid?
      end

      test "key_id must be valid for provided user" do
        DietEarthsmoke::KeyVersion.any_instance.stubs(:id).returns(5678)
        DietEarthsmoke::KeyExportResponse.any_instance.stubs(:current_key_id).returns(5678)

        refute Codespaces::UserSecret.new(@attributes).valid?
      end

      test "encrypted value must be valid" do
        GitHub::KredzClient::Credz.expects(:validate_secret).returns(mock(succeeded?: false, error: "Sweet error"))
        secret = Codespaces::UserSecret.new(@attributes)
        refute secret.valid?(:new)
        assert secret.errors.include?(:encrypted_value)
      end
    end

    context "#save", skip_enterprise: true do
      test "handles success super well" do
        credential = GitHub::Launch::Services::Credz::Credential.new(
          name: @name,
          created_at: Google::Protobuf::Timestamp.new(seconds: 123456),
          updated_at: Google::Protobuf::Timestamp.new(seconds: 123456),
        )
        DietEarthsmoke::KeyVersion.any_instance.stubs(:id).returns(@key_id)
        DietEarthsmoke::KeyExportResponse.any_instance.stubs(:current_key_id).returns(@key_id)

        expected_value = Base64.strict_encode64(embed(@key_id, Base64.strict_decode64(@encrypted_value)))

        GitHub::KredzClient::Credz.expects(:create_credential).with(
          app:   ::Apps::Privileged.integration(:codespaces_production),
          owner:  @user,
          actor: @user,
          key:   @name,
          value: expected_value,
          visibility: GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_SELECTED_REPOS,
          selected_repositories: [@repository.global_relay_id],
        ).returns(FakeKredzResponse.new(data: GitHub::Launch::Services::Credz::CreateResponse.new(stored: true, credential: credential)))

        GlobalInstrumenter.expects(:instrument).with("user_secret.create", {
          app: ::Apps::Privileged.integration(:codespaces_production),
          owner: @user,
          actor: @user,
          name: @name,
          selected_repositories: [@repository.global_relay_id],
          state: "CREATED",
        }).once

        secret = Codespaces::UserSecret.new(@attributes)
        assert secret.save
      end

      test "filters out repositories that are not visible to the user" do
        credential = GitHub::Launch::Services::Credz::Credential.new(
          name: @name,
          created_at: Google::Protobuf::Timestamp.new(seconds: 123456),
          updated_at: Google::Protobuf::Timestamp.new(seconds: 123456),
        )
        DietEarthsmoke::KeyVersion.any_instance.stubs(:id).returns(@key_id)
        DietEarthsmoke::KeyExportResponse.any_instance.stubs(:current_key_id).returns(@key_id)

        expected_value = Base64.strict_encode64(embed(@key_id, Base64.strict_decode64(@encrypted_value)))

        GitHub::KredzClient::Credz.expects(:create_credential).with(
          app:   ::Apps::Privileged.integration(:codespaces_production),
          owner:  @user,
          actor: @user,
          key:   @name,
          value: expected_value,
          visibility: GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_SELECTED_REPOS,
          selected_repositories: [@repository.global_relay_id],
        ).returns(FakeKredzResponse.new(data: GitHub::Launch::Services::Credz::CreateResponse.new(stored: true, credential: credential)))

        # Passing both a accessible and inaccessible repo should result in only the
        # accessible repo being stored in Credz
        secret = Codespaces::UserSecret.new(@attributes.merge(repository_ids: [@repository.id, @inaccessible_repository.id]))
        assert secret.save
      end

      test "handles credential not stored" do
        credential = GitHub::Launch::Services::Credz::Credential.new(
          name: @name,
          created_at: Google::Protobuf::Timestamp.new(seconds: 123456),
          updated_at: Google::Protobuf::Timestamp.new(seconds: 123456),
        )
        DietEarthsmoke::KeyVersion.any_instance.stubs(:id).returns(@key_id)
        DietEarthsmoke::KeyExportResponse.any_instance.stubs(:current_key_id).returns(@key_id)

        expected_value = Base64.strict_encode64(embed(@key_id, Base64.strict_decode64(@encrypted_value)))

        error = GitHub::Launch::Services::Credz::Error.new(error_number: 7, error_message: "Didn't work")
        GitHub::KredzClient::Credz.expects(:create_credential).with(
          app:   ::Apps::Privileged.integration(:codespaces_production),
          owner:  @user,
          actor: @user,
          key:   @name,
          value: expected_value,
          visibility: GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_SELECTED_REPOS,
          selected_repositories: [@repository.global_relay_id],
        ).returns(FakeKredzResponse.new(data: GitHub::Launch::Services::Credz::CreateResponse.new(stored: false, credential: credential, error: error)))

        secret = Codespaces::UserSecret.new(@attributes)
        refute secret.save
      end

      test "handles service failures" do
        DietEarthsmoke::KeyVersion.any_instance.stubs(:id).returns(@attributes[:key_id])
        DietEarthsmoke::KeyExportResponse.any_instance.stubs(:current_key_id).returns(@attributes[:key_id])

        GitHub::KredzClient::Credz.expects(:create_credential).returns(FakeKredzResponse.new(error_code: :unavailable, error_message: "Credz service unavailable"))

        Codespaces::ErrorReporter
          .any_instance.expects(:report)
          .once.with(
            instance_of(Codespaces::UserSecret::CreationError),
            user: @attributes[:user].login,
            error_msg: "Error creating a user's secret for Codespaces.",
            error_type: "Secrets::Error"
          )

        secret = Codespaces::UserSecret.new(@attributes)
        refute secret.save
      end
    end

    # In Credz there is seemingly little to no difference between updating and
    # storing a new credential so these tests are basically the same as #save
    context "#update", skip_enterprise: true do
      test "handles success super well" do
        credential = GitHub::Launch::Services::Credz::Credential.new(
          name: @name,
          created_at: Google::Protobuf::Timestamp.new(seconds: 123456),
          updated_at: Google::Protobuf::Timestamp.new(seconds: 123456),
        )
        DietEarthsmoke::KeyVersion.any_instance.stubs(:id).returns(@attributes[:key_id])
        DietEarthsmoke::KeyExportResponse.any_instance.stubs(:current_key_id).returns(@attributes[:key_id])

        expected_value = Base64.strict_encode64(embed(@key_id, Base64.strict_decode64(@encrypted_value)))

        GitHub::KredzClient::Credz.expects(:update_credential).with(
          app:   ::Apps::Privileged.integration(:codespaces_production),
          owner:  @user,
          actor: @user,
          key:   @name,
          value: expected_value,
          visibility: GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_SELECTED_REPOS,
          selected_repositories: [@repository.global_relay_id],
        ).returns(FakeKredzResponse.new(data: GitHub::Launch::Services::Credz::UpdateResponse.new(updated: true, credential: credential)))

        GlobalInstrumenter.expects(:instrument).with("user_secret.update", {
          app: ::Apps::Privileged.integration(:codespaces_production),
          owner: @user,
          actor: @user,
          name: @name,
          selected_repositories: [@repository.global_relay_id],
          state: "UPDATED",
        }).once

        secret = Codespaces::UserSecret.new(@attributes)
        assert secret.update
      end

      test "handles updates without a modified encrypted value" do
        credential = GitHub::Launch::Services::Credz::Credential.new(
          name: @name,
          created_at: Google::Protobuf::Timestamp.new(seconds: 123456),
          updated_at: Google::Protobuf::Timestamp.new(seconds: 123456),
        )

        DietEarthsmoke::KeyVersion.any_instance.stubs(:id).returns(@attributes[:key_id])
        DietEarthsmoke::KeyExportResponse.any_instance.stubs(:current_key_id).returns(@attributes[:key_id])

        GitHub::KredzClient::Credz.expects(:update_credential).with(
          app:   ::Apps::Privileged.integration(:codespaces_production),
          owner:  @user,
          actor: @user,
          key:   @name,
          value: "",
          visibility: GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_SELECTED_REPOS,
          selected_repositories: [@repository.global_relay_id],
        ).returns(FakeKredzResponse.new(data: GitHub::Launch::Services::Credz::UpdateResponse.new(updated: true, credential: credential)))

        secret = Codespaces::UserSecret.new(@attributes.except(:encrypted_value))
        assert secret.update
      end

      test "filters out repositories that are not visible to the user" do
        credential = GitHub::Launch::Services::Credz::Credential.new(
          name: @name,
          created_at: Google::Protobuf::Timestamp.new(seconds: 123456),
          updated_at: Google::Protobuf::Timestamp.new(seconds: 123456),
        )
        DietEarthsmoke::KeyVersion.any_instance.stubs(:id).returns(@attributes[:key_id])
        DietEarthsmoke::KeyExportResponse.any_instance.stubs(:current_key_id).returns(@attributes[:key_id])

        expected_value = Base64.strict_encode64(embed(@key_id, Base64.strict_decode64(@encrypted_value)))

        GitHub::KredzClient::Credz.expects(:update_credential).with(
          app:   ::Apps::Privileged.integration(:codespaces_production),
          owner:  @user,
          actor: @user,
          key:   @name,
          value: expected_value,
          visibility: GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_SELECTED_REPOS,
          selected_repositories: [@repository.global_relay_id],
        ).returns(FakeKredzResponse.new(data: GitHub::Launch::Services::Credz::UpdateResponse.new(updated: true, credential: credential)))

        # Passing both a accessible and inaccessible repo should result in only the
        # accessible repo being stored in Credz
        secret = Codespaces::UserSecret.new(@attributes.merge(repository_ids: [@repository.id, @inaccessible_repository.id]))
        assert secret.update
      end

      test "handles credential not stored" do
        credential = GitHub::Launch::Services::Credz::Credential.new(
          name: @name,
          created_at: Google::Protobuf::Timestamp.new(seconds: 123456),
          updated_at: Google::Protobuf::Timestamp.new(seconds: 123456),
        )

        DietEarthsmoke::KeyVersion.any_instance.stubs(:id).returns(@attributes[:key_id])
        DietEarthsmoke::KeyExportResponse.any_instance.stubs(:current_key_id).returns(@attributes[:key_id])

        expected_value = Base64.strict_encode64(embed(@key_id, Base64.strict_decode64(@encrypted_value)))

        error = GitHub::Launch::Services::Credz::Error.new(error_number: 7, error_message: "Didn't work")
        GitHub::KredzClient::Credz.expects(:update_credential).with(
          app:   ::Apps::Privileged.integration(:codespaces_production),
          owner:  @user,
          actor: @user,
          key:   @name,
          value: expected_value,
          visibility: GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_SELECTED_REPOS,
          selected_repositories: [@repository.global_relay_id],
        ).returns(FakeKredzResponse.new(data: GitHub::Launch::Services::Credz::UpdateResponse.new(updated: false, credential: credential, error: error)))

        secret = Codespaces::UserSecret.new(@attributes)
        refute secret.update
      end

      test "handles service failures" do
        DietEarthsmoke::KeyVersion.any_instance.stubs(:id).returns(@attributes[:key_id])
        DietEarthsmoke::KeyExportResponse.any_instance.stubs(:current_key_id).returns(@attributes[:key_id])

        GitHub::KredzClient::Credz.expects(:update_credential).returns(FakeKredzResponse.new(error_code: :unavailable, error_message: "Credz service unavailable"))

        Codespaces::ErrorReporter
          .any_instance.expects(:report)
          .once.with(
            instance_of(Codespaces::UserSecret::UpdatingError),
            user: @attributes[:user].login,
            error_msg: "Error updating a user's secret for Codespaces.",
            error_type: "Secrets::Error"
          )

        secret = Codespaces::UserSecret.new(@attributes)
        refute secret.update
      end
    end

    context "#delete", skip_enterprise: true do
      test "deletes the secret" do
        DietEarthsmoke::KeyVersion.any_instance.stubs(:id).returns(@attributes[:key_id])
        DietEarthsmoke::KeyExportResponse.any_instance.stubs(:current_key_id).returns(@attributes[:key_id])


        expected_value = Base64.strict_encode64(embed(@key_id, Base64.strict_decode64(@encrypted_value)))

        GitHub::KredzClient::Credz.expects(:delete_credential).with(
          app:   ::Apps::Privileged.integration(:codespaces_production),
          owner:  @user,
          actor: @user,
          key:   @name,
        ).returns(FakeKredzResponse.new(data: GitHub::Launch::Services::Credz::DeleteResponse.new(success: true)))

        GlobalInstrumenter.expects(:instrument).with("user_secret.remove", {
          app: ::Apps::Privileged.integration(:codespaces_production),
          owner: @user,
          actor: @user,
          name: @name,
          selected_repositories: [],
          state: "DELETED",
        }).once

        secret = Codespaces::UserSecret.new(user: @user, name: @name, key_id: @key_id)
        assert secret.delete
      end

      test "handles credential not deleted" do
        DietEarthsmoke::KeyVersion.any_instance.stubs(:id).returns(@attributes[:key_id])
        DietEarthsmoke::KeyExportResponse.any_instance.stubs(:current_key_id).returns(@attributes[:key_id])


        expected_value = Base64.strict_encode64(embed(@key_id, Base64.strict_decode64(@encrypted_value)))

        error = GitHub::Launch::Services::Credz::Error.new(error_number: 7, error_message: "Didn't work")
        GitHub::KredzClient::Credz.expects(:delete_credential).with(
          app:   ::Apps::Privileged.integration(:codespaces_production),
          owner:  @user,
          actor: @user,
          key:   @name,
        ).returns(FakeKredzResponse.new(data: GitHub::Launch::Services::Credz::DeleteResponse.new(success: false, error: error)))

        secret = Codespaces::UserSecret.new(user: @user, name: @name, key_id: @key_id)
        refute secret.delete
      end

      test "handles service failures" do
        DietEarthsmoke::KeyVersion.any_instance.stubs(:id).returns(@attributes[:key_id])
        DietEarthsmoke::KeyExportResponse.any_instance.stubs(:current_key_id).returns(@attributes[:key_id])

        GitHub::KredzClient::Credz.expects(:delete_credential).returns(FakeKredzResponse.new(error_code: :unavailable, error_message: "Credz service unavailable"))

        Codespaces::ErrorReporter
          .any_instance.expects(:report)
          .once.with(
            instance_of(Codespaces::UserSecret::DeletionError),
            user: @attributes[:user].login,
            error_msg:  "Error deleting a user's secret for Codespaces.",
            error_type: "Secrets::Error"
          )

        secret = Codespaces::UserSecret.new(user: @user, name: @name, key_id: @key_id)
        refute secret.delete
      end
    end

    context "#fetch_credential", skip_enterprise: true do
      test "fetches the credential for the secret" do
        credential = GitHub::Launch::Services::Credz::Credential.new(
          name: @name,
          created_at: Google::Protobuf::Timestamp.new(seconds: 123456),
          updated_at: Google::Protobuf::Timestamp.new(seconds: 123456),
          selected_repositories_count: 1,
          selected_repositories: [GitHub::Launch::Services::Credz::Repository.new(global_id: @repository.global_relay_id)],
        )
        DietEarthsmoke::KeyVersion.any_instance.stubs(:id).returns(@attributes[:key_id])
        DietEarthsmoke::KeyExportResponse.any_instance.stubs(:current_key_id).returns(@attributes[:key_id])


        expected_value = Base64.strict_encode64(embed(@key_id, Base64.strict_decode64(@encrypted_value)))

        GitHub::KredzClient::Credz.expects(:fetch_credential).with(
          app:   ::Apps::Privileged.integration(:codespaces_production),
          owner:  @user,
          actor: @user,
          key:   @name,
          include_value: true,
        ).returns(FakeKredzResponse.new(data: GitHub::Launch::Services::Credz::FetchResponse.new(credential: credential)))

        secret = Codespaces::UserSecret.new(user: @user, name: @name, key_id: @key_id)
        assert_equal credential, secret.fetch_credential
        assert_equal [@repository.id], secret.repository_ids
      end

      test "handles credential fetch errors" do
        DietEarthsmoke::KeyVersion.any_instance.stubs(:id).returns(@attributes[:key_id])
        DietEarthsmoke::KeyExportResponse.any_instance.stubs(:current_key_id).returns(@attributes[:key_id])


        expected_value = Base64.strict_encode64(embed(@key_id, Base64.strict_decode64(@encrypted_value)))

        error = GitHub::Launch::Services::Credz::Error.new(error_number: 7, error_message: "Didn't work")
        GitHub::KredzClient::Credz.expects(:fetch_credential).with(
          app:   ::Apps::Privileged.integration(:codespaces_production),
          owner:  @user,
          actor: @user,
          key:   @name,
          include_value: true,
        ).returns(FakeKredzResponse.new(data: GitHub::Launch::Services::Credz::FetchResponse.new(error: error)))

        secret = Codespaces::UserSecret.new(user: @user, name: @name, key_id: @key_id)
        assert_nil secret.fetch_credential
      end

      test "handles service failures" do
        DietEarthsmoke::KeyVersion.any_instance.stubs(:id).returns(@attributes[:key_id])
        DietEarthsmoke::KeyExportResponse.any_instance.stubs(:current_key_id).returns(@attributes[:key_id])

        GitHub::KredzClient::Credz.expects(:fetch_credential).returns(FakeKredzResponse.new(error_code: :unavailable, error_message: "Credz service unavailable"))

        secret = Codespaces::UserSecret.new(user: @user, name: @name, key_id: @key_id)
        assert_nil secret.fetch_credential
      end
    end

    context "#for", skip_enterprise: true do
      test "fetches the credentials from credz" do
        credential = GitHub::Launch::Services::Credz::Credential.new(
          name: @name,
          created_at: Google::Protobuf::Timestamp.new(seconds: 123456),
          updated_at: Google::Protobuf::Timestamp.new(seconds: 123456),
          selected_repositories_count: 2,
        )
        DietEarthsmoke::KeyVersion.any_instance.stubs(:id).returns(@attributes[:key_id])
        DietEarthsmoke::KeyExportResponse.any_instance.stubs(:current_key_id).returns(@attributes[:key_id])


        expected_value = Base64.strict_encode64(embed(@key_id, Base64.strict_decode64(@encrypted_value)))

        GitHub::KredzClient::Credz.expects(:list_credentials).with(
          app:   ::Apps::Privileged.integration(:codespaces_production),
          owner:  @user,
          actor: @user,
        ).returns(FakeKredzResponse.new(data: GitHub::Launch::Services::Credz::ListResponse.new(credentials: [credential])))

        secrets = Codespaces::UserSecret.for(@user)
        assert_equal 1, secrets.length
        assert_equal @name, secrets.first.name
        assert_equal 2, secrets.first.selected_repositories_count
        assert secrets.first.created_at
        assert secrets.first.updated_at
        assert secrets.first.visibility
      end

      test "handles credential fetch errors" do
        DietEarthsmoke::KeyVersion.any_instance.stubs(:id).returns(@attributes[:key_id])
        DietEarthsmoke::KeyExportResponse.any_instance.stubs(:current_key_id).returns(@attributes[:key_id])

        expected_value = Base64.strict_encode64(embed(@key_id, Base64.strict_decode64(@encrypted_value)))

        error = GitHub::Launch::Services::Credz::Error.new(error_number: 7, error_message: "Didn't work")
        GitHub::KredzClient::Credz.expects(:list_credentials).with(
          app:   ::Apps::Privileged.integration(:codespaces_production),
          owner:  @user,
          actor: @user,
        ).returns(FakeKredzResponse.new(data: GitHub::Launch::Services::Credz::ListResponse.new(error: error)))

        assert_empty Codespaces::UserSecret.for(@user)
      end

      test "handles service failures" do
        DietEarthsmoke::KeyVersion.any_instance.stubs(:id).returns(@attributes[:key_id])
        DietEarthsmoke::KeyExportResponse.any_instance.stubs(:current_key_id).returns(@attributes[:key_id])

        GitHub::KredzClient::Credz.expects(:list_credentials).returns(FakeKredzResponse.new(error_code: :unavailable, error_message: "Credz service unavailable"))

        assert_empty Codespaces::UserSecret.for(@user)
      end
    end

    context "repositories", skip_enterprise: true do
      test "filters out repositories that are not visible to the user at read time" do
        secret = Codespaces::UserSecret.new(@attributes.merge(repository_ids: [@repository.id, @inaccessible_repository.id]))
        assert_equal [@repository], secret.repositories
      end
    end
  end
end
