# typed: true
# frozen_string_literal: true

require "github/launch_client"
require "test_helper"
require "test_helpers/fake_kredz"
require "test_helpers/secrets_test_helpers"

module Codespaces
  class ReassociateUserSecretsTest < GitHub::TestCase
    include SecretsTestHelper

    fixtures do
      make_trusted_oauth_apps_owner
      @integration = create(:codespaces_integration)
      @user = create(:user)
    end

    setup do
      GitHub.flipper[:disable_codespaces_secrets].disable
      @random_repo = create(:repository, owner: @user)
      @readonly_repository = create(:repository)
      @readonly_codespace = create(:codespace, make_collaborator: false, repository: @readonly_repository, owner: @user)
      @template_codespace = create(:unpublished_codespace, owner: @user)
      @template_repo_secret = {
        app: @integration,
        name: "TEMPLATE_SECRET",
        value: encrypt_with_owner_next_global_id("super secret string", @user),
        owner: @user,
        selected_repositories: [@template_codespace.repository.next_global_id],
      }
      @readonly_repo_secret = {
        app: @integration,
        name: "READONLY_SECRET",
        value: encrypt_with_owner_next_global_id("super secret string", @user),
        owner: @user,
        selected_repositories: [@readonly_repository.next_global_id],
      }
      @random_repo_secret = {
        app: @integration,
        name: "RANDOM_SECRET",
        value: encrypt_with_owner_next_global_id("super secret string", @user),
        owner: @user,
        selected_repositories: [@random_repo.next_global_id],
      }
    end

    test "can reassociate a users secrets when a codespace is published" do
      FakeKredz.with_secrets(@template_repo_secret, @readonly_repo_secret, @random_repo_secret) do
        Codespaces::PublishToRepository.call(
          codespace: @template_codespace,
          name: "my-super-cool-repository",
          is_private: false
        )
        GitHub::KredzClient::Credz.expects(:update_credential).with(
          app:   ::Apps::Privileged.integration(:codespaces_production),
          owner:  @user,
          actor: @user,
          key: "TEMPLATE_SECRET",
          value: "",
          visibility: GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_SELECTED_REPOS,
          selected_repositories: [@template_codespace.template_repository.global_relay_id, @template_codespace.repository.global_relay_id].sort,
        ).returns(FakeKredzResponse.new(data: GitHub::Launch::Services::Credz::UpdateResponse.new(updated: true, credential: nil)))
        Codespaces::ReassociateUserSecrets.call(codespace: @template_codespace)
      end
    end

    test "can reassociate a users secrets when a codespace's repository is forked" do
      FakeKredz.with_secrets(@template_repo_secret, @readonly_repo_secret, @random_repo_secret) do
        fork, branch = Codespaces::ForkRepo.call(@readonly_codespace, "main", entry_point: :test_case)
        GitHub::KredzClient::Credz.expects(:update_credential).with(
          app:   ::Apps::Privileged.integration(:codespaces_production),
          owner:  @user,
          actor: @user,
          key: "READONLY_SECRET",
          value: "",
          visibility: GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_SELECTED_REPOS,
          selected_repositories: [@readonly_repository.global_relay_id, fork.global_relay_id].sort,
        ).returns(FakeKredzResponse.new(data: GitHub::Launch::Services::Credz::UpdateResponse.new(updated: true, credential: nil)))
        Codespaces::ReassociateUserSecrets.call(codespace: @readonly_codespace)
      end
    end

    test "doesn't reassociate things if the new repo is somehow not pushable" do
      FakeKredz.with_secrets(@template_repo_secret, @readonly_repo_secret, @random_repo_secret) do
        # We're pretending we got an event that this codespace's repo changed even though we're not changing it
        # because that means the @readonly_codespace is still readonly so we should bail
        Codespaces::UserSecret.expects(:for).never
        GitHub::KredzClient::Credz.expects(:update_credential).never
        Codespaces::ReassociateUserSecrets.call(codespace: @readonly_codespace)
      end
    end
  end
end
