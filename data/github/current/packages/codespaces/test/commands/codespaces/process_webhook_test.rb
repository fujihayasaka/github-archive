# typed: true
# frozen_string_literal: true

require "test_helper"

class Codespaces::ProcessWebhookTest < GitHub::TestCase
  skip_in_multitenant_mode
  include DogstatsTestHelpers
  include HydroTestHelpers
  include GitHub::LoggerHelper

  fixtures do
    @owner = create(:user)
    repo = create(:repository, owner: @owner, from_example: :emojis)
    @codespace = create(:codespace, repository: repo)
    @copilot_workspace_codespace = create(:copilot_workspace, repository: repo, owner: @owner)

    @git_status = {
      "commit" => "fceb75e8995eaa6eb5c996111dc2bf7d8679cd99",
      "branch" => "master",
      "hasUncommittedChanges" => true,
      "ahead" => 3,
      "behind" => 21
    }
    @valid_payload = {
      id: @codespace.guid,
      friendlyName: @codespace.name,
      state: Codespaces::Vscs::State::AVAILABLE,
      gitStatus: @git_status
    }
    @null_state_payload = {
      id: @codespace.guid,
      friendlyName: @codespace.name,
    }

    @copilot_workspace_payload = {
      id: @copilot_workspace_codespace.guid,
      friendlyName: @copilot_workspace_codespace.name,
      state: Codespaces::Vscs::State::AVAILABLE,
      gitStatus: @git_status
    }
  end

  setup do
    @stale_payload = @valid_payload.merge(updated: 5.minutes.ago.iso8601)
  end

  context "stale webhook processing" do
    test "it updates the codespace's environment_data if there is none set" do
      @codespace.update(environment_data: nil)
      assert_changes(-> { @codespace.reload.environment_data }) do
        Codespaces::ProcessWebhook.call(@stale_payload)
      end
    end

    test "it updates the codespace's environment_data if the webhook is newer" do
      @codespace.merge_environment_data!({ state: Codespaces::Vscs::State::SHUTDOWN, updated: 10.minutes.ago.iso8601 })
      assert_changes(-> { @codespace.reload.environment_data }) do
        Codespaces::ProcessWebhook.call(@stale_payload)
      end
    end

    test "it does not update the codespace's environment_data if the webhook is stale" do
      @codespace.merge_environment_data!({ state: Codespaces::Vscs::State::SHUTDOWN, updated: Time.now.iso8601 })
      assert_no_changes(-> { @codespace.reload.environment_data }) do
        Codespaces::ProcessWebhook.call(@stale_payload)
      end
    end

    test "it updates the environment_data if the webhook is missing the updated attribute" do
      @codespace.merge_environment_data!({ state: Codespaces::Vscs::State::SHUTDOWN, updated: Time.now.iso8601 })
      assert_changes(-> { @codespace.reload.environment_data }) do
        Codespaces::ProcessWebhook.call(@valid_payload)
      end
    end
  end

  context "PR updates" do
    test "it updates the codespace's PR when the branch changes" do
      refute @codespace.pull_request
      pr_branch = "master-merged-topic"
      example_repo :pull_request_source, @codespace.repository
      pull_request = create(:pull_request, user: @codespace.owner, repository: @codespace.repository, base_repository: @codespace.repository, head_repository: @codespace.repository, head_ref: pr_branch)
      # Pretend we checked out the PR branch in our codespace and got the update from VSCS
      Codespaces::ProcessWebhook.call(@valid_payload.merge(gitStatus: { "branch" => pr_branch }))
      @codespace.reload
      # Verify that we dynamically reassociated the codespace to the PR
      assert_equal pull_request, @codespace.pull_request
      # Also adds a PR source to preserve history
      assert @codespace.pull_request.pull_request_sources.where(source: :codespace).exists?
    end

    test "it does not attempt to find a PR when we don't have a current_branch set yet but the base ref matches the PR's ref" do
      refute @codespace.pull_request
      pr_branch = "master-merged-topic"
      example_repo :pull_request_source, @codespace.repository
      pull_request = create(:pull_request, user: @codespace.owner, repository: @codespace.repository, base_repository: @codespace.repository, head_repository: @codespace.repository, head_ref: pr_branch)
      Codespaces::FindPullRequest.expects(:call).never
      @codespace.update!(ref: pr_branch)
      Codespaces::ProcessWebhook.call(@valid_payload.merge(gitStatus: { "branch" => pr_branch }))
    end


    test "it removes the codespace's PR association when the branch changes to one not for a PR" do
      repo = create(:repository, from_example: :pull_request_source)
      pr_branch = "master-merged-topic"
      pull_request = create(:pull_request, user: @codespace.owner, repository: repo, base_repository: repo, head_repository: repo, head_ref: pr_branch)
      pull_request.pull_request_sources.create(source: :codespace)
      codespace = create(:codespace, repository: repo, pull_request: pull_request)
      assert codespace.pull_request
      # Pretend we checked out the PR branch in our codespace and got the update from VSCS
      Codespaces::ProcessWebhook.call(@valid_payload.merge(id: codespace.guid, friendlyName: codespace.name, gitStatus: { "branch" => "not-the-pr-branch" }))
      codespace.reload
      # Verify that we removed the PR association
      refute codespace.pull_request
      # It leaves the PR source as :codespace
      pull_request.reload
      assert pull_request.pull_request_sources.where(source: :codespace).exists?
    end

    test "doesn't change a codespace's PR if multiple PRs with the branch exist" do
      refute @codespace.pull_request
      pr_branch = "master-merged-topic"
      example_repo :pull_request_source, @codespace.repository
      pull1 = create(:pull_request, user: @codespace.owner, repository: @codespace.repository, base_repository: @codespace.repository, head_repository: @codespace.repository, head_ref: pr_branch)
      pull2 = create(:pull_request, user: @codespace.owner, repository: @codespace.repository, base_repository: @codespace.repository, head_repository: @codespace.repository, base_ref: "topic-partial-merge", head_ref: pr_branch)
      # Pretend we checked out the PR branch in our codespace and got the update from VSCS
      Codespaces::ProcessWebhook.call(@valid_payload.merge(gitStatus: { "branch" => pr_branch }))
      @codespace.reload
      # Verify that we didn't assign either pull1 or pull2 since we can't tell them apart
      refute @codespace.pull_request
    end

    test "sets the codespace's PR to another user's PR assuming push access to the repository/ref" do
      enable_feature_flag(:codespaces_unscoped_find_pr, @codespace.owner)
      refute @codespace.pull_request
      pr_branch = "master-merged-topic"
      example_repo :pull_request_source, @codespace.repository
      pull_request = create(:pull_request, repository: @codespace.repository, base_repository: @codespace.repository, head_repository: @codespace.repository, head_ref: pr_branch)
      # Pretend we checked out the PR branch in our codespace and got the update from VSCS
      Codespaces::ProcessWebhook.call(@valid_payload.merge(gitStatus: { "branch" => pr_branch }))
      @codespace.reload
      # Verify that we used the existing PR
      assert_equal pull_request, @codespace.pull_request
    end

    test "doesn't associate the codespace with the PR if the user lacks push access" do
      codespace = create(:codespace, repository: @codespace.repository, make_collaborator: false)
      refute @codespace.pull_request
      pr_branch = "master-merged-topic"
      example_repo :pull_request_source, @codespace.repository
      pull_request = create(:pull_request, repository: @codespace.repository, base_repository: @codespace.repository, head_repository: @codespace.repository, head_ref: pr_branch)
      # Pretend we checked out the PR branch in our codespace and got the update from VSCS
      Codespaces::ProcessWebhook.call(@valid_payload.merge(id: codespace.guid, friendlyName: codespace.name, gitStatus: { "branch" => pr_branch }))
      codespace.reload
      # Verify that we didn't get associated to the PR
      refute codespace.pull_request
    end

    test "doesn't change the codespace's PR if the PR's head ref equals the head repo's default branch" do
      refute @codespace.pull_request
      pr_branch = @codespace.repository.default_branch
      example_repo :pull_request_source, @codespace.repository
      pull_request = create(:pull_request, user: @codespace.owner, repository: @codespace.repository, base_repository: @codespace.repository, head_repository: @codespace.repository, base_ref: "conflicts", head_ref: pr_branch)
      # Pretend we checked out the PR branch in our codespace and got the update from VSCS
      Codespaces::ProcessWebhook.call(@valid_payload.merge(gitStatus: { "branch" => pr_branch }))
      @codespace.reload
      # Verify that we did NOT change the codespace's PR to one on the default branch
      refute_equal pull_request, @codespace.pull_request
    end
  end

  context "spammy owner handling" do
    test "it deprovisions a codespace when the user is spammy and the codespace is not provisioned", spammy_only: true do
      @codespace.update!(guid: nil, state: :provisioning)
      @codespace.owner.mark_as_spammy

      Codespaces::ProcessWebhook.call(@valid_payload)

      @codespace.reload
      assert @codespace.deprovisioning?
      assert @codespace.guid.present?
    end

    test "it deprovisions a codespace when billable owner is spammy and the codespace is not provisioned", spammy_only: true do
      organization = create(:organization)

      @codespace.update!(guid: nil, state: :provisioning, billable_owner: organization)
      @codespace.owner.mark_as_spammy

      Codespaces::ProcessWebhook.call(@valid_payload)

      @codespace.reload
      assert @codespace.deprovisioning?
      assert_equal @codespace.guid, @valid_payload[:id]
    end

    test "it does nothing when the billable owner is spammy and the codespace is provisioned", spammy_only: true do
      organization = create(:organization)
      @codespace.update!(state: :provisioned, billable_owner: organization)
      @codespace.owner.mark_as_spammy

      Codespaces::ProcessWebhook.call(@valid_payload)

      @codespace.reload
      refute @codespace.deprovisioning?
    end
  end

  test "doesn't explode with a deleted owner" do
    @codespace.owner.delete

    assert_nothing_raised do
      Codespaces::ProcessWebhook.call(@valid_payload)
    end
  end

  test "makes datadog increment on missing guid" do
    @codespace.update!(state: :provisioning, guid: nil)
    Codespaces::ProcessWebhook.call(@valid_payload)

    assert_dogstats_increment(1, "codespaces.process_webhook.missing_guid")
  end

  test "makes datadog increment on mismatched guid but doesn't update the codespace" do
    expected_keys = {
      "gh.codespaces.name" => @codespace.name,
      "gh.codespaces.guid" => @codespace.guid,
      "gh.codespaces.orphaned_guid" => "invalid",
    }

    assert_logged(Body: "codespace webhook received from orphanced codespace with mismatched guid", **expected_keys) do
      Codespaces::ProcessWebhook.call(@valid_payload.merge(id: "invalid"))
    end
    assert_dogstats_increment(1, "codespaces.process_webhook.mismatched_guids")
    refute_equal "invalid", @codespace.reload.environment_data.id
  end

  test "it properly finds soft-deleted codespaces" do
    @codespace.soft_delete
    Codespaces::ProcessWebhook.call(@valid_payload)
    @codespace.reload
    assert_equal Codespaces::Vscs::State::AVAILABLE, @codespace.environment_data.state
    assert_equal @git_status, @codespace.environment_data.git_status
  end

  test "updates environment_data if present and the codespace validation fails" do
    Codespace.any_instance.expects(:update!).raises(ActiveRecord::RecordInvalid)

    payload = @codespace.environment_data.merge(
      friendlyName: @codespace.name,
      last_state_update_reason: "boop"
    )
    Codespaces::ProcessWebhook.call(payload)
    @codespace.reload
    assert_equal "boop", @codespace.environment_data.last_state_update_reason
  end

  test "it reports an error but updates anyways when the payload has no state" do
    Codespaces::ErrorReporter.expects(:report).with { |error, _| error.kind_of?(Codespaces::NullStateCodespaceError) }
    assert_nothing_raised do
      Codespaces::ProcessWebhook.call(@null_state_payload)
    end
    assert_equal "Available", @codespace.reload.environment_data.state
  end

  test "deprovisions a codespace when the service reports that it failed" do
    codespace = create(:codespace)

    payload = {
      id: codespace.guid,
      friendlyName: codespace.name,
      state: Codespaces::Vscs::State::FAILED,
      gitStatus: @git_status
    }

    Codespaces::ProcessWebhook.call(payload)
    codespace.reload
    assert_equal Codespaces::Vscs::State::FAILED, codespace.environment_data.state
    assert codespace.deprovisioning?
  end

  test "records when a codespace is shutdown" do
    codespace = create(:codespace, :provisioning)

    payload = {
      id: codespace.guid,
      friendlyName: codespace.name,
      state: Codespaces::Vscs::State::SHUTDOWN,
      gitStatus: @git_status
    }

    freeze_time do
      Codespaces::ProcessWebhook.call(payload)
      codespace.reload
      assert_equal Codespaces::Vscs::State::SHUTDOWN, codespace.environment_data.state
      assert_equal Time.now, codespace.shutdown_at
    end
  end

  test "doesn't change shutdown if given a stale payload" do
    codespace = create(:codespace, :provisioned)

    freeze_time do
      payload = {
        id: codespace.guid,
        friendlyName: codespace.name,
        state: Codespaces::Vscs::State::SHUTDOWN,
        gitStatus: @git_status,
        updated: 5.minutes.ago.iso8601
      }
      codespace.merge_environment_data!({ state: Codespaces::Vscs::State::AVAILABLE, updated: Time.now.iso8601 })
      Codespaces::ProcessWebhook.call(payload)
      codespace.reload
      # These values should not have changed from the stale webhook payload being processed
      assert_equal Codespaces::Vscs::State::AVAILABLE, codespace.environment_data.state
      refute codespace.shutdown_at
    end
  end

  test "records when a codespace is shutdown and is already shut down" do
    codespace = create(:codespace, :provisioning)
    codespace.merge_environment_data!({ state: Codespaces::Vscs::State::SHUTDOWN })

    payload = {
      id: codespace.guid,
      friendlyName: codespace.name,
      state: Codespaces::Vscs::State::SHUTDOWN,
      gitStatus: @git_status
    }

    freeze_time do
      Codespaces::ProcessWebhook.call(payload)
      codespace.reload
      assert_equal Codespaces::Vscs::State::SHUTDOWN, codespace.environment_data.state

      assert_equal Time.now, codespace.shutdown_at
    end
  end

  test "instruments suspend_environment when codespaces_improved_shutdown_auditing is enabled and not recently recorded" do
    enable_feature_flag(:codespaces_improved_shutdown_auditing)
    events = subscribe "codespaces.suspend_environment"

    codespace = create(:codespace, :provisioning)

    payload = {
      id: codespace.guid,
      friendlyName: codespace.name,
      state: Codespaces::Vscs::State::SHUTDOWN,
      gitStatus: @git_status
    }

    Codespaces::ProcessWebhook.call(payload)
    codespace.reload
    assert_equal Codespaces::Vscs::State::SHUTDOWN, codespace.environment_data.state

    expected_payload = {
      actor: nil, # GitHub System event since this would happen via idle timeout
      codespace_id: codespace.id,
      location: codespace.location,
      name: codespace.name,
      oid: codespace.oid,
      org: nil,
      owner: codespace.owner.login,
      owner_id: codespace.owner.id,
      pull_request_id: nil,
      ref: codespace.ref,
      sku_name: codespace.sku_name,
      user_id: codespace.owner.id,
      user: codespace.owner.login,
      repo: codespace.repository.nwo,
      repo_id: codespace.repository.id,
      public_repo: codespace.repository.public?,
      devcontainer_path: codespace.devcontainer_path,
      machine_type: codespace.sku&.display_name,
    }
    if codespace.billable_owner.organization?
      expected_payload[:org] = codespace.billable_owner.display_login
      expected_payload[:org_id] = codespace.billable_owner_id
    end

    assert event = events.pop, "an event was expected"
    assert_equal expected_payload, event.payload
  end

  test "skips instrumentation of suspend_environment when codespaces_improved_shutdown_auditing is enabled and recently recorded" do
    enable_feature_flag(:codespaces_improved_shutdown_auditing)

    codespace = create(:codespace, :provisioning)

    # Simulate recently instrumenting suspend like SuspendEnvironment command does normally
    Codespaces::InstrumentSuspend.call(codespace:)

    events = subscribe "codespaces.suspend_environment"

    payload = {
      id: codespace.guid,
      friendlyName: codespace.name,
      state: Codespaces::Vscs::State::SHUTDOWN,
      gitStatus: @git_status
    }

    Codespaces::ProcessWebhook.call(payload)
    assert_equal events.length, 0
  end

  test "clears shutdown_at records when a codespace is resumed" do
    codespace = create(:codespace)
    codespace.merge_environment_data!({ state: Codespaces::Vscs::State::SHUTDOWN })

    payload = {
      id: codespace.guid,
      friendlyName: codespace.name,
      state: Codespaces::Vscs::State::AVAILABLE,
      gitStatus: @git_status
    }

    Codespaces::ProcessWebhook.call(payload)
    codespace.reload
    assert_equal Codespaces::Vscs::State::AVAILABLE, codespace.environment_data.state
    assert_nil codespace.shutdown_at
  end

  test "leaves shutdown_at alone when we get a ShuttingDown webhook after a prior shutdown" do
    codespace = create(:codespace, :provisioning)

    shutdown_payload = {
      id: codespace.guid,
      friendlyName: codespace.name,
      state: Codespaces::Vscs::State::SHUTDOWN,
      gitStatus: @git_status
    }

    freeze_time do
      Codespaces::ProcessWebhook.call(shutdown_payload)
      codespace.reload
      assert_equal Codespaces::Vscs::State::SHUTDOWN, codespace.environment_data.state
      assert_equal Time.now, codespace.shutdown_at
    end

    shutting_down_payload = {
      id: codespace.guid,
      friendlyName: codespace.name,
      state: Codespaces::Vscs::State::SHUTTING_DOWN,
      gitStatus: @git_status
    }

    assert_no_changes -> { codespace.reload.shutdown_at } do
      Codespaces::ProcessWebhook.call(shutting_down_payload)
    end
  end

  test "does nothing when the codespace inititally has no environment data and the new state is not shutdown" do
    codespace = create(:codespace, environment_data: nil)

    payload = {
      id: codespace.guid,
      friendlyName: codespace.name,
      state: Codespaces::Vscs::State::AVAILABLE,
      gitStatus: @git_status
    }

    Codespaces::ProcessWebhook.call(payload)
    codespace.reload
    assert_equal Codespaces::Vscs::State::AVAILABLE, codespace.environment_data.state
    assert_nil codespace.shutdown_at
  end

  context "check for completed async operations" do
    test "normally" do
      codespace = create(:codespace, sku_name: :basicLinux32gb)

      payload = {
        id: codespace.guid,
        friendlyName: codespace.name,
        state: Codespaces::Vscs::State::SHUTDOWN,
        gitStatus: @git_status,
        skuName: "standardLinux32gb",
      }

      Codespaces::AsyncOperation.expects(:check_for_completed_operations).once

      Codespaces::ProcessWebhook.call(payload)
    end

    test "with the payload even if it's stale" do
      codespace = create(:codespace, sku_name: :basicLinux32gb)
      codespace.merge_environment_data!({ state: Codespaces::Vscs::State::SHUTDOWN, updated: Time.now.iso8601 })

      payload = {
        id: codespace.guid,
        friendlyName: codespace.name,
        state: Codespaces::Vscs::State::SHUTDOWN,
        gitStatus: @git_status,
        skuName: "standardLinux32gb",
        updated: 5.minutes.ago.iso8601
      }

      Codespaces::AsyncOperation.expects(:check_for_completed_operations).once.with(codespace, env: Codespaces::Environment.from_json(payload))

      assert_no_changes(-> { codespace.reload.environment_data }) do
        Codespaces::ProcessWebhook.call(payload)
      end
    end

    test "even with a deleted owner" do
      codespace = create(:codespace, sku_name: :basicLinux32gb)
      codespace.owner.delete
      payload = {
        id: codespace.guid,
        friendlyName: codespace.name,
        state: Codespaces::Vscs::State::SHUTDOWN,
        gitStatus: @git_status,
        skuName: "standardLinux32gb",
      }

      Codespaces::AsyncOperation.expects(:check_for_completed_operations).once

      Codespaces::ProcessWebhook.call(payload)
    end
  end

  context "git status events" do
    test "it emits a webhook heartbeat event anytime the webhook is called with a valid payload" do
      Codespaces::ProcessWebhook.call(@valid_payload)
      assert_hydro_published_partial({ type: :WEBHOOK_HEARTBEAT }, schema: "github.codespaces.v0.CodespaceInteraction")
    end

    test "it emits a webhook heartbeat event anytime the webhook is called even with a stale payload" do
      @codespace.merge_environment_data!({ state: Codespaces::Vscs::State::SHUTDOWN, updated: Time.now.iso8601 })
      Codespaces::ProcessWebhook.call(@stale_payload)
      assert_hydro_published_partial({ type: :WEBHOOK_HEARTBEAT }, schema: "github.codespaces.v0.CodespaceInteraction")
    end

    test "it emits a webhook heartbeat event with client usage data if that is provided in the payload" do
      received_client_usage = {
        "sessionId": "7ce49987-e53e-4e69-b4be-75cb1c7980d7",
        "usageData": {
          "vscode": {
              "activeMinutes": 12,
              "lastActivity": "2022-08-29T23:43:56Z"
          },
          "gh": {
              "activeMinutes": 3,
              "lastActivity": "2022-08-29T23:44:27Z"
          }
        }
      }

      # adjusted for event shape
      expected_client_usage = {
        "session_id": "7ce49987-e53e-4e69-b4be-75cb1c7980d7",
        "clients": {
          "vscode": {
            "active_minutes": 12,
            "last_activity": Google::Protobuf::Timestamp.new(seconds: Time.parse("2022-08-29T23:43:56Z").to_i)
          },
          "gh": {
              "active_minutes": 3,
              "last_activity": Google::Protobuf::Timestamp.new(seconds: Time.parse("2022-08-29T23:44:27Z").to_i)
          }
        }
      }

      Codespaces::ProcessWebhook.call(@valid_payload.merge(clientUsage: received_client_usage))
      assert_hydro_published_partial({ type: :WEBHOOK_HEARTBEAT, client_usage: expected_client_usage }, schema: "github.codespaces.v0.CodespaceInteraction")
    end

    test "it does not emit client usage data if the data is invalid" do
      # show that an invalid client usage map won't be sent
      invalid_client_usage = {
        "sessionId": "7ce49987-e53e-4e69-b4be-75cb1c7980d7",
        "usageData": {
          "vscode": {
            "activeMinutes": "should be a number",
            "lastActivity": "some time ago"
          },
          "gh": {
            "activeMinutes": 3,
            "lastActivity": "2022-08-29T23:44:27Z"
          }
        }
      }

      Codespaces::ProcessWebhook.call(@valid_payload.merge(clientUsage: invalid_client_usage))
      assert_hydro_published_partial({ type: :WEBHOOK_HEARTBEAT, client_usage: nil }, schema: "github.codespaces.v0.CodespaceInteraction")
    end


    test "it emits file changed events when we detect uncommitted changes" do
      Codespaces::ProcessWebhook.call(@valid_payload.merge(gitStatus: { "hasUncommittedChanges" => true }))
      assert_hydro_published_partial({ type: :FILE_CHANGED }, schema: "github.codespaces.v0.CodespaceInteraction")
      assert_hydro_message_difference("github.codespaces.v0.CodespaceInteraction") do
        # the difference is the extra event sent for the webhook heartbeat
        Codespaces::ProcessWebhook.call(@valid_payload.merge(gitStatus: { "hasUncommittedChanges" => true }))
      end
    end

    test "it emits file changed events when we detect unpushed changes" do
      Codespaces::ProcessWebhook.call(@valid_payload.merge(gitStatus: { "hasUnpushedChanges" => true }))
      assert_hydro_published_partial({ type: :FILE_CHANGED }, schema: "github.codespaces.v0.CodespaceInteraction")
      assert_hydro_message_difference("github.codespaces.v0.CodespaceInteraction") do
        Codespaces::ProcessWebhook.call(@valid_payload.merge(gitStatus: { "hasUnpushedChanges" => true }))
      end
    end

    test "it emits push received events when we previously had unpushed changes but no longer do if the new commit is revertable to the previous commit" do
      commit = create(:commit, repository: @codespace.repository, committer: @owner)
      @codespace.merge_environment_data!({ gitStatus: { "commit" => commit.sha, "branch" => @codespace.branch, "hasUnpushedChanges" => true } })
      new_commit = create(:commit, repository: @codespace.repository, committer: @owner)
      Codespaces::ProcessWebhook.call(@valid_payload.merge(gitStatus: { "commit" => new_commit.sha, "branch" => @codespace.branch, "hasUnpushedChanges" => false }))
      assert_hydro_published_partial({ type: :PUSHED_UPSTREAM }, schema: "github.codespaces.v0.CodespaceInteraction")
      assert_hydro_message_difference("github.codespaces.v0.CodespaceInteraction") do
        # Now lets pretend we had unpushed changes and we get a webhook telling us we're on a SHA that we don't
        # actually know about in the repo. Means they didn't push so no event should fire.
        @codespace.merge_environment_data!({ gitStatus: { "commit" => "4c8124ffcf4039d292442eeccabdeca5af5c5017", "branch" => @codespace.branch, "hasUnpushedChanges" => true } })
        Codespaces::ProcessWebhook.call(@valid_payload.merge(gitStatus: { "commit" => "a47fd41f3aa4610ea527dcc1669dfdb9c15c5425", "branch" => @codespace.branch, "hasUnpushedChanges" => false }))
      end
    end

    test "it ignores invalid noGitRepo webhooks for codespaces that should never be in that state" do
      enable_feature_flag(:codespaces_prevent_no_git_repo_bug, @codespace.owner)
      @codespace.merge_environment_data!({ gitStatus: @git_status })
      no_git_repo = @valid_payload.merge(gitStatus: {
        "ahead": 0,
        "behind": 0,
        "branch": nil,
        "commit": nil,
        "autoPush": false,
        "noGitRepo": true,
        "hasUnpushedChanges": false,
        "hasUncommittedChanges": false
      })
      assert_no_changes -> { @codespace.reload.environment_data.git_status } do
        Codespaces::ProcessWebhook.call(no_git_repo)
      end
    end

    test "it accepts noGitRepo webhooks for codespaces from templates" do
      enable_feature_flag(:codespaces_prevent_no_git_repo_bug, @codespace.owner)
      @codespace.merge_environment_data!({ gitStatus: @git_status })
      Codespace.any_instance.stubs(:from_codespace_template?).returns(true)
      no_git_repo = @valid_payload.merge(gitStatus: {
        "ahead": 0,
        "behind": 0,
        "branch": nil,
        "commit": nil,
        "autoPush": false,
        "noGitRepo": true,
        "hasUnpushedChanges": false,
        "hasUncommittedChanges": false
      })
      Codespaces::ProcessWebhook.call(no_git_repo)
      assert_nil @codespace.reload.environment_data.branch
      assert_equal true, @codespace.reload.environment_data.no_git_repo?
    end
  end

  context "copilot workspace codespaces" do
    test "does not deprovision running codespace" do
      disable_feature_flag(:codespaces_cw_no_delete_on_shutdown, @owner)
      Codespaces::ProcessWebhook.call(@copilot_workspace_payload)

      @copilot_workspace_codespace.reload
      refute @copilot_workspace_codespace.deprovisioning?
    end

    test "deprovisions when copilot workspace codespace is shutdown" do
      disable_feature_flag(:codespaces_cw_no_delete_on_shutdown, @owner)
      Codespaces::ProcessWebhook.call(@copilot_workspace_payload.merge(state: Codespaces::Vscs::State::SHUTDOWN))

      @copilot_workspace_codespace.reload
      assert @copilot_workspace_codespace.deprovisioning?
    end

    test "does not deprovision if user has codespaces_cw_no_delete_on_shutdown flag enabled" do
      enable_feature_flag(:codespaces_cw_no_delete_on_shutdown, @owner)

      Codespaces::ProcessWebhook.call(@copilot_workspace_payload.merge(state: Codespaces::Vscs::State::SHUTDOWN))

      @copilot_workspace_codespace.reload
      refute @copilot_workspace_codespace.deprovisioning?
    end
  end
end
