# typed: true
# frozen_string_literal: true

require "test_helper"

class CodespacesSubscribersTest < GitHub::TestCase
  include CodespacesPlanFixtures

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    make_trusted_oauth_apps_owner
    @organization = create(:organization)
    @user = create(:user)
    @repository = create(:repository, owner: @user)
    @commit_sha_before = "4c8124ffcf4039d292442eeccabdeca5af5c5017"
    @commit_sha_after = "a47fd41f3aa4610ea527dcc1669dfdb9c15c5425"
    @branch = "master"
    @ref = "refs/heads/master"
    @message = {
      before: @commit_sha_before,
      after: @commit_sha_after,
      ref: @ref,
      repository_id: @repository.id,
      pusher_id: @user.id,
      pushed_at: Time.now
    }

    @codespaces_app = create(:codespaces_integration)
    @actions_app = create(:launch_integration)
    create(:codespace, repository: @repository, billable_owner: @organization, owner: @user)
  end

  setup do
    GitHub.stubs(:actions_enabled?).returns(true)
    GitHub.stubs(:launch_github_app).returns(@actions_app)
  end

  # these are quick tests to make sure that getting these events calls the respective commands
  test "plan change is processed", skip_enterprise: true do
    @organization = create(:business_plus_organization)
    Codespaces::ProcessPlanChange.expects(:call).with(user_id: @organization.id, old_plan_name: "business", new_plan_name: "free")

    GlobalInstrumenter.instrument("billing.plan_change", {
      user_id: @organization.id,
      old_plan_name: "business",
      new_plan_name: "free"
    })
  end

  test "organization disables all codespaces", skip_enterprise: true do
    @organization = create(:business_plus_organization)
    @user = create(:user)
    @organization.add_member(@user)
    @repository = create(:repository, owner: @organization)
    @codespace = create(:codespace, repository: @repository, owner: @user)

    Codespaces::FindAffectedCodespacesByOrganization.expects(:call)
      .with(organization_id: @organization.id, disabled: true, deletion_reason: Codespace.deletion_reasons[:org_disabled_codespaces])
    Codespaces::UpdateTrustedRepositoryAccess.expects(:call).with(
      actor: @organization.admins.first,
      target: @organization,
      trusted_repo_setting: Configurable::CodespaceTrustedRepositories::DISABLED,
      repo: nil,
      entry_point: :codespaces_subscribers_org_codespaces_disabled_event
    )

    GlobalInstrumenter.instrument(::Codespaces::Events::ORG_CODESPACES_DISABLED, {
      actor_id: @organization.admins.first.id,
      organization_id: @organization.id,
    })
  end

  test "organization disables all codespaces - non billing", skip_enterprise: true do
    @organization = create(:business_plus_organization)
    @user = create(:user)
    @organization.add_member(@user)
    @repository = create(:repository, owner: @organization)
    @codespace = create(:codespace, repository: @repository, owner: @user)

    Codespaces::UpdateCodespacesEnablementByOrganization.expects(:call).with(organization_id: @organization.id, disabled: true)
    Codespaces::UpdateTrustedRepositoryAccess.expects(:call).with(
      actor: @organization.admins.first,
      target: @organization,
      trusted_repo_setting: Configurable::CodespaceTrustedRepositories::DISABLED,
      repo: nil,
      entry_point: :codespaces_subscribers_org_repo_owned_codespaces_disabled_event
    )

    GlobalInstrumenter.instrument(::Codespaces::Events::ORG_REPO_OWNED_CODESPACES_DISABLED, {
      actor_id: @organization.admins.first.id,
      organization_id: @organization.id,
    })
  end

  test "organization enables all users for codespaces", skip_enterprise: true do
    @organization = create(:business_plus_organization)
    @user = create(:user)
    @organization.add_member(@user)
    @repository = create(:repository, owner: @organization)
    @codespace = create(:codespace, repository: @repository, owner: @user)

    @mock_command = mock("Codespaces::FindAffectedCodespacesByOrganization")
    @mock_command.stubs(:call).returns(true)
    Codespaces::FindAffectedCodespacesByOrganization.expects(:new).with(organization_id: @organization.id).returns(@mock_command)

    GlobalInstrumenter.instrument(::Codespaces::Events::ORG_CODESPACES_ENABLED, {
      organization_id: @organization.id,
    })
  end

  test "organization disables single user for codespaces", skip_enterprise: true do
    @organization = create(:business_plus_organization)
    @user = create(:user)
    @organization.add_member(@user)
    @repository = create(:repository, owner: @organization)
    @codespace = create(:codespace, repository: @repository, owner: @user)

    @mock_command = mock("Codespaces::FindAffectedCodespacesByUser")
    @mock_command.stubs(:call).returns(true)
    Codespaces::FindAffectedCodespacesByUser.expects(:new).with(user_id: @user.id, deletion_reason: Codespace.deletion_reasons[:org_disabled_for_user]).returns(@mock_command)

    GlobalInstrumenter.instrument(::Codespaces::Events::ORG_CODESPACES_DISABLED_USER, {
      user_id: @user.id
    })
  end

  test "organization enables single user for codespaces", skip_enterprise: true do
    @organization = create(:business_plus_organization)
    @user = create(:user)
    @organization.add_member(@user)
    @repository = create(:repository, owner: @organization)
    @codespace = create(:codespace, repository: @repository, owner: @user)

    @mock_command = mock("Codespaces::FindAffectedCodespacesByUser")
    @mock_command.stubs(:call).returns(true)
    Codespaces::FindAffectedCodespacesByUser.expects(:new).with(user_id: @user.id).returns(@mock_command)

    GlobalInstrumenter.instrument(::Codespaces::Events::ORG_CODESPACES_ENABLED_USER, {
      user_id: @user.id
    })
  end

  context "codespaces.repository_changed", skip_enterprise: true do
    test "call :perform_later on CodespacesProcessSystemEventJob" do
      codespace = create(:codespace)

      CodespacesProcessSystemEventJob.expects(:perform_later).once.with(codespaces: [codespace])

      GlobalInstrumenter.instrument("codespaces.repository_changed", {
        codespace: codespace,
      })
    end
  end

  context "enqueues find unbillables jobs", skip_enterprise: true do
    test "on repository access change with codespace" do
      @codespace = create(:codespace, repository: @repository, owner: @user)
      Codespaces::FindAffectedCodespacesByRepositoryAccessChange.expects(:call).with(user: @user, repository_ids: [@repository.id], deletion_reason: Codespace.deletion_reasons[:lost_repo_access])

      GlobalInstrumenter.instrument(GlobalEvents::User::REPOSITORY_ACCESS_CHANGED, {
        user: @user,
        repository_ids: [@repository.id],
      })
    end

    test "on repository access change with no codepsace but has gpg authorization" do
      @authorization = create(:codespace_trusted_repository_authorization, repository: @repository, user: @user)
      Codespaces::FindAffectedCodespacesByRepositoryAccessChange.expects(:call).with(user: @user, repository_ids: [@repository.id], deletion_reason: Codespace.deletion_reasons[:lost_repo_access])

      GlobalInstrumenter.instrument(GlobalEvents::User::REPOSITORY_ACCESS_CHANGED, {
        user: @user,
        repository_ids: [@repository.id],
      })
    end

    test "on repository access change with codepsace and gpg authorization performs once" do
      @codespace = create(:codespace, repository: @repository, owner: @user)
      @authorization = create(:codespace_trusted_repository_authorization, repository: @repository, user: @user)
      Codespaces::FindAffectedCodespacesByRepositoryAccessChange.expects(:call).with(user: @user, repository_ids: [@repository.id], deletion_reason: Codespace.deletion_reasons[:lost_repo_access])

      GlobalInstrumenter.instrument(GlobalEvents::User::REPOSITORY_ACCESS_CHANGED, {
        user: @user,
        repository_ids: [@repository.id],
      })
    end

    test "on repository access change with no codespace or gpg authorization" do
      Codespaces::FindAffectedCodespacesByRepositoryAccessChange.expects(:call).with(user: @user, repository_ids: [@repository.id], deletion_reason: Codespace.deletion_reasons[:lost_repo_access])

      GlobalInstrumenter.instrument(GlobalEvents::User::REPOSITORY_ACCESS_CHANGED, {
        user: @user,
        repository_ids: [@repository.id],
      })
    end

    test "when a repository goes private" do
      Codespaces::FindAffectedCodespacesByRepository.expects(:call).once.with(repository_id: @repository.id, deletion_reason: Codespace.deletion_reasons[:repository_made_private])

      GlobalInstrumenter.instrument("repository.visibility_changed", {
        repository_id: @repository.id,
        is_private: true
      })


      GlobalInstrumenter.instrument("repository.visibility_changed", {
        repository_id: @repository.id,
        is_private: false
      })
    end

    test "on repository removal" do
      @mock_command = mock("Codespaces::FindAffectedCodespacesByRepository")
      @mock_command.stubs(:call).returns(true)
      Codespaces::FindAffectedCodespacesByRepository.expects(:new).with(repository_id: @repository.id, deletion_reason: Codespace.deletion_reasons[:repository_removed]).returns(@mock_command)

      GlobalInstrumenter.instrument(GlobalEvents::Repository::REMOVED, {
        repository_id: @repository.id,
      })
    end
  end

  context "'Codespaces::Events::INACCESSIBLE_CODESPACE subscription event", skip_enterprise: true do
    test "does not call :perform_later on CodespacesProcessSystemEventJob when the payload has a NULL value for codespace_id" do
      CodespacesProcessSystemEventJob.expects(:perform_later).never

      GlobalInstrumenter.instrument(Codespaces::Events::INACCESSIBLE_CODESPACE, {
        codespace_id: nil,
      })
    end

    test "does not call :perform_later on CodespacesProcessSystemEventJob when the payload for codespace_id is not associated to a Codespace" do
      CodespacesProcessSystemEventJob.expects(:perform_later).never

      # We need to make sure we provide an id that does not exist so this test is not flaky
      unassociated_id = Codespace.maximum(:id) + 1

      GlobalInstrumenter.instrument(Codespaces::Events::INACCESSIBLE_CODESPACE, {
        codespace_id: unassociated_id,
      })
    end

    test "call :perform_later on CodespacesProcessSystemEventJob when the payload for codespace_id is associated to a Codespace" do
      codespace = create(:codespace)
      GitHub.flipper[:codespaces_skip_transfer_for_inaccessible].enable(codespace.owner)
      CodespacesProcessSystemEventJob.expects(:perform_later).with(codespaces: [codespace], transfer_billable_owner: false, deletion_reason: Codespace.deletion_reasons[:inaccessible])

      GlobalInstrumenter.instrument(Codespaces::Events::INACCESSIBLE_CODESPACE, {
        codespace_id: codespace.id,
      })
    end

    test "call :perform_later on CodespacesProcessSystemEventJob when the payload for codespace_id is associated to a Codespace - ff off" do
      codespace = create(:codespace)
      GitHub.flipper[:codespaces_skip_transfer_for_inaccessible].disable(codespace.owner)
      CodespacesProcessSystemEventJob.expects(:perform_later).with(codespaces: [codespace], transfer_billable_owner: true, deletion_reason: Codespace.deletion_reasons[:inaccessible])

      GlobalInstrumenter.instrument(Codespaces::Events::INACCESSIBLE_CODESPACE, {
        codespace_id: codespace.id,
      })
    end
  end

  context "marking a user as spammy", skip_enterprise: true do
    test "will call Codespaces::HandleSpammyUser with the correct arguments" do
      user = create(:user)

      Codespaces::HandleSpammyUser.expects(:call).with(user_id: user.id, user_type: "User")
      user.mark_as_spammy
    end
  end

  context "marking an organization as spammy", skip_enterprise: true do
    test "will call Codespaces::HandleSpammyUser with the correct arguments" do
      organization = create(:organization)

      Codespaces::HandleSpammyUser.expects(:call).with(user_id: organization.id, user_type: "Organization")
      organization.mark_as_spammy
    end
  end

  context "suspending a user", skip_enterprise: true do
    test "will call Codespaces::HandleSpammyUser with the correct arguments" do
      user = create(:user)

      Codespaces::HandleSpammyUser.expects(:call).with(user_id: user.id, user_type: "User")
      user.suspend("suspension reason")
    end
  end

  context "suspending an organization", skip_enterprise: true do
    test "will call Codespaces::HandleSpammyUser with the correct arguments" do
      organization = create(:organization)

      Codespaces::HandleSpammyUser.expects(:call).with(user_id: organization.id, user_type: "Organization")
      organization.suspend("suspension reason")
    end
  end

  context "repository_changed", skip_enterprise: true do
    test "queues `TransferPrebuildTemplateOwnerByRepositoryJob` when expected" do
      repo = create(:repository)
      rando = create(:user)

      # Prebuild templates should exist on repo
      create(:codespace_prebuild_template, repository: repo)

      Codespaces::TransferPrebuildTemplateOwnerByRepositoryJob.expects(:perform_later).once.with(repository: repo)

      GlobalInstrumenter.instrument("search_indexing.repository_changed", {
        repository: repo,
        change: :OWNER_CHANGED,
      })
    end

    test "next unless owner changed event" do
      repo = create(:repository)
      rando = create(:user)

      # Prebuild templates should exist on repo
      create(:codespace_prebuild_template, repository: repo)

      Codespaces::TransferPrebuildTemplateOwnerByRepositoryJob.expects(:perform_later).with(repository: repo).never

      GlobalInstrumenter.instrument("search_indexing.repository_changed", {
        repository: repo,
        change: :PUSH,
      })
    end

    test "next if no prebuild template exists on the repo" do
      repo = create(:repository)
      rando = create(:user)

      Codespaces::TransferPrebuildTemplateOwnerByRepositoryJob.expects(:perform_later).with(repository: repo).never

      GlobalInstrumenter.instrument("search_indexing.repository_changed", {
        repository: repo,
        change: :OWNER_CHANGED,
      })
    end
  end

  context "notify prebuild_configuration_workflow_run channel", skip_enterprise: true do
    test "notify channel after CreatePrebuildTemplateDynamicWorkflow call and at check suite update" do
      repo = create(:repository, owner: @user, from_example: :simple)

      workflow_file_path = Codespaces::Prebuilds.workflow_path(:production)
      commit = create(:commit, repository: repo, branch: @branch, create_branch: false)
      check_suite = create(:check_suite, github_app: @actions_app, repository: repo, head_sha: commit.oid, name: "Codespaces Prebuilds", workflow_file_path: workflow_file_path)
      prebuild_configuration = create(:codespace_prebuild_configuration, repository: repo, branch: @branch)

      expected_result = TwirpResponse.new(
        value: GitHub::Launch::Services::Deploy::RunDynamicWorkflowResponse.new(
          execution_id: "123",
          workflow_run_id: check_suite.workflow_run.id,
        ),
        status: 200,
        call_succeeded: true,
      )

      repo.expects(:run_dynamic_workflow).returns(
        expected_result
      )

      GitHub::WebSocket.expects(:notify_prebuild_configuration_workflow_run_channel).with(
        prebuild_configuration,
        GitHub::WebSocket::Channels.prebuild_configuration_workflow_run(prebuild_configuration)
      )

      Codespaces::CreatePrebuildTemplateDynamicWorkflow.call(
        repository: repo,
        branch: @branch,
        locations: ["WestUs2"],
        commit_sha: commit.oid,
        concurrency_modifier: prebuild_configuration.id.to_s,
        configuration: prebuild_configuration,
      )

      GitHub::WebSocket.expects(:notify_prebuild_configuration_workflow_run_channel).with(
        prebuild_configuration,
        GitHub::WebSocket::Channels.prebuild_configuration_workflow_run(prebuild_configuration)
      )

      check_suite.update!(status: "completed", conclusion: "success", completed_at: Time.now)
    end
  end

  context "secret change triggers update of all secrets for impacted codespaces", skip_enterprise: true do
    context "#user_secrets" do
      test "process when a codespaces user_secret is added" do
        Codespaces::ProcessUserSecretUpdatesJob.expects(:perform_later).with(selected_repository_global_ids: selected_repository_global_ids, user: @user).once
        GlobalInstrumenter.instrument("user_secret.create", {
          app: @codespaces_app,
          owner: @user,
          actor: @user,
          name: :secret_name,
          selected_repositories: selected_repository_global_ids,
          state: "CREATED",
        })
      end

      test "do not process when a non-codespaces user_secret is added" do
        Codespaces::ProcessUserSecretUpdatesJob.expects(:perform_later).never
        GlobalInstrumenter.instrument("user_secret.create", {
          app: @actions_app,
          owner: @user,
          actor: @user,
          name: :secret_name,
          selected_repositories: selected_repository_global_ids,
          state: "CREATED",
        })
      end

      test "process when a codespaces user_secret is removed" do
        Codespaces::ProcessUserSecretUpdatesJob.expects(:perform_later).with(selected_repository_global_ids: selected_repository_global_ids, user: @user).once
        GlobalInstrumenter.instrument("user_secret.remove", {
          app: @codespaces_app,
          owner: @user,
          actor: @user,
          name: :secret_name,
          selected_repositories: selected_repository_global_ids,
          state: "DELETED",
        })
      end

      test "do not process when a non-codespaces user_secret is removed" do
        Codespaces::ProcessUserSecretUpdatesJob.expects(:perform_later).never
        GlobalInstrumenter.instrument("user_secret.remove", {
          app: @actions_app,
          owner: @user,
          actor: @user,
          name: :secret_name,
          selected_repositories: selected_repository_global_ids,
          state: "DELETED",
        })
      end

      test "process when a codespaces user_secret is updated" do
        Codespaces::ProcessUserSecretUpdatesJob.expects(:perform_later).with(selected_repository_global_ids: selected_repository_global_ids, user: @user).once
        GlobalInstrumenter.instrument("user_secret.update", {
          app: @codespaces_app,
          owner: @user,
          actor: @user,
          name: :secret_name,
          selected_repositories: selected_repository_global_ids,
          state: "UPDATED",
        })
      end

      test "do not process when a non-codespaces user_secret is updated" do
        Codespaces::ProcessUserSecretUpdatesJob.expects(:perform_later).never
        GlobalInstrumenter.instrument("user_secret.update", {
          app: @actions_app,
          owner: @user,
          actor: @user,
          name: :secret_name,
          selected_repositories: selected_repository_global_ids,
          state: "UPDATED",
        })
      end
    end

    context "#repository_secrets" do
      test "process when a codespaces repository_secret is added" do
        Codespaces::ProcessRepositorySecretUpdatesJob.expects(:perform_later).with(repository: @repository).once
        GlobalInstrumenter.instrument("repository_secret.create", {
          app: @codespaces_app,
          owner: @repository,
          actor: @user,
          name: :secret_name,
          selected_repositories: [],
          state: "CREATED",
        })
      end

      test "do not process when a non-codespaces repository_secret is added" do
        Codespaces::ProcessRepositorySecretUpdatesJob.expects(:perform_later).never
        GlobalInstrumenter.instrument("repository_secret.create", {
          app: @actions_app,
          owner: @repository,
          actor: @user,
          name: :secret_name,
          selected_repositories: [],
          state: "CREATED",
        })
      end

      test "process when a codespaces repository_secret is removed" do
        Codespaces::ProcessRepositorySecretUpdatesJob.expects(:perform_later).with(repository: @repository).once
        GlobalInstrumenter.instrument("repository_secret.remove", {
          app: @codespaces_app,
          owner: @repository,
          actor: @user,
          name: :secret_name,
          selected_repositories: [],
          state: "DELETED",
        })
      end

      test "do not process when a non-codespaces repository_secret is removed" do
        Codespaces::ProcessRepositorySecretUpdatesJob.expects(:perform_later).never
        GlobalInstrumenter.instrument("repository_secret.remove", {
          app: @actions_app,
          owner: @repository,
          actor: @user,
          name: :secret_name,
          selected_repositories: [],
          state: "DELETED",
        })
      end

      test "process when a codespaces repository_secret is updated" do
        Codespaces::ProcessRepositorySecretUpdatesJob.expects(:perform_later).with(repository: @repository).once
        GlobalInstrumenter.instrument("repository_secret.remove", {
          app: @codespaces_app,
          owner: @repository,
          actor: @user,
          name: :secret_name,
          selected_repositories: [],
          state: "UPDATED",
        })
      end

      test "do not process when a non-codespaces repository_secret is updated" do
        Codespaces::ProcessRepositorySecretUpdatesJob.expects(:perform_later).never
        GlobalInstrumenter.instrument("repository_secret.remove", {
          app: @actions_app,
          owner: @repository,
          actor: @user,
          name: :secret_name,
          selected_repositories: [],
          state: "UPDATED",
        })
      end
    end

    context "#org_secrets" do
      test "process when a codespaces org_secret is added" do
        Codespaces::ProcessOrgSecretUpdatesJob.expects(:perform_later).with(selected_repository_global_ids: selected_repository_global_ids, org: @organization).once
        GlobalInstrumenter.instrument("org_secret.create", {
          app: @codespaces_app,
          owner: @organization,
          actor: @user,
          name: :secret_name,
          selected_repositories: selected_repository_global_ids,
          state: "CREATED",
        })
      end

      test "do not process when a non-codespaces org_secret is added" do
        Codespaces::ProcessOrgSecretUpdatesJob.expects(:perform_later).never
        GlobalInstrumenter.instrument("org_secret.create", {
          app: @actions_app,
          owner: @organization,
          actor: @user,
          name: :secret_name,
          selected_repositories: selected_repository_global_ids,
          state: "CREATED",
        })
      end

      test "process when a codespaces org_secret is removed" do
        Codespaces::ProcessOrgSecretUpdatesJob.expects(:perform_later).with(selected_repository_global_ids: selected_repository_global_ids, org: @organization).once
        GlobalInstrumenter.instrument("org_secret.remove", {
          app: @codespaces_app,
          owner: @organization,
          actor: @user,
          name: :secret_name,
          selected_repositories: selected_repository_global_ids,
          state: "DELETED",
        })
      end

      test "do not process when a non-codespaces org_secret is removed" do
        Codespaces::ProcessOrgSecretUpdatesJob.expects(:perform_later).never
        GlobalInstrumenter.instrument("org_secret.remove", {
          app: @actions_app,
          owner: @organization,
          actor: @user,
          name: :secret_name,
          selected_repositories: selected_repository_global_ids,
          state: "DELETED",
        })
      end

      test "process when a codespaces org_secret is updated" do
        Codespaces::ProcessOrgSecretUpdatesJob.expects(:perform_later).with(selected_repository_global_ids: selected_repository_global_ids, org: @organization).once
        GlobalInstrumenter.instrument("org_secret.update", {
          app: @codespaces_app,
          owner: @organization,
          actor: @user,
          name: :secret_name,
          selected_repositories: selected_repository_global_ids,
          state: "UPDATED",
        })
      end

      test "do not process when a non-codespaces org_secret is updated" do
        Codespaces::ProcessOrgSecretUpdatesJob.expects(:perform_later).never
        GlobalInstrumenter.instrument("org_secret.update", {
          app: @actions_app,
          owner: @organization,
          actor: @user,
          name: :secret_name,
          selected_repositories: selected_repository_global_ids,
          state: "UPDATED",
        })
      end
    end
  end

  def selected_repository_global_ids
    [@repository.global_relay_id]
  end

  context "ORG_CODESPACES_OWNERSHIP_SETTING_UPDATED", skip_enterprise: true do
    test "call :perform_later on CodespacesProcessSystemEventJob" do
      codespace = create(:codespace)

      Codespaces::FindAffectedCodespacesByOrganization.expects(:call).once.with(organization_id: codespace.billable_owner.id)

      GlobalInstrumenter.instrument(Codespaces::Events::ORG_CODESPACES_OWNERSHIP_SETTING_UPDATED,
        {
          actor_id: codespace.owner.id,
          organization_id: codespace.billable_owner.id,
        })
    end
  end
end
