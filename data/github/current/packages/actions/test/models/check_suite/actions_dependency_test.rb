# typed: true
# frozen_string_literal: true

require "test_helper"

class CheckSuiteActionsDependencyTest < GitHub::TestCase
  setup do
    enable_feature_flag(:pull_request_sub_triggers)
    GitHub.stubs(:actions_enabled?).returns(true)
  end

  def create_codespaces_prebuild_check_suite_with_workflow_run(configuration:)
    workflow_path = Codespaces::Prebuilds.workflow_path(configuration.vscs_target)
    codespaces_app = create(:integration, default_permissions: { "checks" => :write })
    workflow = Actions::Workflow.find_by(repository: configuration.repository, name: "Codespaces Prebuilds", path: workflow_path)
    if workflow.nil?
      workflow = create(:workflow, repository: configuration.repository, name: "Codespaces Prebuilds", path: workflow_path)
    end

    commit = create(:commit, repository: configuration.repository, branch: configuration.branch, create_branch: false)
    check_suite = create(
        :check_suite_for_actions_app,
        repository: configuration.repository,
        github_app: codespaces_app,
        head_sha: commit.oid,
        workflow_file_path: workflow_path,
        creator: create(:bot)
    )

    workflow_run = Actions::WorkflowRun.create(check_suite: check_suite,
      workflow: workflow,
      repository: configuration.repository,
      actor: check_suite.creator,
      head_branch: configuration.branch,
      workflow_file_path: workflow_path,
      head_sha: commit.oid)

    check_suite.update!(workflow_run: workflow_run)
    check_suite.stubs(:actions_app?).returns(true)

    configuration.update!(latest_workflow_run_id: check_suite.workflow_run.id)

    check_suite
  end

  context "notifications" do
    test "doesn't send notifications if check suite repo doesn't have Dreamlifter enabled" do
      make_trusted_oauth_apps_owner
      GitHub.stubs(:actions_enabled?).returns(false)

      GitHub.newsies.expects(:trigger).never

      create(:check_suite_for_actions_app, :failure)
    end

    test "doesn't send notifications if the suite was not from GitHub Actions" do
      some_other_app = create(:integration)

      GitHub.newsies.expects(:trigger).never

      create(:check_suite, :failure, github_app: some_other_app)
    end

    test "doesn't send notifications if runs are incomplete" do
      make_trusted_oauth_apps_owner

      GitHub.newsies.expects(:trigger).never

      create(:check_suite_for_actions_app, status: :queued)
    end

    test "doesn't send notifications if runs completed but conclusion wasn't updated" do
      make_trusted_oauth_apps_owner

      GitHub.newsies.expects(:trigger).never

      create(:check_suite_for_actions_app, status: :completed)
    end

    test "doesn't send notifications if the head is the parent of the base" do
      make_trusted_oauth_apps_owner

      user = create(:user)
      source_repo = create(:repository)
      fork_repo = create(:fork_repository, forker: user, fork_repo: source_repo)

      GitHub.newsies.expects(:trigger).never
      CheckRun.any_instance.stubs(:notify_socket_subscribers)

      create(:check_suite_for_actions_app, :failure, head_repository: source_repo, repository: fork_repo)
    end

    test "sends notifications if Dreamlifter was enabled, runs completed, and conclusion set" do
      make_trusted_oauth_apps_owner
      check_suite = build(:check_suite_for_actions_app, :failure)

      saved_at = Time.now.change(usec: 0).utc

      GitHub.newsies.expects(:trigger).with(
        instance_of(CheckSuiteEventNotification),
        recipient_ids: [check_suite.creator_id],
        reason: :ci_activity,
        event_time: saved_at,
      )

      Timecop.freeze(saved_at) { check_suite.save }
    end

    test "send notifications if suite has been completed with a conclusion" do
      make_trusted_oauth_apps_owner
      check_suite = create(:check_suite_for_actions_app)

      updated_at = 3.minutes.from_now.change(usec: 0).utc

      GitHub.newsies.expects(:trigger).with(
        instance_of(CheckSuiteEventNotification),
        recipient_ids: [check_suite.creator_id],
        reason: :ci_activity,
        event_time: updated_at,
      )

      Timecop.freeze(updated_at) do
        check_suite.update(status: "completed", conclusion: "success")
      end
    end

    test "doesn't send notifications if there are no creator" do
      make_trusted_oauth_apps_owner

      GitHub.newsies.expects(:trigger).never

      create(:check_suite_for_actions_app, :failure, creator: nil)
    end

    test "doesn't send notifications if the creator is a Bot" do
      make_trusted_oauth_apps_owner

      GitHub.newsies.expects(:trigger).never

      create(:check_suite_for_actions_app, :failure, creator: create(:bot))
    end

    test "instruments event when a notification is sent" do
      make_trusted_oauth_apps_owner

      names = []
      payloads = []
      payload = GlobalInstrumenter.subscribe("check_suite.notification_triggered") do |event, _start, _finish, _id, payload|
        names << event
        payloads << payload
      end
      check_suite = create(:check_suite_for_actions_app, :success)

      expected_payload = {
        conclusion: "success",
        check_suite: check_suite,
      }

      assert_equal "check_suite.notification_triggered", names.pop
      assert_equal expected_payload, payloads.pop
    end
  end

  context "notifications for codespace prebuild dynamic workflows" do
    test "don't send notification if prebuild config doesn't exist" do
      make_trusted_oauth_apps_owner

      updated_at = 3.minutes.from_now.change(usec: 0).utc

      configuration = create(:codespace_prebuild_configuration)
      check_suite = create_codespaces_prebuild_check_suite_with_workflow_run(configuration: configuration)
      configuration.destroy!

      GitHub.newsies.expects(:trigger).never

      Timecop.freeze(updated_at) do
        check_suite.update(status: "completed", conclusion: "failure")
      end
    end

    test "don't send notification if there are no actors to notify" do
      make_trusted_oauth_apps_owner

      updated_at = 3.minutes.from_now.change(usec: 0).utc

      configuration = create(:codespace_prebuild_configuration)
      check_suite = create_codespaces_prebuild_check_suite_with_workflow_run(configuration: configuration)

      GitHub.newsies.expects(:trigger).never

      Timecop.freeze(updated_at) do
        check_suite.update(status: "completed", conclusion: "failure")
      end
    end

    test "don't send notification if completion state is succeeded" do
      make_trusted_oauth_apps_owner

      updated_at = 3.minutes.from_now.change(usec: 0).utc

      configuration = create(:codespace_prebuild_configuration)
      check_suite = create_codespaces_prebuild_check_suite_with_workflow_run(configuration: configuration)

      GitHub.newsies.expects(:trigger).never

      Timecop.freeze(updated_at) do
        check_suite.update(status: "completed", conclusion: "success")
      end
    end

    test "send notification to actors to notify specified on configuration" do
      make_trusted_oauth_apps_owner

      updated_at = 3.minutes.from_now.change(usec: 0).utc

      org = create(:organization)
      repo = create(:repository, owner: org, from_example: :simple)
      configuration = create(:codespace_prebuild_configuration, repository: repo, branch: repo.default_branch)

      # create users to notify
      user_1 = create(:user)
      user_2 = create(:user)
      user_3 = create(:user)
      user_logins = [user_1.login, user_2.login, user_3.login]

      # create team 1
      team_1 = create(:public_team, organization: org)
      user1_for_team1 = create(:user)
      user2_for_team1 = create(:user)
      team_1.add_member(user1_for_team1)
      team_1.add_member(user2_for_team1)

      # create team 2
      team_2 = create(:public_team, organization: org)
      user_for_team2 = create(:user)
      team_2.add_member(user_for_team2)
      team_2.add_member(user_1)
      team_2.add_member(user_2)

      team_slugs = [team_1.slug, team_2.slug]

      configuration.build_actors_to_notify(user_logins: user_logins, team_slugs: team_slugs)
      configuration.save!

      check_suite = create_codespaces_prebuild_check_suite_with_workflow_run(configuration: configuration)
      configuration_actors_to_notify = T.must(Codespaces::PrebuildConfiguration.find_by(latest_workflow_run_id: check_suite.workflow_run.id)&.actors_to_notify&.to_a)

      GitHub.logger.stubs(:info).returns(true)
      GitHub.logger.expects(:info).with("prebuild notify on failure info",
        {
          "catalog_service" => "github/codespaces",
          "workflow_run_id" => check_suite.workflow_run.id,
          "prebuild_configuration_id" => T.must(configuration_actors_to_notify.first).codespace_prebuild_configuration_id,
          "users_to_notify_count" => 3,
          "teams_to_notify_count" => 2
        })

      GitHub.newsies.expects(:trigger).with(
        instance_of(CheckSuiteEventNotification),
        recipient_ids: [user_1.id, user_2.id, user1_for_team1.id, user2_for_team1.id, user_for_team2.id, user_3.id],
        reason: :ci_activity,
        event_time: updated_at,
      )

      Timecop.freeze(updated_at) do
        check_suite.update(status: "completed", conclusion: "failure")
      end
    end
  end

  context "#healable_for_actions?" do
    test "false if check_suite is not from the actions app" do
      check_suite = create :check_suite
      refute check_suite.healable_for_actions?
    end

    test "false if check_suite does not have explicit_completion set" do
      make_trusted_oauth_apps_owner

      check_suite = create :check_suite_for_actions_app, explicit_completion: false

      refute check_suite.explicit_completion
      refute check_suite.healable_for_actions?
    end

    test "false if there is a conclusion" do
      make_trusted_oauth_apps_owner

      check_suite = create :check_suite_for_actions_app, :success, explicit_completion: true

      assert check_suite.explicit_completion
      refute_nil check_suite.conclusion
      refute check_suite.healable_for_actions?
    end

    test "false if not all the latest_check_runs are concluded" do
      make_trusted_oauth_apps_owner

      check_suite = create :check_suite_for_actions_app, explicit_completion: true
      check_run = create :check_run, check_suite: check_suite

      assert check_suite.explicit_completion
      assert_nil check_suite.conclusion
      refute check_suite.check_runs.where(repository_id: check_suite.repository_id).first.concluded?
      refute check_suite.healable_for_actions?
    end

    test "true when all check runs are done and suite is not" do
      make_trusted_oauth_apps_owner

      check_suite = create :check_suite_for_actions_app, explicit_completion: true
      check_run = create :check_run, :completed, conclusion: :success, check_suite: check_suite

      assert check_suite.explicit_completion
      assert_nil check_suite.conclusion
      assert check_suite.check_runs.where(repository_id: check_suite.repository_id).first.concluded?
      assert check_suite.healable_for_actions?
    end

    test "true if the check suite has an inconsistent status" do
      make_trusted_oauth_apps_owner

      check_suite = create :check_suite_for_actions_app, status: :in_progress, conclusion: :cancelled, explicit_completion: true
      check_run = create :check_run, :completed, conclusion: :cancelled, check_suite: check_suite

      assert check_suite.explicit_completion
      assert check_suite.inconsistent_status?
      assert check_suite.check_runs.where(repository_id: check_suite.repository_id).first.concluded?
      assert check_suite.healable_for_actions?
    end
  end

  context "#inconsistent_status?" do
    test "true if there is a conclusion and the status is not completed" do
      make_trusted_oauth_apps_owner
      check_suite = create :check_suite_for_actions_app, status: :in_progress, conclusion: :cancelled

      assert check_suite.inconsistent_status?
    end

    test "false if there is a conclusion and the status is completed for a cancelled run" do
      make_trusted_oauth_apps_owner
      check_suite = create :check_suite_for_actions_app, status: :completed, conclusion: :cancelled

      refute check_suite.inconsistent_status?
    end

    test "false if there is a conclusion and the status is completed for a succesfull run" do
      make_trusted_oauth_apps_owner
      check_suite = create :check_suite_for_actions_app, status: :completed, conclusion: :success

      refute check_suite.inconsistent_status?
    end

    test "false if there is a conclusion and the status is completed for a failed run" do
      make_trusted_oauth_apps_owner
      check_suite = create :check_suite_for_actions_app, status: :completed, conclusion: :failure

      refute check_suite.inconsistent_status?
    end

    test "false if there is no conclusion" do
      make_trusted_oauth_apps_owner
      check_suite = create :check_suite_for_actions_app, status: :pending

      refute check_suite.inconsistent_status?
    end
  end

  context "#mark_as_complete!" do
    test "does nothing if not healable_for_actions?" do
      make_trusted_oauth_apps_owner

      check_suite = create :check_suite_for_actions_app
      check_suite.expects(:healable_for_actions?).returns(false)
      check_suite.expects(:set_complete_explicitly!).never

      check_suite.mark_as_complete!
    end

    test "calls set_complete_explicitly! with the latest check runs" do
      make_trusted_oauth_apps_owner

      check_suite = create :check_suite_for_actions_app
      check_run = create :check_run, :completed, conclusion: :success, check_suite: check_suite

      check_suite.expects(:healable_for_actions?).returns(true)
      check_suite.expects(:set_complete_explicitly!).with("success")

      check_suite.mark_as_complete!
    end

    test "defaults to cancelled if there are no check runs" do
      make_trusted_oauth_apps_owner

      check_suite = create :check_suite_for_actions_app
      check_suite.expects(:healable_for_actions?).returns(true)
      check_suite.expects(:set_complete_explicitly!).with("cancelled")

      check_suite.mark_as_complete!
    end

    test "inconsistent statuses get correctly fixed" do
      make_trusted_oauth_apps_owner
      check_suite = create :check_suite_for_actions_app, status: :in_progress, conclusion: :cancelled, explicit_completion: true
      check_run = create :check_run, :completed, conclusion: :cancelled, check_suite: check_suite

      assert check_suite.inconsistent_status?
      check_suite.mark_as_complete!

      check_suite.reload
      assert_equal "completed", check_suite.status
      assert_equal "cancelled", check_suite.conclusion
    end
  end

  context "gate_approval_logs_for_execution" do
    test "returns all gate approvals for the check_suite" do
      make_trusted_oauth_apps_owner

      check_suite = create :check_suite_for_actions_app, :success_after_create

      gate_approval_log1 = create(:gate_approval_log, repository: check_suite.repository, check_suite: check_suite)
      gate_approval_log2 = create(:gate_approval_log, repository: check_suite.repository, check_suite: check_suite)
      gate_approval_log3 = create(:gate_approval_log, repository: check_suite.repository, check_suite: check_suite)

      gate_approval_logs = check_suite.gate_approval_logs_for_execution

      assert_same_elements [gate_approval_log3, gate_approval_log2, gate_approval_log1], gate_approval_logs

    end

    test "returns only the gate approvals within the execution time range" do
      make_trusted_oauth_apps_owner

      check_suite = create :check_suite_for_actions_app, :success_after_create

      gate_approval_log1 = create(:gate_approval_log, repository: check_suite.repository, check_suite: check_suite, created_at: check_suite.started_at + 1.second)
      gate_approval_log2 = create(:gate_approval_log, repository: check_suite.repository, check_suite: check_suite, created_at: check_suite.started_at + 3.seconds)
      gate_approval_log3 = create(:gate_approval_log, repository: check_suite.repository, check_suite: check_suite, created_at: check_suite.started_at + 6.seconds)

      execution = check_suite.workflow_run.workflow_run_executions.first
      execution.created_at = check_suite.started_at + 2.seconds
      execution.started_at = check_suite.started_at + 2.seconds
      execution.completed_at = check_suite.started_at + 4.seconds
      execution.save!

      gate_approval_logs = check_suite.gate_approval_logs_for_execution(execution: execution)
      assert_same_elements [gate_approval_log2], gate_approval_logs
    end
  end

  context "#missing_workflow_run?" do
    test "false if check_suite has a workflow_run associated with it" do
      make_trusted_oauth_apps_owner

      check_suite = create :check_suite_for_actions_app

      refute check_suite.missing_workflow_run?
    end

    test "true if check_suite has a missing workflow_run" do
      make_trusted_oauth_apps_owner

      check_suite = create :check_suite
      check_suite.stubs(:actions_app?).returns(true)
      check_suite.update!(workflow_run: nil)

      assert check_suite.missing_workflow_run?
    end
  end

  context "external_id and clones" do
    test "generates a unique external_id for a cloned run" do
      make_trusted_oauth_apps_owner
      check_suite = create(:check_suite_for_actions_app, external_id: "74766586-ac8e-4bf7-befa-efb994ef9004")
      external_id_for_clone = check_suite.new_unique_external_id_for_clone

      refute_equal external_id_for_clone, check_suite.external_id
      assert external_id_for_clone.start_with?("#{check_suite.external_id}#clone-")
      assert_equal "74766586-ac8e-4bf7-befa-efb994ef9004", external_id_for_clone[0..35]
    end

    test "returns the original actions external id for a cloned run" do
      make_trusted_oauth_apps_owner
      check_suite = create(:check_suite_for_actions_app, external_id: "74766586-ac8e-4bf7-befa-efb994ef9004")
      external_id_for_clone = check_suite.new_unique_external_id_for_clone

      CheckSuite.any_instance.stubs(:external_id).returns(external_id_for_clone)
      assert_equal external_id_for_clone, check_suite.external_id
      assert_equal "74766586-ac8e-4bf7-befa-efb994ef9004", check_suite.original_actions_external_id
    end
  end

  context "#force_cancellation" do
    test "1 day older check suites are eligible for force cancellation" do
      make_trusted_oauth_apps_owner

      check_suite = create :check_suite_for_actions_app
      CheckSuite.any_instance.stubs(:updated_at).returns(1.day.ago)
      assert check_suite.force_set_cancellation_eligible?
    end

    test "recent check suites are not eligible for force cancellation" do
      make_trusted_oauth_apps_owner

      check_suite = create :check_suite_for_actions_app
      CheckSuite.any_instance.stubs(:updated_at).returns(1.hour.ago)
      refute check_suite.force_set_cancellation_eligible?
    end

    test "force_set_cancellation_state correctly cancels non completed check suite and check runs" do
      make_trusted_oauth_apps_owner

      check_suite = create(:check_suite_for_actions_app, :in_progress)
      in_progress_run = create(:check_run, :in_progress, check_suite: check_suite)
      succesfull_run = create(:check_run, :success, check_suite: check_suite)

      check_suite.force_set_cancellation_state(actor: check_suite.repository.owner)

      check_suite.reload
      assert_equal "completed", check_suite.status
      assert_equal "cancelled", check_suite.conclusion

      in_progress_run.reload
      assert_equal "completed", in_progress_run.status
      assert_equal "cancelled", in_progress_run.conclusion

      succesfull_run.reload
      assert_equal "completed", succesfull_run.status
      assert_equal "success", succesfull_run.conclusion
    end
  end

  context "#is_required_workflow_run?" do
    test "returns false if the check suite is not of actions" do
      org = create(:organization)
      target_repo = create(:repository, owner: org, from_example: :pull_request_source)

      pull = create :pull_request, :with_mergeable_head, repository: target_repo

      GitHub.stubs(:actions_enabled?).returns(true)
      integration = create(:integration)

      check_suite = CheckSuite.create(repository: target_repo, head_sha: pull.head_sha, github_app_id: integration.id)
      create :check_run_for_actions_app, check_suite: check_suite, name: "simple-context", status: :completed, conclusion: :success, completed_at: 1.second.ago

      assert_equal false, check_suite.is_required_workflow_run?
    end

    test "returns false if the check suite is of actions but not required" do
      org = create(:organization)
      target_repo = create(:repository, owner: org, from_example: :pull_request_source)

      pull = create :pull_request, :with_mergeable_head, repository: target_repo

      GitHub.stubs(:actions_enabled?).returns(true)
      make_trusted_oauth_apps_owner
      launch_app = create(:launch_integration)
      GitHub.stubs(:launch_github_app).returns(launch_app)

      workflow_path = "test.yml"
      Actions::Workflow.create_or_update_workflow(workflow_path, "Test workflow", target_repo, nil)
      target_repo_workflow = Actions::Workflow.where(repository_id: target_repo.id, path: workflow_path).first
      check_suite = CheckSuite.create(repository: target_repo, head_sha: pull.head_sha, github_app_id: launch_app.id, workflow_file_path: workflow_path)
      create :check_run_for_actions_app, check_suite: check_suite, name: "simple-context", status: :completed, conclusion: :success, completed_at: 1.second.ago

      assert_equal false, check_suite.is_required_workflow_run?
    end

    if GitHub.enterprise?
      test "returns true if the check suite is of actions and is required but run not created" do
        org = create(:organization)
        target_repo = create(:repository, owner: org, from_example: :pull_request_source)
        source_repo = create(:repository, owner: org)

        pull = create :pull_request, :with_mergeable_head, repository: target_repo

        GitHub.stubs(:actions_enabled?).returns(true)
        make_trusted_oauth_apps_owner
        launch_app = create(:launch_integration)
        GitHub.stubs(:launch_github_app).returns(launch_app)

        req_workflow_path = "required/#{source_repo.id}/.github/required-workflows/required.yml"
        Actions::Workflow.create_or_update_workflow(req_workflow_path, "req-workflow-name", target_repo, nil, imposer_repository_id: source_repo.id)
        target_repo_workflow = Actions::Workflow.where(repository_id: target_repo.id, path: req_workflow_path, imposer_repository_id: source_repo.id).first
        check_suite = CheckSuite.create(repository: target_repo, head_sha: pull.head_sha, github_app_id: launch_app.id, workflow_file_path: req_workflow_path)

        assert_equal true, check_suite.is_required_workflow_run?
      end

      test "returns true if the check suite is of actions and is required and run is created" do
        org = create(:organization)
        target_repo = create(:repository, owner: org, from_example: :pull_request_source)
        source_repo = create(:repository, owner: org)

        pull = create :pull_request, :with_mergeable_head, repository: target_repo

        GitHub.stubs(:actions_enabled?).returns(true)
        make_trusted_oauth_apps_owner
        launch_app = create(:launch_integration)
        GitHub.stubs(:launch_github_app).returns(launch_app)

        req_workflow_path = "required/#{source_repo.id}/.github/required-workflows/required.yml"
        Actions::Workflow.create_or_update_workflow(req_workflow_path, "req-workflow-name", target_repo, nil, imposer_repository_id: source_repo.id)
        target_repo_workflow = Actions::Workflow.where(repository_id: target_repo.id, path: req_workflow_path, imposer_repository_id: source_repo.id).first
        check_suite = CheckSuite.create(repository: target_repo, head_sha: pull.head_sha, github_app_id: launch_app.id, workflow_file_path: req_workflow_path)
        create :check_run_for_actions_app, check_suite: check_suite, name: "req-workflow-context", status: :completed, conclusion: :success, completed_at: 1.second.ago

        assert_equal true, check_suite.is_required_workflow_run?
      end
    end
  end

  context "#verify_and_return_workflow_path_metadata" do
    test "returns original path and nil imposer repo id for non-required workflows" do
      repo = create(:repository)

      workflow_file_path = ".github/workflows/test.yml"

      check_suite = create(
        :check_suite_for_actions_app,
        repository: repo,
        workflow_file_path: workflow_file_path
      )

      processed_path, processed_imposer_repo_id = check_suite.verify_and_return_workflow_path_metadata(workflow_file_path)

      assert_equal workflow_file_path, processed_path
      assert_nil processed_imposer_repo_id
    end

    test "returns processed path and imposer repo id for required workflows" do
      repo = create(:repository)

      workflow_file_path = ".github/workflows/test.yml"
      imposer_repo_id = 1
      required_workflow_file_path = "required/#{imposer_repo_id}/#{workflow_file_path}"

      check_suite = create(
        :check_suite_for_actions_app,
        repository: repo,
        workflow_file_path: required_workflow_file_path
      )

      processed_path, processed_imposer_repo_id = check_suite.verify_and_return_workflow_path_metadata(required_workflow_file_path)

      assert_equal workflow_file_path, processed_path
      assert_equal imposer_repo_id, processed_imposer_repo_id
    end
  end

  context "#imposer_repo_id" do
    test "returns nil for non-required workflows" do
      repo = create(:repository)

      workflow_file_path = ".github/workflows/test.yml"

      check_suite = create(
        :check_suite_for_actions_app,
        repository: repo,
        workflow_file_path: workflow_file_path
      )

      assert_nil check_suite.imposer_repo_id
    end

    test "returns imposer repo id for required workflows" do
      repo = create(:repository)

      workflow_file_path = ".github/workflows/test.yml"
      imposer_repo_id = 1
      required_workflow_file_path = "required/#{imposer_repo_id}/#{workflow_file_path}"

      check_suite = create(
        :check_suite_for_actions_app,
        repository: repo,
        workflow_file_path: required_workflow_file_path
      )

      assert_equal imposer_repo_id, check_suite.imposer_repo_id
    end
  end

  context "#processed_workflow_file_path" do
    test "returns original path for non-required workflows" do
      repo = create(:repository)

      workflow_file_path = ".github/workflows/test.yml"

      check_suite = create(
        :check_suite_for_actions_app,
        repository: repo,
        workflow_file_path: workflow_file_path
      )

      assert_equal workflow_file_path, check_suite.processed_workflow_file_path
    end

    test "returns processed path for required workflows" do
      repo = create(:repository)

      workflow_file_path = ".github/workflows/test.yml"
      imposer_repo_id = 1
      required_workflow_file_path = "required/#{imposer_repo_id}/#{workflow_file_path}"

      check_suite = create(
        :check_suite_for_actions_app,
        repository: repo,
        workflow_file_path: required_workflow_file_path
      )

      assert_equal workflow_file_path, check_suite.processed_workflow_file_path
    end
  end

  context "steps from results" do
    test "returns check steps for a list of jobs" do
      check_suite = create(:check_suite_for_actions_app, :success)
      check_run_1 = create(:check_run_for_actions_app, :with_results_steps, check_suite: check_suite)
      check_run_2 = create(:check_run_for_actions_app, :with_results_steps, check_suite: check_suite)

      steps = create_list(:check_step, 10, :completed, :results_completed_log_url)
      ActionsResults::Twirp::StepsClient
      .any_instance
      .expects(:get_multiple_workflow_steps)
      .returns(TwirpResponse.new(
        status: 200,
        call_succeeded: true,
        value: MonolithTwirp::ActionsResults::Core::V1::GetMultipleWorkflowStepsResponse.new(
            job_steps: [
              MonolithTwirp::ActionsResults::Core::V1::JobSteps.new(
                workflow_run_backend_id: check_run_1.workflow_job_run.original_workflow_run_execution.external_id,
                workflow_job_run_backend_id: check_run_1.external_id,
                steps: steps.map(&:to_proto_object)
              ),
              MonolithTwirp::ActionsResults::Core::V1::JobSteps.new(
                workflow_run_backend_id: check_run_2.workflow_job_run.original_workflow_run_execution.external_id,
                workflow_job_run_backend_id: check_run_2.external_id,
                steps: steps.map(&:to_proto_object)
              ),
            ]
        )
      ))

      resp = check_suite.steps_from_results([check_run_1, check_run_2])
      assert_equal 2, resp.length
      assert_equal 10, resp[check_run_1.id].length
      assert_equal 10, resp[check_run_2.id].length
    end

    test "returns check steps for a list of jobs with a non-actions check" do
      check_suite = create(:check_suite_for_actions_app, :success)
      check_run_1 = create(:check_run_for_actions_app, :with_results_steps, check_suite: check_suite)
      check_run_2 = create(:check_run_for_actions_app, :with_results_steps, check_suite: check_suite)
      check_run_3 = create(:check_run, check_suite: check_suite, name: "non-actions-check")

      steps = create_list(:check_step, 10, :completed, :results_completed_log_url)
      ActionsResults::Twirp::StepsClient
      .any_instance
      .expects(:get_multiple_workflow_steps)
      .returns(TwirpResponse.new(
        status: 200,
        call_succeeded: true,
        value: MonolithTwirp::ActionsResults::Core::V1::GetMultipleWorkflowStepsResponse.new(
            job_steps: [
              MonolithTwirp::ActionsResults::Core::V1::JobSteps.new(
                workflow_run_backend_id: check_run_1.workflow_job_run.original_workflow_run_execution.external_id,
                workflow_job_run_backend_id: check_run_1.external_id,
                steps: steps.map(&:to_proto_object)
              ),
              MonolithTwirp::ActionsResults::Core::V1::JobSteps.new(
                workflow_run_backend_id: check_run_2.workflow_job_run.original_workflow_run_execution.external_id,
                workflow_job_run_backend_id: check_run_2.external_id,
                steps: steps.map(&:to_proto_object)
              ),
            ]
        )
      ))

      resp = check_suite.steps_from_results([check_run_1, check_run_2, check_run_3])
      assert_equal 2, resp.length
      assert_equal 10, resp[check_run_1.id].length
      assert_equal 10, resp[check_run_2.id].length
    end

    test "returns check steps for a list of jobs including partial reruns" do
      job_1_key = "job-1"
      job_2_key = "job-2"
      job_1_external_id = SimpleUUID::UUID.new.to_guid
      job_2_external_id = SimpleUUID::UUID.new.to_guid
      check_suite = create(:check_suite_for_actions_app, :success)
      check_run_1 = create(:check_run_for_actions_app, :with_results_steps, check_suite: check_suite, job_key: job_1_key, external_id: job_1_external_id)
      check_run_2 = create(:check_run_for_actions_app, :with_results_steps, check_suite: check_suite, job_key: job_2_key, external_id: job_2_external_id)
      workflow_run = check_suite.workflow_run
      workflow_run.create_new_workflow_execution(external_id: SimpleUUID::UUID.new.to_guid, attempt: 2)
      check_run_1_rerun = create(:check_run_for_actions_app, :with_results_steps, check_suite: check_suite, job_key: job_1_key, external_id: job_1_external_id, is_cloned_from_previous_run: true)
      check_run_2_rerun = create(:check_run_for_actions_app, :with_results_steps, check_suite: check_suite, job_key: job_2_key, external_id: job_2_external_id, is_cloned_from_previous_run: false)
      workflow_run.reload

      steps = create_list(:check_step, 10, :completed, :results_completed_log_url)
      steps_rerun = create_list(:check_step, 11, :completed, :results_completed_log_url)
      ActionsResults::Twirp::StepsClient
      .any_instance
      .expects(:get_multiple_workflow_steps)
      .returns(TwirpResponse.new(
        status: 200,
        call_succeeded: true,
        value: MonolithTwirp::ActionsResults::Core::V1::GetMultipleWorkflowStepsResponse.new(
            job_steps: [ # check_run_1_rerun is cloned from check_run_1, so it won't be in this list
              MonolithTwirp::ActionsResults::Core::V1::JobSteps.new(
                workflow_run_backend_id: check_run_1.workflow_job_run.original_workflow_run_execution.external_id,
                workflow_job_run_backend_id: check_run_1.external_id,
                steps: steps.map(&:to_proto_object)
              ),
              MonolithTwirp::ActionsResults::Core::V1::JobSteps.new(
                workflow_run_backend_id: check_run_2.workflow_job_run.original_workflow_run_execution.external_id,
                workflow_job_run_backend_id: check_run_2.external_id,
                steps: steps.map(&:to_proto_object)
              ),
              MonolithTwirp::ActionsResults::Core::V1::JobSteps.new(
                workflow_run_backend_id: check_run_2_rerun.workflow_job_run.original_workflow_run_execution.external_id,
                workflow_job_run_backend_id: check_run_2_rerun.external_id,
                steps: steps_rerun.map(&:to_proto_object)
              ),
            ]
        )
      ))

      resp = check_suite.steps_from_results([check_run_1, check_run_2, check_run_1_rerun, check_run_2_rerun])
      assert_equal 4, resp.length
      assert_equal 10, resp[check_run_1.id].length
      assert_equal 10, resp[check_run_2.id].length
      assert_equal 10, resp[check_run_1_rerun.id].length
      assert_equal 11, resp[check_run_2_rerun.id].length
    end

    test "returns check steps for latest check runs including partial reruns" do
      job_1_key = "job-1"
      job_2_key = "job-2"
      job_1_external_id = SimpleUUID::UUID.new.to_guid
      job_2_external_id = SimpleUUID::UUID.new.to_guid
      check_suite = create(:check_suite_for_actions_app, :success)
      check_run_1 = create(:check_run_for_actions_app, check_suite: check_suite, job_key: job_1_key, external_id: job_1_external_id)
      check_run_2 = create(:check_run_for_actions_app, check_suite: check_suite, job_key: job_2_key, external_id: job_2_external_id)
      workflow_run = check_suite.workflow_run
      workflow_run.create_new_workflow_execution(external_id: SimpleUUID::UUID.new.to_guid, attempt: 2)
      check_run_1_rerun = create(:check_run_for_actions_app, check_suite: check_suite, job_key: job_1_key, external_id: job_1_external_id, is_cloned_from_previous_run: true)
      check_run_2_rerun = create(:check_run_for_actions_app, check_suite: check_suite, job_key: job_2_key, external_id: job_2_external_id, is_cloned_from_previous_run: false)
      workflow_run.reload

      steps = create_list(:check_step, 10, :completed, :results_completed_log_url)
      steps_rerun = create_list(:check_step, 11, :completed, :results_completed_log_url)
      ActionsResults::Twirp::StepsClient
      .any_instance
      .expects(:get_multiple_workflow_steps)
      .returns(TwirpResponse.new(
        status: 200,
        call_succeeded: true,
        value: MonolithTwirp::ActionsResults::Core::V1::GetMultipleWorkflowStepsResponse.new(
            job_steps: [ # check_run_1_rerun is cloned from check_run_1, so it won't be in this list
              MonolithTwirp::ActionsResults::Core::V1::JobSteps.new(
                workflow_run_backend_id: check_run_1.workflow_job_run.original_workflow_run_execution.external_id,
                workflow_job_run_backend_id: check_run_1.external_id,
                steps: steps.map(&:to_proto_object)
              ),
              MonolithTwirp::ActionsResults::Core::V1::JobSteps.new(
                workflow_run_backend_id: check_run_2_rerun.workflow_job_run.original_workflow_run_execution.external_id,
                workflow_job_run_backend_id: check_run_2_rerun.external_id,
                steps: steps_rerun.map(&:to_proto_object)
              ),
            ]
        )
      ))

      resp = check_suite.steps_from_results(workflow_run.latest_check_runs)
      assert_equal 2, resp.length
      assert_equal 10, resp[check_run_1_rerun.id].length
      assert_equal 11, resp[check_run_2_rerun.id].length
    end

    test "returns an empty hash when results call fails" do
      check_suite = create(:check_suite_for_actions_app, :success)
      check_run_1 = create(:check_run_for_actions_app, :with_results_steps, check_suite: check_suite)
      check_run_2 = create(:check_run_for_actions_app, :with_results_steps, check_suite: check_suite)

      ActionsResults::Twirp::StepsClient
      .any_instance
      .expects(:get_multiple_workflow_steps)
      .returns(TwirpResponse.new(
        status: 500,
        call_succeeded: false
      ))

      resp = check_suite.steps_from_results([check_run_1, check_run_2])
      assert_equal 0, resp.length
    end
  end
end
