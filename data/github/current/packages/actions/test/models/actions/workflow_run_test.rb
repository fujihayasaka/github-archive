# typed: false
# frozen_string_literal: true
require "test_helper"
require "test_helpers/launch/artifacts_exchange_helper"

class Actions::WorkflowRunTest < GitHub::TestCase
  include AuditLog::IntegrationTestHelpers
  include ::Billing::ApiTestHelpers
  include GitHub::DatabaseQueryWarningsTestHelpers
  include GitHub::LoggerHelper
  include Launch::ArtifactExchangeHelper
  include HydroTestHelpers
  include BackgroundDeletesTestHelpers

  fixtures do
    GitHub.stubs(:actions_enabled?).returns(true)
    make_trusted_oauth_apps_owner
    @launch_app = create(:launch_integration)
    GitHub.stubs(:launch_github_app).returns(@launch_app)

    @repository = create :repository
    @owner = @repository.owner
    @business_org = create :enterprise_linked_organization, admin: @owner
    @audited_repo = create :repository, owner: @business_org
    @pull_request_repo = create :repository
    @pull_request_user = @pull_request_repo.owner
    @complex_check_suite = create_complex_actions_check_suite
    @lab_app = create(:launch_lab_integration)
  end

  setup do
    GitHub.stubs(:actions_enabled?).returns(true)
  end

  def create_workflow_run(trigger = nil, head_branch: "master", creator: nil)
    check_suite_name = "Node CI"

    creator ||= create(:user)
    check_suite = create(
      :check_suite_for_actions_app,
      :success_after_create,
      repository: @repository,
      creator: creator,
      name: check_suite_name,
      trigger: trigger,
      event: "pull_request",
      action: "open",
      head_branch: head_branch,
    )
    check_suite.workflow_run
  end

  def create_complex_actions_check_suite
    # graph which fans in and out. Contains matrix and non-matrix groups
    graph_json = <<~JSON
        {"stages":[
          {\"groups\":[
            {\"id\":\"|-build-frontend-|test-frontend-a&test-frontend-b\",\"name\":\"build-frontend\",\"type\":1,\"jobs\":[{\"id\":\"build-frontend\"}],\"outputs\":[\"build-frontend|env:staging|integration-test\",\"build-frontend|integration-test\"]},
            {\"id\":\"|test-backend\",\"type\":0,\"jobs\":[{\"id\":\"build-backend\"}],\"outputs\":[\"build-backend|integration-test\"]}
          ]},
          {\"groups\":[
            {\"id\":\"build-frontend|env:staging|integration-test\",\"type\":0,\"jobs\":[{\"id\":\"test-frontend-A\"}],\"inputs\":[\"|-build-frontend-|test-frontend-a&test-frontend-b\"],\"outputs\":[\"test-backend&test-frontend-a&test-frontend-b|stage\"]},
            {\"id\":\"build-frontend|integration-test\",\"type\":0,\"jobs\":[{\"id\":\"test-frontend-B\"}],\"inputs\":[\"|-build-frontend-|test-frontend-a&test-frontend-b\"],\"outputs\":[\"test-backend&test-frontend-a&test-frontend-b|stage\"]},
            {\"id\":\"build-backend|integration-test\",\"type\":0,\"jobs\":[{\"id\":\"test-backend\"}],\"inputs\":[\"|test-backend\"],\"outputs\":[\"test-backend&test-frontend-a&test-frontend-b|stage\"]}
          ]},
          {\"groups\":[
            {\"id\":\"test-backend&test-frontend-a&test-frontend-b|stage\",\"type\":0,\"jobs\":[{\"id\":\"integration-test\"}],\"inputs\":[\"build-backend|integration-test\",\"build-frontend|env:staging|integration-test\",\"build-frontend|integration-test\"],\"outputs\":[\"integration-test|-stage-|deploy\"]}
          ]},
          {\"groups\":[
            {\"id\":\"integration-test|-stage-|deploy\",\"name\":\"stage\",\"type\":1,\"jobs\":[{\"id\":\"stage\"}],\"inputs\":[\"test-backend&test-frontend-a&test-frontend-b|stage\"],\"outputs\":[\"stage|\"]}]},{\"groups\":[{\"id\":\"stage|\",\"type\":0,\"jobs\":[{\"id\":\"deploy\"}],\"inputs\":[\"integration-test|-stage-|deploy\"]}
          ]}
        ]}
      JSON

    check_suite_name = "Complex"
    check_suite = create(:check_suite_for_actions_app, :failure, repository: @repository, name: check_suite_name)
    check_suite.workflow_run.update!(execution_graph: graph_json)

    # build-frontend matrix
    check = create :check_run_for_actions_app, check_suite: check_suite, display_name: "build-frontend (1)"
    check.workflow_job_run.update!(parent_job_id: "build-frontend")
    check = create :check_run_for_actions_app, check_suite: check_suite, display_name: "build-frontend (2)"
    check.workflow_job_run.update!(parent_job_id: "build-frontend")

    check = create :check_run_for_actions_app, check_suite: check_suite, display_name: "build-backend"
    check.workflow_job_run.update!(parent_job_id: "build-backend")

    # test-front-end parallel jobs
    check = create :check_run_for_actions_app, check_suite: check_suite, display_name: "test-frontend-A"
    check.workflow_job_run.update!(parent_job_id: "test-frontend-A")
    check = create :check_run_for_actions_app, check_suite: check_suite, display_name: "test-frontend-B"
    check.workflow_job_run.update!(parent_job_id: "test-frontend-B")

    check = create :check_run_for_actions_app, check_suite: check_suite, display_name: "test-backend"
    check.workflow_job_run.update!(parent_job_id: "test-backend")

    check = create :check_run_for_actions_app, check_suite: check_suite, display_name: "integration-test"
    check.workflow_job_run.update!(parent_job_id: "integration-test")

    # stage matrix
    check = create :check_run_for_actions_app, check_suite: check_suite, display_name: "stage (1)"
    check.workflow_job_run.update!(parent_job_id: "stage")
    check = create :check_run_for_actions_app, check_suite: check_suite, display_name: "stage (2)"
    check.workflow_job_run.update!(parent_job_id: "stage")

    check = create :check_run_for_actions_app, check_suite: check_suite, display_name: "deploy"
    check.workflow_job_run.update!(parent_job_id: "deploy")

    check_suite
  end

  def assert_title(title, run)
    assert_equal title, run.title
    assert_equal title, run.async_title.sync
  end

  context "default_scope" do
    test "does not include execution_graph" do
      workflow_run = Actions::WorkflowRun.find(create_workflow_run.id)

      assert_raises ActiveModel::MissingAttributeError do
        workflow_run.execution_graph
      end
    end
  end

  context "#with_execution_graph" do
    test "includes the execution_graph" do
      workflow_run = Actions::WorkflowRun.with_execution_graph.find(create_workflow_run.id)
      assert_nothing_raised { workflow_run.execution_graph }
    end
  end

  context "#graph" do
    test "returns nil if column not loaded" do
      wr = create_workflow_run
      wr.update!(execution_graph: "{}")

      workflow_run = Actions::WorkflowRun.find(wr.id)

      assert_nil workflow_run.graph
    end

    test "returns nil if column is empty" do
      wr = create_workflow_run

      workflow_run = Actions::WorkflowRun.with_execution_graph.find(wr.id)

      assert_nil workflow_run.graph
    end

    test "returns graph if column is loaded and has a value" do
      wr = create_workflow_run
      wr.update!(execution_graph: "{\"stages\":[{\"groups\":[{\"id\":\"|\",\"type\":0,\"jobs\":[{\"id\":\"build\"}],\"inputs\":null,\"outputs\":null}]}]}")

      workflow_run = Actions::WorkflowRun.with_execution_graph.find(wr.id)

      refute_nil workflow_run.graph
    end

    test "returns nil if graph is invalid" do
      wr = create_workflow_run
      wr.update!(execution_graph: "{}")

      workflow_run = Actions::WorkflowRun.with_execution_graph.find(wr.id)

      assert_nil workflow_run.graph
    end

    test "returns workflow_run_execution's graph for reruns if available" do
      wr = create_workflow_run
      wr.update!(execution_graph: "{}")

      Timecop.travel(10.minutes) do
        wr.check_suite.reset
        graph = "{\"stages\":[{\"groups\":[{\"id\":\"|\",\"type\":0,\"jobs\":[{\"id\":\"build\"}],\"inputs\":null,\"outputs\":null}]}]}"
        wr.create_new_workflow_execution(external_id: SimpleUUID::UUID.new.to_guid, attempt: 2, execution_graph: graph)
      end

      execution = Actions::WorkflowRunExecution.with_execution_graph.find(wr.latest_workflow_run_execution.id)

      refute_nil wr.graph(execution: execution)
    end

    test "returns workflow_run's graph for reruns if execution's graph is empty" do
      wr = create_workflow_run
      wr.update!(execution_graph: "{\"stages\":[{\"groups\":[{\"id\":\"|\",\"type\":0,\"jobs\":[{\"id\":\"build\"}],\"inputs\":null,\"outputs\":null}]}]}")

      Timecop.travel(10.minutes) do
        wr.check_suite.reset
        wr.create_new_workflow_execution(external_id: SimpleUUID::UUID.new.to_guid, attempt: 2, execution_graph: "")
      end

      # Load both the run and execution with their graphs
      workflow_run = Actions::WorkflowRun.with_execution_graph.find(wr.id)
      execution = Actions::WorkflowRunExecution.with_execution_graph.find(wr.latest_workflow_run_execution.id)

      refute_nil workflow_run.graph(execution: execution)
    end
  end

  context "#has_billing_data?" do
    if GitHub.enterprise?
      test "returns false" do
        workflow_run = create_workflow_run
        refute workflow_run.has_billing_data?
      end
    else
      test "returns false when none available" do
        mock_get_usage_line_items_response_with(usage_line_items: [])
        workflow_run = create_workflow_run
        refute workflow_run.has_billing_data?
      end

      test "returns false when a BillingClientError occurs" do
        mock_get_usage_line_items_response_error
        workflow_run = create_workflow_run
        refute workflow_run.has_billing_data?
      end

      test "returns true when available" do
        workflow_run = create_workflow_run
        check_run = create(:check_run, :success, check_suite: workflow_run.check_suite)

        mock_get_usage_line_items_response_with(usage_line_items: [
          create_mock_usage_line_item(
            repository_id: @repository.id,
            quantity: 5,
            product_sku_name: "linux",
            custom_fields: {
              "actions.check_run.id": check_run.id.to_s,
            },
          ),
        ])
        assert workflow_run.has_billing_data?
      end
    end
  end

  context "#billing_minutes_duration" do
    test "returns sum of billable minutes" do
      workflow_run = create_workflow_run
      first_run = create(:check_run, :success, check_suite: workflow_run.check_suite)
      second_run = create(:check_run, :success, check_suite: workflow_run.check_suite)
      third_run = create(:check_run, :success, check_suite: workflow_run.check_suite)

      usage_line_items = []
      [first_run, second_run, third_run].each do |check_run|
        usage_line_items << create_mock_usage_line_item(
          product_sku_name: "linux",
          repository_id: @repository.id,
          quantity: 2,
          custom_fields: {
            "actions.check_run.id": check_run.id.to_s,
          },
        )
      end
      mock_get_usage_line_items_response_with(usage_line_items: usage_line_items)

      assert_equal 360, workflow_run.billing_duration_in_seconds
    end
  end

  context "#notify_socket_subscribers" do
    test "sends a workflow_runs notification only when creating a new record" do
      workflow_runs_notifications = 0
      GitHub::WebSocket.expects(:notify_repository_channel).with do |_repository, channel_id, data|
        if /workflow_runs:/ =~ channel_id
          assert_match /created/, data[:reason]
          workflow_runs_notifications += 1
        end
        true
      end.at_least_once

      workflow_run = create_workflow_run
      first_run = create(:check_run, :success, check_suite: workflow_run.check_suite)

      assert_equal 1, workflow_runs_notifications
    end
  end

  context "#notify_pull_request_socket_subscribers" do
    test "notify on create for action_required runs" do
      example_repo :rebase_pull_request, @pull_request_repo

      pull = create(:pull_request,
        repository: @pull_request_repo,
        base_repository: @pull_request_repo,
        base_user: @pull_request_repo.owner,
        base_ref: @pull_request_repo.default_branch,
        head_repository: @pull_request_repo,
        head_user: @pull_request_repo.owner,
        head_ref: "contrib",
        user: @pull_request_user,
      )

      after = @pull_request_repo.refs["contrib"].commit

      # Ignore other channel notifications
      GitHub::WebSocket.expects(:notify_repository_channel).with(any_parameters).at_least_once

      GitHub::WebSocket.expects(:notify_repository_channel).with(@pull_request_repo, GitHub::WebSocket::Channels.pull_request_workflow_run_state(pull), anything).once
      check_suite = create(:check_suite_for_actions_app, repository: @pull_request_repo, head_sha: after, head_branch: "contrib", status: :completed, conclusion: :action_required)
    end

    test "do not notify on create for other check suite conclusions" do
      example_repo :rebase_pull_request, @pull_request_repo

      pull = create(:pull_request,
        repository: @pull_request_repo,
        base_repository: @pull_request_repo,
        base_user: @pull_request_repo.owner,
        base_ref: @pull_request_repo.default_branch,
        head_repository: @pull_request_repo,
        head_user: @pull_request_repo.owner,
        head_ref: "contrib",
        user: @pull_request_user,
      )

      after = @pull_request_repo.refs["contrib"].commit

      # Ignore other channel notifications
      GitHub::WebSocket.expects(:notify_repository_channel).with(any_parameters).at_least_once

      GitHub::WebSocket.expects(:notify_repository_channel).with(@pull_request_repo, GitHub::WebSocket::Channels.pull_request_workflow_run_state(pull), anything).never
      check_suite = create(:check_suite_for_actions_app, repository: @pull_request_repo, head_sha: after, head_branch: "contrib", status: :queued)
    end

    test "notify on destroy for action_required runs" do
      example_repo :rebase_pull_request, @pull_request_repo

      pull = create(:pull_request,
        repository: @pull_request_repo,
        base_repository: @pull_request_repo,
        base_user: @pull_request_repo.owner,
        base_ref: @pull_request_repo.default_branch,
        head_repository: @pull_request_repo,
        head_user: @pull_request_repo.owner,
        head_ref: "contrib",
        user: @pull_request_user,
      )

      after = @pull_request_repo.refs["contrib"].commit
      check_suite = create(:check_suite_for_actions_app, repository: @pull_request_repo, head_sha: after, head_branch: "contrib", status: :completed, conclusion: :action_required)
      workflow_run = check_suite.workflow_run

      GitHub::WebSocket.expects(:notify_repository_channel).with(@pull_request_repo, GitHub::WebSocket::Channels.pull_request_workflow_run_state(pull), anything).once
      workflow_run.hard_delete(actor: @pull_request_user)
    end

    test "do not notify on destroy for other check suite conclusions" do
      example_repo :rebase_pull_request, @pull_request_repo

      pull = create(:pull_request,
        repository: @pull_request_repo,
        base_repository: @pull_request_repo,
        base_user: @pull_request_repo.owner,
        base_ref: @pull_request_repo.default_branch,
        head_repository: @pull_request_repo,
        head_user: @pull_request_repo.owner,
        head_ref: "contrib",
        user: @pull_request_user,
      )

      after = @pull_request_repo.refs["contrib"].commit
      check_suite = create(:check_suite_for_actions_app, repository: @pull_request_repo, head_sha: after, head_branch: "contrib", status: :completed, conclusion: :success)
      workflow_run = check_suite.workflow_run

      GitHub::WebSocket.expects(:notify_repository_channel).never
      workflow_run.hard_delete(actor: @pull_request_user)
    end

    test "notify on rerun for action_required runs" do
      example_repo :rebase_pull_request, @pull_request_repo

      pull = create(:pull_request,
        repository: @pull_request_repo,
        base_repository: @pull_request_repo,
        base_user: @pull_request_repo.owner,
        base_ref: @pull_request_repo.default_branch,
        head_repository: @pull_request_repo,
        head_user: @pull_request_repo.owner,
        head_ref: "contrib",
        user: @pull_request_user,
      )

      after = @pull_request_repo.refs["contrib"].commit
      check_suite = create(:check_suite_for_actions_app, repository: @pull_request_repo, head_sha: after, head_branch: "contrib", conclusion: :action_required)

      GitHub::WebSocket.expects(:notify_repository_channel).with(@pull_request_repo, GitHub::WebSocket::Channels.pull_request_workflow_run_state(pull), anything).once
      check_suite.rerequest(actor: @pull_request_user)
    end

    test "do not notify on reset for other check suite conclusions" do
      example_repo :rebase_pull_request, @pull_request_repo

      pull = create(:pull_request,
        repository: @pull_request_repo,
        base_repository: @pull_request_repo,
        base_user: @pull_request_repo.owner,
        base_ref: @pull_request_repo.default_branch,
        head_repository: @pull_request_repo,
        head_user: @pull_request_repo.owner,
        head_ref: "contrib",
        user: @pull_request_user,
      )

      after = @pull_request_repo.refs["contrib"].commit
      check_suite = create(:check_suite_for_actions_app, repository: @pull_request_repo, head_sha: after, head_branch: "contrib", conclusion: :success)

      GitHub::WebSocket.expects(:notify_repository_channel).never
      check_suite.rerequest(actor: @pull_request_user)
    end

    test "force cancel on destroy for not completed runs" do
      example_repo :rebase_pull_request, @pull_request_repo

      pull = create(:pull_request,
        repository: @pull_request_repo,
        base_repository: @pull_request_repo,
        base_user: @pull_request_repo.owner,
        base_ref: @pull_request_repo.default_branch,
        head_repository: @pull_request_repo,
        head_user: @pull_request_repo.owner,
        head_ref: "contrib",
        user: @pull_request_user,
      )

      after = @pull_request_repo.refs["contrib"].commit
      check_suite = create(:check_suite_for_actions_app, repository: @pull_request_repo, head_sha: after, head_branch: "contrib", status: :waiting, created_at: 40.days.ago)
      workflow_run = check_suite.workflow_run

      cancel_args = {
        check_suite_id: GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: check_suite.global_relay_id),
        canceled_by_id: @pull_request_user.id,
        canceled_by_name: @pull_request_user.display_login,
        canceled_by_global_id: GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: @pull_request_user.global_relay_id),
        force: true
      }

      Launch::Twirp::DeployerClient.any_instance
        .expects(:rpc)
        .with(:WorkflowCancel, cancel_args)
        .returns(TwirpResponse.new(status: 200, call_succeeded: true))
        .once

      workflow_run.hard_delete(actor: @pull_request_user)
    end
  end

  context "title and async_title" do
    test "returns the placeholder event name if there's no trigger or a workflow name" do
      check_suite = create(:check_suite_for_actions_app, repository: @repository, name: nil, trigger: nil)
      workflow_run = check_suite.workflow_run
      assert_title "(Unknown event)", workflow_run
    end

    test "returns the placeholder event name if the check suite has been deleted" do
      check_suite = create(:check_suite_for_actions_app, repository: @repository, name: nil, trigger: nil)
      workflow_run_id = check_suite.workflow_run.id
      check_suite.destroy!

      workflow_run = Actions::WorkflowRun.find(workflow_run_id)
      assert_title "(Unknown event)", workflow_run
    end

    test "returns the workflow name if the trigger is nil" do
      workflow_run = create_workflow_run
      assert_title "Node CI", workflow_run
    end

    test "returns the issue title if the trigger is an issue" do
      issue = create(:issue, repository: @repository, title: "An issue")
      workflow_run = create_workflow_run(issue)
      assert_title issue.title, workflow_run
    end

    test "returns the issue title if the trigger is an issue comment" do
      issue = create(:issue, repository: @repository, title: "An issue")
      issue_comment = create(:issue_comment, issue: issue)
      workflow_run = create_workflow_run(issue_comment)
      assert_title issue.title, workflow_run
    end

    test "returns the pull request title if the trigger is a pull request" do
      issue = create(:issue, repository: @repository, title: "A pull request")
      pr = create(:pull_request, :disable_disk_access, repository: @repository, issue: issue)
      workflow_run = create_workflow_run(pr)
      assert_title pr.title, workflow_run
    end

    test "returns the release name if the trigger is a release" do
      example_repo :simple, @repository

      release = create(:release, repository: @repository, tag_name: "v1", name: "The release name")
      workflow_run = create_workflow_run(release)
      assert_title release.name, workflow_run
    end

    test "returns the release tag_name if the trigger is a release and it does not have a name" do
      example_repo :simple, @repository

      release = create(:release, repository: @repository, tag_name: "v1", name: "")
      workflow_run = create_workflow_run(release)
      assert_title release.tag_name, workflow_run
    end

    test "returns the environment if the trigger is a deployment" do
      deployment = create(:deployment, repository: @repository, environment: "staging")
      workflow_run = create_workflow_run(deployment)
      assert_title deployment.environment, workflow_run
    end

    test "returns the latest commit message subject but not the message body if the trigger is a push" do
      example_repo :simple, @repository
      before = @repository.refs.find("master").target.oid
      commit1 = @repository.refs.find("master").append_commit({ message: "Add a thing1\n\nBody text", author: @owner }, @owner) do |changes|
        changes.add("README", "Hello")
      end
      commit2 = @repository.refs.find("master").append_commit({ message: "Add a thing2\n\nBody text", author: @owner }, @owner) do |changes|
        changes.add("README", "Hello")
      end

      push = create(:push, repository: @repository, before: before, after: commit2.oid)
      workflow_run = create_workflow_run(push)
      assert_title "Add a thing2", workflow_run
    end

    test "returns default message, if the trigger is a push and we get GRPC ObjectMissing" do
      example_repo :simple, @repository

      before = @repository.refs.find("master").target.oid

      push = create(:push, repository: @repository, before: before, after: "bb963879b7fb978e977d54d09add7bffb57442ed")
      workflow_run = create_workflow_run(push)
      assert_title "Node CI", workflow_run
    end

    test "returns the name if the event is dynamic and name is present" do
      name = "Custom Name"
      check_suite = create(:check_suite_for_actions_app, :failure, repository: @repository, name: name,  event: "dynamic", workflow_name_hint: "Workflow Name")
      assert_title name, check_suite.workflow_run
    end

    test "returns the workflow run name if it has been explicitly set, even if it would usually custom format another way" do
      issue = create(:issue, repository: @repository, title: "An issue")
      workflow_run = create_workflow_run(issue)
      assert_title "An issue", workflow_run

      workflow_run.update!(name: "My Run Name") # explicit_name is still the default, false, so show the issue title
      assert_title "An issue", workflow_run

      workflow_run.update!(explicit_name: true)
      assert_title "My Run Name", workflow_run
    end
  end

  context "#explicit_name?" do
    test "returns true if the name has been explicitly set" do
      workflow_run = create_workflow_run
      workflow_run.update!(name: "My Run Name", explicit_name: true)
      assert workflow_run.explicit_name?
    end

    test "returns false if the name has not been explicitly set" do
      workflow_run = create_workflow_run
      refute workflow_run.explicit_name?
    end
  end

  context "#permalink" do
    test "returns the latest commit message if the trigger is a push" do
      workflow_run = create_workflow_run

      assert_equal "#{@repository.permalink(include_host: true)}/actions/runs/#{workflow_run.id}", workflow_run.permalink
      assert_equal "#{@repository.permalink(include_host: true)}/actions/runs/#{workflow_run.id}", workflow_run.check_suite.permalink
    end

    test "with pull request number" do
      example_repo :rebase_pull_request, @pull_request_repo

      pull = create(:pull_request,
        repository: @pull_request_repo,
        base_repository: @pull_request_repo,
        base_user: @pull_request_repo.owner,
        base_ref: @pull_request_repo.default_branch,
        head_repository: @pull_request_repo,
        head_user: @pull_request_repo.owner,
        head_ref: "contrib",
        user: @pull_request_user,
      )

      after = @pull_request_repo.refs["contrib"].commit
      check_suite = create(:check_suite_for_actions_app, repository: @pull_request_repo, head_sha: after, head_branch: "contrib", conclusion: :success)
      workflow_run = check_suite.workflow_run

      assert_equal "#{@pull_request_repo.permalink(include_host: true)}/actions/runs/#{workflow_run.id}?pr=#{pull.number}", workflow_run.permalink(pull_request_number: pull.number)
      assert_equal "#{@pull_request_repo.permalink(include_host: true)}/actions/runs/#{workflow_run.id}?pr=#{pull.number}", workflow_run.check_suite.permalink(pull_request_number: pull.number)
    end
  end

  context "#message_id" do
    test "sets an id for to identify workflow runs in emails" do
      workflow_run = create_workflow_run
      expected_message_id = "<#{workflow_run.repository.name_with_display_owner}/workflow-run/#{workflow_run.global_relay_id}/#{workflow_run.updated_at.to_i}@#{GitHub.urls.host_name}>"
      assert_equal expected_message_id, workflow_run.message_id
    end
  end

  context "#search" do
    test "index updated on check_suite save" do
      suite = create(:check_suite_for_actions_app, status: :queued)
      workflow_run = suite.workflow_run
      make_searchable(workflow_run)
      assert_equal "queued", suite.status
      suite.status = "completed"
      perform_enqueued_jobs(only: [AddToSearchIndexJob]) do
        suite.save!
      end

      refresh_search

      result = Actions::WorkflowRun.search(query: "is:completed", repo: workflow_run.repository, workflow_id: workflow_run.workflow.id)

      assert_equal 1, result[:total_count]
      assert_equal "completed", result[:workflow_runs].first.status
    end

    test "does not return results if the workflow run does not match" do
      workflow_run = create_workflow_run
      make_searchable(workflow_run)

      searches = [
        "status:foo",
        "workflow:foo",
        "event:foo",
        "action:foo",
        "conclusion:foo",
        "branch:foo",
        "creator:foo",
        "is:foo",
        "actor:foo",
      ]

      searches.each do |search|
        result = Actions::WorkflowRun.search(query: search, repo: workflow_run.check_suite.repository)

        assert_equal 0, result[:total_count]
      end
    end

    test "does not error if check suite is missing" do
      repository = create :repository

      check_suite = create(:check_suite_for_actions_app, :failure, repository: repository, name: "Node", event: "pull_request", action: "open")
      workflow_run = check_suite.workflow_run
      make_searchable(workflow_run)
      check_suite.destroy!

      older_check_suite = create(:check_suite_for_actions_app, :failure, repository: repository, name: "Node", event: "pull_request", action: "open")
      older_check_suite.update(created_at: 1.day.ago)
      older_workflow_run = older_check_suite.workflow_run
      make_searchable(older_workflow_run)

      result = Actions::WorkflowRun.search(query: "", repo: repository, workflow: workflow_run.workflow.name)
      # total count is calculated prior to pruning, so it is not a good metric here
      assert_equal 1, result[:workflow_runs].size
      assert_equal older_workflow_run.id, result[:workflow_runs].last.id
    end

    test "retrieve distinct values by aggregating on one field from elasticsearch" do
      name = "CI One"
      repository = create :repository
      (1..20).each do |i|
        event = "event_#{i}"
        check_suite = create(:check_suite_for_actions_app, :failure, repository: repository, name: name,  event: event, workflow_name_hint: "Workflow Name")
        make_searchable(check_suite.workflow_run)
      end

      # return distinct values in "event" field
      result = Actions::WorkflowRun.distinct_by(repo: repository, field: :event, size: 50)[:distinct_values]
      assert_equal 20, result.count
      assert result.first.starts_with?("event_")

      # By default only 10 distinct values are returned
      result = Actions::WorkflowRun.distinct_by(repo: repository, field: :event)[:distinct_values]
      assert_equal 10, result.count
    end

    test "Should not return invalid events such as empty string from elasticsearch" do
      name = "CI One"
      repository = create :repository
      check_suite = create(:check_suite_for_actions_app, :failure, repository: repository, name: name,  event: "", workflow_name_hint: "Workflow Name")
      make_searchable(check_suite.workflow_run)

      # filter out return empty string
      result = Actions::WorkflowRun.distinct_by(repo: repository, field: :event, size: 50, filter_empty_value: true)[:distinct_values]
      assert_equal 0, result.count

      # allow empty string
      result = Actions::WorkflowRun.distinct_by(repo: repository, field: :event, size: 50, filter_empty_value: false)[:distinct_values]
      assert_equal 1, result.count
    end

    test "correctly filter by event" do
      repository = create :repository
      check_suite_push = create(:check_suite_for_actions_app, :failure, repository: repository, name: "Node", event: "push")
      make_searchable(check_suite_push.workflow_run)
      check_suite_pr = create(:check_suite_for_actions_app, :failure, repository: repository, name: "Node", event: "pull_request")
      make_searchable(check_suite_pr.workflow_run)

      query = "#{query} event:\"pull_request\""
      result = Actions::WorkflowRun.search(query: query, repo: repository)
      assert_equal 1, result[:total_count]
      workflow_fun_found = result[:workflow_runs].first
      assert_equal check_suite_pr.workflow_run.id, workflow_fun_found.id
    end

    test "correctly filters when is a lab workflow or not" do
      repository = create :repository

      lab_check_suite = create(:check_suite_for_actions_app, :failure, repository: repository, name: "Node", event: "pull_request", action: "open", github_app: @lab_app)
      lab_workflow_run = lab_check_suite.workflow_run
      make_searchable(lab_workflow_run)

      check_suite = create(:check_suite_for_actions_app, :failure, repository: repository, name: "Node", event: "pull_request", action: "open", creator: lab_check_suite.creator)
      workflow_run = check_suite.workflow_run
      make_searchable(workflow_run)

      # lab = true
      result = Actions::WorkflowRun.search(query: "", repo: repository, workflow: "#{lab_workflow_run.workflow.name} (Lab)")
      assert_equal 1, result[:total_count]
      workflow_fun_found = result[:workflow_runs].first
      assert_equal lab_workflow_run.id, workflow_fun_found.id

      # lab = false
      result = Actions::WorkflowRun.search(query: "", repo: repository, workflow: workflow_run.workflow.name)
      assert_equal 1, result[:total_count]
      workflow_fun_found = result[:workflow_runs].first
      assert_equal workflow_run.id, workflow_fun_found.id
    end

    test "correctly sorts by creation date" do
      repository = create :repository

      check_suite = create(:check_suite_for_actions_app, :failure, repository: repository, name: "Node", event: "pull_request", action: "open")
      workflow_run = check_suite.workflow_run
      make_searchable(workflow_run)

      older_check_suite = create(:check_suite_for_actions_app, :failure, repository: repository, name: "Node", event: "pull_request", action: "open")
      older_check_suite.update(created_at: 1.day.ago)
      older_workflow_run = older_check_suite.workflow_run
      make_searchable(older_workflow_run)

      result = Actions::WorkflowRun.search(query: "", repo: repository, workflow: workflow_run.workflow.name)
      assert_equal 2, result[:total_count]
      assert_equal workflow_run.id, result[:workflow_runs].first.id
      assert_equal older_workflow_run.id, result[:workflow_runs].last.id
    end

    test "correctly filters by workflow id" do
      repository = create :repository

      check_suite = create(:check_suite_for_actions_app, :failure, repository: repository, name: "Node", event: "pull_request", action: "open")
      workflow_run = check_suite.workflow_run
      make_searchable(workflow_run)

      ignored_check_suite = create(:check_suite_for_actions_app, :failure, repository: repository, name: "Node", event: "pull_request", action: "open", workflow_file_path: ".github/workflows/ignored.yml")
      ignored_workflow_run = ignored_check_suite.workflow_run
      make_searchable(ignored_workflow_run)

      result = Actions::WorkflowRun.search(query: "", repo: repository, workflow_id: workflow_run.workflow.id)
      assert_equal 1, result[:total_count]
      assert_equal workflow_run.id, result[:workflow_runs].first.id
    end

    test "correctly filter by branch" do
      repository = create :repository
      check_suite = create(:check_suite_for_actions_app, :failure, repository: repository, name: "Node", event: "push", head_branch: "master")
      make_searchable(check_suite.workflow_run)
      check_suite_fullref = create(:check_suite_for_actions_app, :failure, repository: repository, name: "Node", event: "push", head_branch: "refs/heads/master")
      make_searchable(check_suite_fullref.workflow_run)
      check_suite_ignored = create(:check_suite_for_actions_app, :failure, repository: repository, name: "Node", event: "push", head_branch: "refs/master")
      make_searchable(check_suite_ignored.workflow_run)

      query = "#{query} branch:\"master\""
      result = Actions::WorkflowRun.search(query: query, repo: repository)
      assert_equal 2, result[:total_count]
      assert_same_elements [check_suite.workflow_run.id, check_suite_fullref.workflow_run.id], result[:workflow_runs].map(&:id)
    end

    test "filters out results with out of sync status and conclusions" do
      repository = create :repository

      check_suite = create(:check_suite_for_actions_app, repository: repository)
      workflow_run = check_suite.workflow_run
      make_searchable(workflow_run)

      Actions::WorkflowRun.any_instance.stubs(:status).returns("completed")
      Actions::WorkflowRun.any_instance.stubs(:conclusion).returns("success")

      Search.expects(:add_to_search_index).with("workflow_run", workflow_run.id).once

      result = Actions::WorkflowRun.search(query: "is:queued", repo: repository)
      assert_equal 0, result[:workflow_runs].size
    end

    test "correctly filters out spammy workflow runs", skip_enterprise: true do
      repository = create :repository

      # Non-spammy workflow run
      check_suite = create(:check_suite_for_actions_app, repository: repository, created_at: 1.day.ago)
      workflow_run = check_suite.workflow_run

      # Spammy workflow run by current user
      spammy_check_suite = create(:check_suite_for_actions_app, repository: repository)
      spammy_workflow_run = spammy_check_suite.workflow_run
      current_spammy_user = create(:spammy_user)
      spammy_workflow_run.update(actor: current_spammy_user)

      # Spammy workflow run by other spammy user
      other_spammy_check_suite = create(:check_suite_for_actions_app, repository: repository)
      other_spammy_workflow_run = other_spammy_check_suite.workflow_run
      other_spammy_user = create(:spammy_user)
      other_spammy_workflow_run.update(actor: other_spammy_user)
      other_spammy_workflow_run.save

      make_searchable(workflow_run, spammy_workflow_run, other_spammy_workflow_run)

      # Current spammy user - expect only non-spammy workflow run
      result = Actions::WorkflowRun.search(query: "",
                                            repo: repository,
                                            current_user: current_spammy_user,
                                            hide_spammy_runs: true,
                                            show_spammy_runs_by_current_user: false
                                          )

      assert_equal 1, result[:workflow_runs].size
      assert_equal workflow_run.id, result[:workflow_runs].first.id

      # Current spammy user, show spammy runs by current user - expect non-spammy workflow run and current spammy user's workflow run
      result = Actions::WorkflowRun.search(query: "",
                                            repo: repository,
                                            current_user: current_spammy_user,
                                            hide_spammy_runs: true,
                                            show_spammy_runs_by_current_user: true
                                          )

      assert_equal 2, result[:workflow_runs].size
      assert_equal spammy_workflow_run.id, result[:workflow_runs].first.id
      assert_equal workflow_run.id, result[:workflow_runs].last.id

      # No current user - expect only non-spammy workflow run
      result = Actions::WorkflowRun.search(query: "",
                                            repo: repository,
                                            current_user: nil,
                                            hide_spammy_runs: true,
                                            show_spammy_runs_by_current_user: false
                                          )

      assert_equal 1, result[:workflow_runs].size
      assert_equal workflow_run.id, result[:workflow_runs].first.id

      # No current user, show spammy runs by current user - expect only non-spammy workflow run
      result = Actions::WorkflowRun.search(query: "",
                                            repo: repository,
                                            current_user: nil,
                                            hide_spammy_runs: true,
                                            show_spammy_runs_by_current_user: true
                                          )

      assert_equal 1, result[:workflow_runs].size
      assert_equal workflow_run.id, result[:workflow_runs].first.id
    end

    test "removes from search index when destroyed" do
      repository = create :repository

      check_suite = create(:check_suite_for_actions_app, repository: repository)
      workflow_run = check_suite.workflow_run
      make_searchable(workflow_run)

      assert_enqueued_with job: RemoveFromSearchIndexJob do
        expected_keys = { "Body" => "Removing workflow run from search index" }
        assert_logged(**expected_keys) do
          workflow_run.destroy
        end
      end

      result = Actions::WorkflowRun.search(query: "", repo: repository)
      assert_equal 0, result[:workflow_runs].size
    end
  end

  context "#hard_delete" do
    test "creates an audit log" do
      workflow_run = create_workflow_run
      check_suite = workflow_run.check_suite
      check_suite_id = check_suite.id

      mock_delete_build_logs(check_suite:)

      events = assert_performed_audit_entries(count: 1, only: "workflows.delete_workflow_run") do
        workflow_run.hard_delete(actor: @owner)
      end

      expected_payload = {
        started_at: workflow_run.started_at,
        event: "pull_request",
        name: "Node CI",
        workflow_run_id: workflow_run.id,
        workflow_id: check_suite.workflow_run.workflow.id,
        workflow_file_path: check_suite.workflow_run.workflow_file_path,
        head_branch: check_suite.head_branch,
        head_sha: check_suite.head_sha,
        repo: @repository.nwo,
        org: @repository.organization,
        trigger_id: check_suite.trigger&.id,
        actor: @owner.login,
        workflow_run_action: "open",
        operation_type: "remove",
        action: "workflows.delete_workflow_run"
      }

      assert_subset_hash expected_payload, events.first

      assert_nil Actions::WorkflowRun.find_by_id(workflow_run.id)
      assert_nil CheckSuite.find_by_id(check_suite_id)
    end

    test "deletes artifacts associated with workflow_run and check suite" do
      workflow_run = create_workflow_run
      check_suite = workflow_run.check_suite
      artifact = create(:artifact, check_suite: check_suite, repository_id: check_suite.repository_id, source_url: "https://logs.github.com/some-unique-slug-step1")
      artifact_id = artifact.id
      check_suite_id = check_suite.id

      mock_delete_build_logs(check_suite:)
      mock_delete_artifact(artifact_name: "", check_suite:)

      perform_enqueued_jobs(only: DestroyDependentRecordsJob) do
        workflow_run.hard_delete(actor: @owner)
      end

      assert_nil Actions::WorkflowRun.find_by_id(workflow_run.id)
      assert_nil CheckSuite.find_by_id(check_suite_id)
      assert_nil Artifact.find_by_id(artifact_id)
    end

    test "deletes workflow if no workflow runs" do
      check_suite = create(:check_suite_for_actions_app, :completed, :success)
      workflow_run = check_suite.workflow_run
      workflow = workflow_run.workflow

      workflow_run.hard_delete(actor: @owner)

      refute Actions::WorkflowRun.exists?(workflow_run.id)
      assert Actions::Workflow.find(workflow.id)&.deleted?
    end

    test "deletes orphaned workflow run that doesn't have a check suite" do
      check_suite = create(:check_suite_for_actions_app, :in_progress)
      workflow_run = check_suite.workflow_run
      workflow = workflow_run.workflow

      refute workflow_run.deleteable?
      check_suite.destroy!
      assert workflow_run.reload.deleteable?

      workflow_run.hard_delete(actor: @owner)

      refute Actions::WorkflowRun.exists?(workflow_run.id)
      assert Actions::Workflow.find(workflow.id)&.deleted?
    end
  end

  context "#delete_workflow_if_no_runs" do
    test "deletes workflow after destroy if no workflow runs" do
      check_suite = create(:check_suite_for_actions_app)
      workflow_run = check_suite.workflow_run
      workflow = workflow_run.workflow

      workflow_run.destroy

      refute Actions::WorkflowRun.exists?(workflow_run.id)
      assert Actions::Workflow.find(workflow.id)&.deleted?
    end

    test "works if workflow is already deleted" do
      check_suite = create(:check_suite_for_actions_app)
      workflow_run = check_suite.workflow_run
      workflow_run.workflow.delete # skip callbacks

      workflow_run.reload.destroy

      refute Actions::WorkflowRun.exists?(workflow_run.id)
    end
  end

  context "#workflow_job_runs" do
    test "are destroyed when the workflow_run is destroyed" do
      workflow_run = create_workflow_run
      assert_equal 1, workflow_run.workflow_job_runs.count

      assert_difference("Actions::WorkflowJobRun.where(repository_id: #{@repository.id}).count", -1) do
        perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
          workflow_run.destroy
        end
      end
    end
  end

  context "#workflow_run_execution" do
    test "execution is created when workflow run is created and queued" do
      workflow_run = nil
      _, queries = log_queries do
        assert_no_query_warnings do
          workflow_run = create(:check_suite_for_actions_app, repository: @repository, external_id: SimpleUUID::UUID.new.to_guid, completed_log_url: "url").workflow_run
        end
      end

      refute_nil workflow_run
      assert_equal 1, workflow_run.workflow_run_executions.count(:all)

      execution = workflow_run.workflow_run_executions.first
      assert_equal workflow_run, execution.workflow_run
      assert_equal workflow_run.completed_log_url, execution.completed_log_url
      assert_equal workflow_run.external_id, execution.external_id
      assert_equal workflow_run.actor_id, execution.actor_id
      assert_equal workflow_run.repository, execution.repository
      assert_equal workflow_run.started_at, execution.started_at
      assert_nil execution.conclusion
      assert_equal workflow_run.status, execution.status
      assert_nil execution.completed_at
      assert_equal 1, execution.attempt
      assert_equal execution.id, workflow_run.latest_workflow_run_execution.id

      # Assert only 1 write to workflow_run_executions, 2 to workflow_runs (1 to create, 1 to update latest_workflow_run_execution)
      assert_equal 1, queries.count { |q| /INSERT INTO `workflow_runs`/ =~ q.sql }
      assert_equal 1, queries.count { |q| /UPDATE `workflow_runs`/ =~ q.sql }
      assert_equal 1, queries.count { |q| /INSERT INTO `workflow_run_executions`/ =~ q.sql }
      assert_equal 0, queries.count { |q| /UPDATE `workflow_run_executions`/ =~ q.sql }
    end

    test "execution is created when workflow run is created on failure" do
      workflow_run = nil
      _, queries = log_queries do
        assert_no_query_warnings do
          workflow_run = create(:check_suite_for_actions_app, :failure, repository: @repository, external_id: SimpleUUID::UUID.new.to_guid, completed_log_url: "url", completed_at: Time.zone.now).workflow_run
        end
      end

      refute_nil workflow_run
      assert_equal 1, workflow_run.workflow_run_executions.count(:all)

      execution = workflow_run.workflow_run_executions.first
      assert_equal workflow_run, execution.workflow_run
      assert_equal workflow_run.completed_log_url, execution.completed_log_url
      assert_equal workflow_run.external_id, execution.external_id
      assert_equal workflow_run.actor_id, execution.actor_id
      assert_equal workflow_run.repository, execution.repository
      assert_equal workflow_run.started_at, execution.started_at
      assert_equal workflow_run.conclusion, execution.conclusion
      assert_equal workflow_run.status, execution.status
      assert_equal workflow_run.completed_at, execution.completed_at
      assert_equal 1, execution.attempt

      # Assert only 1 write to workflow_run_executions, 2 to workflow_runs (1 to create, 1 to update latest_workflow_run_execution)
      assert_equal 1, queries.count { |q| /INSERT INTO `workflow_runs`/ =~ q.sql }
      assert_equal 1, queries.count { |q| /UPDATE `workflow_runs`/ =~ q.sql }
      assert_equal 1, queries.count { |q| /INSERT INTO `workflow_run_executions`/ =~ q.sql }
      assert_equal 0, queries.count { |q| /UPDATE `workflow_run_executions`/ =~ q.sql }
    end
  end

  context "#create_new_workflow_execution" do
    test "a new execution is created and the check_suite.external_id updated" do
      @contributor = create(:user)
      @repository.add_member(@contributor, action: :write)

      external_id_orig = SimpleUUID::UUID.new.to_guid
      external_id_new = SimpleUUID::UUID.new.to_guid
      workflow_run = create(:check_suite_for_actions_app, repository: @repository, external_id: external_id_orig, completed_log_url: "url").workflow_run
      refute_nil workflow_run
      assert_equal 1, workflow_run.workflow_run_executions.count(:all)
      assert_no_query_warnings do
        workflow_run.create_new_workflow_execution external_id: external_id_new, attempt: 2, actor: @contributor
      end

      execution = workflow_run.workflow_run_executions.order(id: :asc).last
      assert_equal workflow_run, execution.workflow_run
      assert_nil execution.completed_log_url
      assert_equal external_id_new, execution.external_id
      assert_equal @contributor, execution.actor
      assert_equal workflow_run.repository, execution.repository
      assert_equal 2, execution.attempt
      assert_equal execution, workflow_run.latest_workflow_run_execution
      assert_equal external_id_new, execution.workflow_run.external_id
      assert_equal workflow_run.started_at, execution.started_at
    end

    test "a new execution is created with the default workflow_run.actor if none is passed in" do
      workflow_run = create(:check_suite_for_actions_app, repository: @repository, external_id: SimpleUUID::UUID.new.to_guid, completed_log_url: "url").workflow_run
      assert_equal 1, workflow_run.workflow_run_executions.count(:all)

      workflow_run.create_new_workflow_execution external_id: SimpleUUID::UUID.new.to_guid, attempt: 2

      assert_equal 2, workflow_run.reload.workflow_run_executions.count(:all)
      execution = workflow_run.workflow_run_executions.last
      assert_equal workflow_run.actor, execution.actor
    end

    test "does not create duplicate executions if called multiple times" do
      workflow_run = create(:check_suite_for_actions_app, repository: @repository, external_id: SimpleUUID::UUID.new.to_guid, completed_log_url: "url").workflow_run
      assert_equal 1, workflow_run.workflow_run_executions.count(:all)

      external_id_new = SimpleUUID::UUID.new.to_guid
      workflow_run.create_new_workflow_execution external_id: external_id_new, attempt: 2
      workflow_run.create_new_workflow_execution external_id: external_id_new, attempt: 2

      assert_equal 2, workflow_run.reload.workflow_run_executions.count(:all)
    end

    test "copies execution_graph from previous execution if none passed in" do
      Timecop.freeze do
        check_suite = create(:check_suite_for_actions_app, :success_after_create, repository: @repository)
        workflow_run = check_suite.workflow_run
        execution_graph = "{\"stages\":[{\"groups\":[{\"id\":\"|\",\"type\":0,\"jobs\":[{\"id\":\"job_id\",\"name\":\"job\"}]}]}]}"
        workflow_run.latest_workflow_run_execution_with_graph.update!(
          execution_graph: execution_graph,
          status: "completed",
          conclusion: "success",
          completed_at: check_suite.completed_at,
        )

        Timecop.travel(10.minutes)
        check_suite.rerequest(actor: @owner)
        execution = workflow_run.create_new_workflow_execution(external_id: SimpleUUID::UUID.new.to_guid, attempt: 2, execution_graph: nil)
        assert_equal execution_graph, execution.execution_graph
      end
    end

    test "does not copy execution_graph from previous execution if one passed in" do
      workflow_run = create_workflow_run
      previous_execution_graph = "{\"stages\":[{\"groups\":[{\"id\":\"|\",\"type\":0,\"jobs\":[{\"id\":\"caller_job_id.called_job_id\",\"name\":\"caller_job / called_job\"}]}]}]}"
      workflow_run.latest_workflow_run_execution_with_graph.update!(execution_graph: previous_execution_graph)
      workflow_run.workflow_job_runs.first.update!(parent_job_id: "caller_job_id.called_job_id")

      new_execution_graph = "{\"stages\":[{\"groups\":[{\"id\":\"|\",\"type\":0,\"jobs\":[{\"id\":\"caller_job_id.called_job_id1\",\"name\":\"caller_job / called_job1\"},{\"id\":\"caller_job_id.called_job_id2\",\"name\":\"caller_job / called_job2\"}]}]}]}"
      execution = workflow_run.create_new_workflow_execution(external_id: SimpleUUID::UUID.new.to_guid, attempt: 2, execution_graph: new_execution_graph)

      assert_equal new_execution_graph, execution.execution_graph
    end
  end

  context "#latest_workflow_run_execution" do
    test "returns nil if no executions" do
      workflow_run = create(:check_suite_for_actions_app,
        :skip_workflow_run_execution_creation, # Don't create executions
        repository: @repository,
        external_id: SimpleUUID::UUID.new.to_guid,
        completed_log_url: "url"
      ).workflow_run
      assert_equal 0, workflow_run.workflow_run_executions.count(:all)

      refute workflow_run.latest_workflow_run_execution
    end

    test "returns latest execution" do
      workflow_run = create(:check_suite_for_actions_app, repository: @repository, external_id: "1234567890123456", completed_log_url: "url").workflow_run
      assert_equal 1, workflow_run.workflow_run_executions.count(:all)
      assert_equal 1, workflow_run.latest_workflow_run_execution.attempt
    end

    test "sets latest in database if not already set" do
      workflow_run = create(:check_suite_for_actions_app, repository: @repository, external_id: "1234567890123456", completed_log_url: "url").workflow_run
      workflow_run.latest_workflow_run_execution = nil
      workflow_run.save!

      latest_in_db = ApplicationRecord::Domain::RepositoriesActionsChecks.connection.select_value(<<~SQL)
        SELECT latest_workflow_run_execution_id
        FROM workflow_runs
        WHERE repository_id = #{workflow_run.repository_id}
          AND id = #{workflow_run.id}
      SQL

      assert_nil latest_in_db

      # Get latest and set in database
      latest_in_ar = workflow_run.latest_workflow_run_execution

      assert_equal workflow_run.workflow_run_executions.first, latest_in_ar

      latest_in_db = ApplicationRecord::Domain::RepositoriesActionsChecks.connection.select_value(<<~SQL)
        SELECT latest_workflow_run_execution_id
        FROM workflow_runs
        WHERE repository_id = #{workflow_run.repository_id}
          AND id = #{workflow_run.id}
      SQL

      assert_equal latest_in_ar.id, latest_in_db
    end
  end

  context "#latest_workflow_job_runs" do
    test "does not run one query per check run when getting deployments and feature is on" do
      workflow_run = create_workflow_run
      10.times do
        create(:check_run, :success, check_suite: workflow_run.check_suite)
      end

      assert_max_query_count(9, ignore_feature_flags: true) do
        workflow_run.latest_workflow_job_runs_with_deployments
      end
    end

    test "respects execution start and finish time" do
      workflow_run = create_workflow_run
      job1 = workflow_run.workflow_job_runs.first
      execution = workflow_run.workflow_run_executions.first
      Timecop.travel(10.minutes) do
        workflow_run.check_suite.reset
        workflow_run.create_new_workflow_execution(external_id: SimpleUUID::UUID.new.to_guid, attempt: 2)
        run = create(:check_run, :success, check_suite: workflow_run.check_suite)
        job2 = run.workflow_job_run

        job_runs = workflow_run.latest_workflow_job_runs(execution: execution)
        assert_includes job_runs, job1
        refute_includes job_runs, job2
      end
    end

    test "respects execution start and finish time with deployments" do
      workflow_run = create_workflow_run
      job1 = workflow_run.workflow_job_runs.first
      execution = workflow_run.workflow_run_executions.first
      # Travel forward 10 minutes and start a new execution to support time-based and execution-based job filtering
      Timecop.travel(10.minutes) do
        workflow_run.check_suite.reset
        workflow_run.create_new_workflow_execution(external_id: SimpleUUID::UUID.new.to_guid, attempt: 2)
        run = create(:check_run, :success, check_suite: workflow_run.check_suite)
        job2 = run.workflow_job_run

        job_runs = workflow_run.latest_workflow_job_runs_with_deployments(execution: execution)
        assert_includes job_runs, job1
        refute_includes job_runs, job2
      end
    end
  end

  context "#latest_check_runs" do
    test "filters check_runs on time where there are no executions" do
      check_suite = create(:check_suite_for_actions_app, :success_after_create, :skip_workflow_run_execution_creation, repository: @repository)
      workflow_run = check_suite.workflow_run
      check_run1 = workflow_run.workflow_job_runs.first.check_run

      Timecop.freeze do
        Timecop.travel(10.minutes)
        check_suite.reset
        check_run2 = create(:check_run, :success, check_suite: workflow_run.check_suite)
        check_runs = workflow_run.latest_check_runs
        assert_includes check_runs, check_run2
        refute_includes check_runs, check_run1
      end
    end

    test "filters check_runs by attempt when there are executions" do
      workflow_run = create_workflow_run
      check_run1 = workflow_run.workflow_job_runs.first.check_run
      execution = workflow_run.workflow_run_executions.first

      Timecop.freeze do
        Timecop.travel(10.minutes)
        workflow_run.check_suite.reset
        workflow_run.create_new_workflow_execution(external_id: SimpleUUID::UUID.new.to_guid, attempt: 2)
        check_run2 = create(:check_run, :success, check_suite: workflow_run.check_suite)

        check_runs = workflow_run.latest_check_runs(execution: execution)
        assert_includes check_runs, check_run1
        refute_includes check_runs, check_run2
      end
    end
  end

  context "has multiple attempts" do
    test "false by default" do
      workflow_run = create_workflow_run
      refute workflow_run.has_multiple_attempts
    end

    test "true if rerun" do
      check_suite = create :check_suite_for_actions_app, :success_after_create, repository: @repository
      workflow_run = check_suite.workflow_run
      workflow_run.create_new_workflow_execution(external_id: SimpleUUID::UUID.new.to_guid, attempt: 2)
      workflow_run.reload

      assert workflow_run.has_multiple_attempts
    end
  end

  context "processing rerun" do
    test "true after rerun" do
      check_suite = create :check_suite_for_actions_app, :success_after_create, repository: @repository
      check_suite.rerequest(actor: @owner)

      check_suite.workflow_run.reload
      assert check_suite.workflow_run.processing_retry?
    end

    test "false if new execution is created after rerun" do
      check_suite = create :check_suite_for_actions_app, :success_after_create, repository: @repository
      check_suite.rerequest(actor: @owner)

      check_suite.workflow_run.reload

      check_suite.workflow_run.create_new_workflow_execution(external_id: SimpleUUID::UUID.new.to_guid, attempt: 2)

      refute check_suite.workflow_run.processing_retry?
    end
  end

  context "#failed_workflow_job_runs" do
    test "returns failed job runs" do
      check_suite = create(:check_suite_for_actions_app, repository: @repository)
      check_run_success = create(:check_run_for_actions_app, :success, name: "success", check_suite: check_suite)
      check_run_failure = create(:check_run_for_actions_app, :failure, name: "failure", check_suite: check_suite)
      workflow_run = check_suite.workflow_run
      workflow_job_run_success = check_run_success.workflow_job_run
      workflow_job_run_failure = check_run_failure.workflow_job_run

      failed_workflow_job_runs = workflow_run.failed_workflow_job_runs
      assert_same_elements [workflow_job_run_failure], failed_workflow_job_runs
    end

    test "returns cancelled job runs" do
      check_suite = create(:check_suite_for_actions_app, repository: @repository)
      check_run_success = create(:check_run_for_actions_app, :success, name: "success", check_suite: check_suite)
      check_run_cancelled = create(:check_run_for_actions_app, :cancelled, name: "cancelled", check_suite: check_suite)
      workflow_run = check_suite.workflow_run
      workflow_job_run_success = check_run_success.workflow_job_run
      workflow_job_run_cancelled = check_run_cancelled.workflow_job_run

      failed_workflow_job_runs = workflow_run.failed_workflow_job_runs
      assert_same_elements [workflow_job_run_cancelled], failed_workflow_job_runs
    end

    test "does not return job runs that were healed (launch sets external_id to the string `github-actions`)" do
      check_run = create(:check_run_for_actions_app, :success, external_id: "github-actions")

      assert_empty check_run.check_suite.workflow_run.failed_workflow_job_runs
    end
  end

  context "#has_failed_workflow_job_runs?" do
    test "returns true if there are failed job runs" do
      check_suite = create(:check_suite_for_actions_app, repository: @repository)
      create(:check_run_for_actions_app, :success, name: "success", check_suite: check_suite)
      create(:check_run_for_actions_app, :failure, name: "failure", check_suite: check_suite)

      assert check_suite.workflow_run.has_failed_workflow_job_runs?
    end

    test "returns true if there are cancelled job runs" do
      check_suite = create(:check_suite_for_actions_app, repository: @repository)
      create(:check_run_for_actions_app, :success, name: "success", check_suite: check_suite)
      create(:check_run_for_actions_app, :cancelled, name: "cancelled", check_suite: check_suite)

      assert check_suite.workflow_run.has_failed_workflow_job_runs?
    end

    test "returns false if there are only successful jobs runs" do
      check_suite = create(:check_suite_for_actions_app, repository: @repository)
      create(:check_run_for_actions_app, :success, name: "success", check_suite: check_suite)

      refute check_suite.workflow_run.has_failed_workflow_job_runs?
    end

    test "returns false for job runs that were healed (launch sets external_id to the string `github-actions`)" do
      check_suite = create(:check_suite_for_actions_app, repository: @repository)
      create(:check_run_for_actions_app, :success, name: "success", external_id: "github-actions", check_suite: check_suite)

      refute check_suite.workflow_run.has_failed_workflow_job_runs?
    end
  end

  context "#Emitting workflow_run audit logs" do
    test "after workflow_run creation" do
      GitHub.stubs(:actions_enabled?).returns(true)
      make_trusted_oauth_apps_owner

      workflow_file_path = ".github/workflows/main.yml"
      check_suite = nil
      events = assert_performed_audit_entries(count: 1, only: "workflows.created_workflow_run") do
        check_suite = create :check_suite_for_actions_app,
                             repository: @audited_repo,
                             workflow_file_path: workflow_file_path,
                             name: "Node CI",
                             external_id: SimpleUUID::UUID.new.to_guid,
                             event: "pull_request",
                             action: "open"
      end

      expected_payload = {
        started_at: check_suite.started_at,
        event: "pull_request",
        name: "Node CI",
        workflow_run_id: check_suite.workflow_run.id,
        workflow_id: check_suite.workflow_run.workflow.id,
        workflow_file_path: check_suite.workflow_run.workflow_file_path,
        head_branch: check_suite.head_branch,
        head_sha: check_suite.head_sha,
        repo: @audited_repo.name_with_owner,
        org: @audited_repo.organization.login,
        trigger_id: check_suite.trigger&.id,
        actor: check_suite.creator.login,
        workflow_run_action: "open",
        operation_type: "create",
        action: "workflows.created_workflow_run"
      }

      assert_subset_hash expected_payload, events.first
      refute_nil Actions::WorkflowRun.find_by_id(check_suite.workflow_run.id)
    end

    test "after workflow_run completion" do
      GitHub.stubs(:actions_enabled?).returns(true)
      make_trusted_oauth_apps_owner

      workflow_file_path = ".github/workflows/main.yml"
      check_suite = create :check_suite_for_actions_app,
                           repository: @audited_repo,
                           workflow_file_path: workflow_file_path,
                           name: "Node CI",
                           external_id: SimpleUUID::UUID.new.to_guid,
                           event: "pull_request",
                           action: "open"

      events = assert_performed_audit_entries(count: 1, only: "workflows.completed_workflow_run") do
        check_suite.update(conclusion: :success)
      end

      expected_payload = {
        started_at: check_suite.started_at,
        event: "pull_request",
        name: "Node CI",
        workflow_run_id: check_suite.workflow_run.id,
        workflow_id: check_suite.workflow_run.workflow.id,
        workflow_file_path: check_suite.workflow_run.workflow_file_path,
        head_branch: check_suite.head_branch,
        head_sha: check_suite.head_sha,
        repo: @audited_repo.name_with_owner,
        org: @audited_repo.organization.login,
        trigger_id: check_suite.trigger&.id,
        actor: check_suite.creator.login,
        run_number: 1,
        workflow_run_action: "open",
        operation_type: "modify",
        action: "workflows.completed_workflow_run",
        conclusion: "success",
        completed_at: check_suite.completed_at,
        re_run: false,
        run_attempt: 1,
      }

      assert_subset_hash expected_payload, events.first
      refute_nil Actions::WorkflowRun.find_by_id(check_suite.workflow_run.id)
    end

    test "after workflow_run completion for non business repo", skip_enterprise: true do
      GitHub.stubs(:actions_enabled?).returns(true)
      make_trusted_oauth_apps_owner

      workflow_file_path = ".github/workflows/main.yml"
      check_suite = create :check_suite_for_actions_app,
                           repository: @repository,
                           workflow_file_path: workflow_file_path,
                           name: "Node CI",
                           external_id: SimpleUUID::UUID.new.to_guid,
                           event: "pull_request",
                           action: "open"

      assert_performed_audit_entries(count: 0, only: "workflows.completed_workflow_run") do
        check_suite.update(conclusion: :success)
      end
    end

    test "after workflow_run rerun" do
      GitHub.stubs(:actions_enabled?).returns(true)

      make_trusted_oauth_apps_owner
      user = create :user
      @business_org.add_admin(user)

      workflow_file_path = ".github/workflows/main.yml"
      check_suite = create :check_suite_for_actions_app,
                           repository: @audited_repo,
                           workflow_file_path: workflow_file_path,
                           name: "Node CI",
                           external_id: SimpleUUID::UUID.new.to_guid,
                           event: "pull_request",
                           action: "open",
                           created_at: 5.minutes.ago

      check_run = create(:check_run, check_suite: check_suite, status: :completed, conclusion: :success, completed_at: Time.now)
      check_suite.update(conclusion: :success)
      original_start = check_suite.started_at
      events = assert_performed_audit_entries(count: 1, only: "workflows.rerun_workflow_run") do
        check_suite.rerequest(actor: user)
      end

      expected_payload = {
        started_at: check_suite.started_at,
        event: "pull_request",
        name: "Node CI",
        workflow_run_id: check_suite.workflow_run.id,
        workflow_id: check_suite.workflow_run.workflow.id,
        workflow_file_path: check_suite.workflow_run.workflow_file_path,
        head_branch: check_suite.head_branch,
        head_sha: check_suite.head_sha,
        repo: @audited_repo.name_with_owner,
        org: @audited_repo.organization.login,
        trigger_id: check_suite.trigger&.id,
        actor: user.login,
        run_number: 1,
        workflow_run_action: "open",
        operation_type: "modify",
        action: "workflows.rerun_workflow_run"
      }

      assert_subset_hash expected_payload, events.first
      refute_nil Actions::WorkflowRun.find_by_id(check_suite.workflow_run.id)
      assert_equal "queued", check_suite.workflow_run.status
      assert_equal true, check_suite.has_reruns
      refute_equal original_start, check_suite.started_at
    end

    test "after workflow_run rerun, payload contains attempt when execution present and rerun_type: all_jobs" do
      GitHub.stubs(:actions_enabled?).returns(true)

      make_trusted_oauth_apps_owner
      user = create :user
      @business_org.add_admin(user)

      workflow_file_path = ".github/workflows/main.yml"
      check_suite = create :check_suite_for_actions_app,
                           repository: @audited_repo,
                           workflow_file_path: workflow_file_path,
                           name: "Node CI",
                           external_id: SimpleUUID::UUID.new.to_guid,
                           event: "pull_request",
                           action: "open",
                           created_at: 5.minutes.ago

      check_run = create(:check_run, check_suite: check_suite, status: :completed, conclusion: :success, completed_at: Time.now)
      check_suite.update(conclusion: :success)
      events = assert_performed_audit_entries(count: 1, only: "workflows.rerun_workflow_run") do
        check_suite.rerequest(actor: user)
      end

      expected_payload = {
        run_attempt: 2,
        rerun_type: "all_jobs",
      }

      assert_subset_hash expected_payload, events.first
    end

    test "after workflow_run rerun of all failed jobs, payload contains rerun_type: failed_jobs" do
      GitHub.stubs(:actions_enabled?).returns(true)

      make_trusted_oauth_apps_owner
      user = create :user
      @business_org.add_admin(user)

      check_suite = create :check_suite_for_actions_app, :failure, repository: @audited_repo

      events = assert_performed_audit_entries(count: 1, only: "workflows.rerun_workflow_run") do
        check_suite.rerequest(actor: user, only_failed_check_runs: true)
      end

      expected_payload = {
        rerun_type: "failed_jobs",
      }

      assert_subset_hash expected_payload, events.first
    end

    test "after workflow_run rerun of a single job, payload contains rerun_type: single_job and a check_run_id" do
      GitHub.stubs(:actions_enabled?).returns(true)

      make_trusted_oauth_apps_owner
      user = create :user
      @business_org.add_admin(user)

      check_suite = create :check_suite_for_actions_app, :success, repository: @audited_repo
      check_run = check_suite.check_runs.first

      events = assert_performed_audit_entries(count: 1, only: "workflows.rerun_workflow_run") do
        check_suite.rerequest(actor: user, only_check_run_id: check_run.id)
      end

      expected_payload = {
        rerun_type: "single_job",
        check_run_id: check_run.id,
      }

      assert_subset_hash expected_payload, events.first
    end

    test "after workflow_run cancel" do

      GitHub.stubs(:actions_enabled?).returns(true)

      make_trusted_oauth_apps_owner
      user = create :user
      @business_org.add_admin(user)

      workflow_file_path = ".github/workflows/main.yml"
      check_suite = create :check_suite_for_actions_app,
                           repository: @audited_repo,
                           workflow_file_path: workflow_file_path,
                           name: "Node CI",
                           external_id: SimpleUUID::UUID.new.to_guid,
                           event: "pull_request",
                           action: "open",
                           created_at: 10.minutes.ago

      check_run = create(:check_run, check_suite: check_suite, status: :completed, conclusion: :cancelled, completed_at: 5.minutes.ago)
      cancelled_at = Time.now

      cancel_args = {
        check_suite_id: GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: check_suite.global_relay_id),
        canceled_by_id: user.id,
        canceled_by_name: user.display_login,
        canceled_by_global_id: GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: user.global_relay_id),
        force: false
      }

      Launch::Twirp::DeployerClient.any_instance
        .expects(:rpc)
        .with(:WorkflowCancel, cancel_args)
        .returns(TwirpResponse.new(status: 200, call_succeeded: true))
        .once

      events = assert_performed_audit_entries(count: 1, only: "workflows.cancel_workflow_run") do
        Time.stubs(:now).returns(cancelled_at)
        check_suite.cancel(actor: user)
      end

      expected_payload = {
        started_at: check_suite.started_at,
        cancelled_at: check_suite.cancelled_at,
        event: "pull_request",
        name: "Node CI",
        workflow_run_id: check_suite.workflow_run.id,
        workflow_id: check_suite.workflow_run.workflow.id,
        workflow_file_path: check_suite.workflow_run.workflow_file_path,
        head_branch: check_suite.head_branch,
        head_sha: check_suite.head_sha,
        repo: @audited_repo.name_with_owner,
        org: @audited_repo.organization.login,
        trigger_id: check_suite.trigger&.id,
        actor: user.login,
        run_number: 1,
        workflow_run_action: "open",
        operation_type: "modify",
        action: "workflows.cancel_workflow_run"
      }

      run = Actions::WorkflowRun.find_by_id(check_suite.workflow_run.id)

      assert run
      assert run.cancelled?
      assert_subset_hash expected_payload, events.first
      refute_equal user, check_suite.creator
    end

    test "doesn't load the trigger just to get the trigger ID" do
      GitHub.stubs(:actions_enabled?).returns(true)

      issue = create(:issue, repository: @audited_repo)
      events = assert_performed_audit_entries(count: 1, only: "workflows.created_workflow_run") do
        assert_query_count_per_table({ issues: 0 }) do
          create :check_suite_for_actions_app, repository: @audited_repo, trigger: issue
        end
      end

      assert_equal issue.id, events.first[:trigger_id]
    end
  end

  context "#user_hidden", skip_enterprise: true do
    test "user_hidden is set when the check suite creator is marked spammy" do
      user = create(:user)
      run = create_workflow_run(creator: user)
      refute run.user_hidden

      perform_enqueued_jobs(only: [UpdateTableUserHiddenJob]) do
        user.mark_as_spammy
      end
      assert run.reload.user_hidden
    end

    test "user_hidden is unset when the check suite creator is marked not spammy" do
      user = create(:user)
      run = create_workflow_run(creator: user)
      perform_enqueued_jobs(only: [UpdateTableUserHiddenJob]) do
        user.mark_as_spammy
      end
      assert run.reload.user_hidden

      perform_enqueued_jobs(only: [UpdateTableUserHiddenJob]) do
        user.mark_not_spammy
      end
      refute run.reload.user_hidden
    end

    test "only runs created by one user are marked spammy" do
      user1 = create(:user)
      user1_runs = []

      user2 = create(:user)
      user2_runs = []

      (0..5).each do
        user1_runs.append(create_workflow_run(creator: user1))
        user2_runs.append(create_workflow_run(creator: user2))
      end

      perform_enqueued_jobs(only: [UpdateTableUserHiddenJob]) do
        user1.mark_as_spammy
      end

      user1_runs.each do |run|
        assert run.reload.user_hidden
      end

      user2_runs.each do |run|
        refute run.reload.user_hidden
      end
    end

    test "user_hidden is set for every run when there's a large number associated with one creator" do
      user = create(:user)

      # update_user_hidden uses a batch size of 50, so we'll test creating more runs than that.
      runs = (0..100).map do
        create_workflow_run(creator: user)
      end

      perform_enqueued_jobs(only: [UpdateTableUserHiddenJob]) do
        user.mark_as_spammy
      end

      runs.each do |run|
        assert run.reload.user_hidden
      end
    end
  end

  context "#downstream_jobs_for" do
    test "returns empty array if no jobs passed in" do
      workflow_run = create_workflow_run
      downstream = workflow_run.downstream_jobs_for
      assert_nothing_raised { workflow_run.execution_graph }
      assert downstream.empty?
    end

    test "no downstream jobs" do
      last_job = @complex_check_suite.check_runs.with_display_name("deploy").first.workflow_job_run
      assert last_job.present?

      # load graph with run
      run_with_graph = Actions::WorkflowRun.with_execution_graph.find(@complex_check_suite.workflow_run.id)
      downstream = run_with_graph.downstream_jobs_for(jobs: [last_job])
      assert downstream.empty?
    end

    test "excludes upstream jobs" do
      middle_graph_job = @complex_check_suite.check_runs.with_display_name("integration-test").first.workflow_job_run
      assert middle_graph_job.present?

      # load graph with run
      run_with_graph = Actions::WorkflowRun.with_execution_graph.find(@complex_check_suite.workflow_run.id)
      downstream = run_with_graph.downstream_jobs_for(jobs: [middle_graph_job]).map(&:parent_job_id)
      assert_same_elements %w[stage stage deploy], downstream
    end

    test "one job in matrix" do
      matrix_job = @complex_check_suite.check_runs.with_display_name("build-frontend (1)").first.workflow_job_run
      assert matrix_job.present?

      # load graph with run
      run_with_graph = Actions::WorkflowRun.with_execution_graph.find(@complex_check_suite.workflow_run.id)
      downstream = run_with_graph.downstream_jobs_for(jobs: [matrix_job]).map(&:parent_job_id)
      assert_same_elements %w[test-frontend-A test-frontend-B integration-test stage stage deploy], downstream
    end

    test "multiple jobs" do
      matrix_job1 = @complex_check_suite.check_runs.with_display_name("build-frontend (1)").first.workflow_job_run
      assert matrix_job1.present?
      matrix_job2 = @complex_check_suite.check_runs.with_display_name("build-frontend (2)").first.workflow_job_run
      assert matrix_job2.present?
      middle_graph_job = @complex_check_suite.check_runs.with_display_name("integration-test").first.workflow_job_run
      assert middle_graph_job.present?

      # load graph with run
      run_with_graph = Actions::WorkflowRun.with_execution_graph.find(@complex_check_suite.workflow_run.id)
      downstream = run_with_graph.downstream_jobs_for(jobs: [matrix_job1, matrix_job2, middle_graph_job]).map(&:parent_job_id)
      assert_same_elements %w[test-frontend-A test-frontend-B integration-test stage stage deploy], downstream
    end

    test "returns an empty array when there is no graph" do
      matrix_job = @complex_check_suite.check_runs.with_display_name("build-frontend (1)").first.workflow_job_run

      workflow_run = Actions::WorkflowRun.new
      assert_empty workflow_run.downstream_jobs_for(jobs: [matrix_job])
    end
  end

  context "#latest_workflow_run_job" do
    test "returns the latest job" do
      workflow_run = create_workflow_run
      10.times do
        create(:check_run, :success, check_suite: workflow_run.check_suite)
      end

      assert_equal workflow_run.latest_workflow_run_job, workflow_run.workflow_job_runs.order(id: :desc).first
    end
  end

  context "cleanup" do
    test "deletes workflow_run_execution if workflow_run is deleted" do
      workflow_run = create_workflow_run

      wfre_id = workflow_run.workflow_run_executions.first.id
      refute_nil Actions::WorkflowRunExecution.find(wfre_id)

      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
        workflow_run.destroy!
      end

      assert_raises ActiveRecord::RecordNotFound do
        Actions::WorkflowRunExecution.find(wfre_id)
      end
    end
  end

  context "authorization" do
    test "delegates permission attributes to check_suite" do
      workflow_run = create_workflow_run

      expected_attributes = {
        "subject.type" => "Actions::WorkflowRun",
        "subject.id" => workflow_run.id,
        "subject.repository.id" => workflow_run.repository_id,
        "subject.repository.owner.id" => workflow_run.repository.owner.id,
        "subject.repository.internal" => workflow_run.repository.internal?,
        "subject.repository.public" => workflow_run.repository.public?,
        "subject.owning_organization.id" => workflow_run.repository.owning_organization_id,
        "subject.business.id" => workflow_run.repository.owner&.async_business&.sync&.id,
      }

      assert_equal expected_attributes, workflow_run.permissions_wrapper.subject_attributes
    end

    test "policy allows pusher to receive a notification on a public repo" do
      workflow_run = create_workflow_run
      decision = ::Permissions::Enforcer.authorize(
        action: :receive_notification,
        actor: workflow_run.actor,
        subject: workflow_run,
      )

      assert_equal :ALLOW, decision.result
    end

    test "policy allows pusher to receive a notification on a private repo if pusher has access to private repo" do
      user = create(:user)
      repository = create(:private_repository, owner: user)
      check_suite_name = "Node CI"
      check_suite = create(:check_suite_for_actions_app, :success_after_create, repository: repository, creator: user, name: check_suite_name, trigger: nil, event: "pull_request", action: "open")
      workflow_run = check_suite.workflow_run

      decision = ::Permissions::Enforcer.authorize(
        action: :receive_notification,
        actor: user,
        subject: workflow_run,
      )

      assert_equal :ALLOW, decision.result
    end

    test "policy blocks user that has no access to the repository from receiving a notification" do
      user = create(:user)
      repository = create(:private_repository)
      check_suite_name = "Node CI"
      check_suite = create(:check_suite_for_actions_app, :success_after_create, repository: repository, creator: user, name: check_suite_name, trigger: nil, event: "pull_request", action: "open")
      workflow_run = check_suite.workflow_run

      decision = ::Permissions::Enforcer.authorize(
        action: :receive_notification,
        actor: user,
        subject: workflow_run,
      )

      assert_equal :DENY, decision.result
    end
  end

  context "authorization v2" do
    test "policy allows pusher to receive a notification on a public repo" do
      workflow_run = create_workflow_run
      decision = ::Permissions::Enforcer.authorize(
        action: :receive_notification,
        actor: workflow_run.actor,
        subject: workflow_run,
        context: {
          version: 2,
          "notification.initiator.id": workflow_run.actor.id,
          "notification.initiator.type": "User",
        },
      )

      assert_equal :ALLOW, decision.result
    end

    test "policy allows pusher to receive a notification on a private repo if pusher has access to private repo" do
      user = create(:user)
      repository = create(:private_repository, owner: user)
      check_suite_name = "Node CI"
      check_suite = create(:check_suite_for_actions_app, :success_after_create, repository: repository, creator: user, name: check_suite_name, trigger: nil, event: "pull_request", action: "open")
      workflow_run = check_suite.workflow_run

      decision = ::Permissions::Enforcer.authorize(
        action: :receive_notification,
        actor: user,
        subject: workflow_run,
        context: {
          version: 2,
          "notification.initiator.id": workflow_run.actor.id,
          "notification.initiator.type": "User",
        },
      )

      assert_equal :ALLOW, decision.result
    end

    test "policy blocks user that has no access to the repository from receiving a notification" do
      user = create(:user)
      repository = create(:private_repository)
      check_suite_name = "Node CI"
      check_suite = create(:check_suite_for_actions_app, :success_after_create, repository: repository, creator: user, name: check_suite_name, trigger: nil, event: "pull_request", action: "open")
      workflow_run = check_suite.workflow_run

      decision = ::Permissions::Enforcer.authorize(
        action: :receive_notification,
        actor: user,
        subject: workflow_run,
        context: {
          version: 2,
          "notification.initiator.id": user.id,
          "notification.initiator.type": "User",
        },
      )

      assert_equal :DENY, decision.result
    end

    test "policy blocks user that is spammy" do
      user = create(:spammy_user)
      repository = create(:private_repository, owner: user)
      check_suite_name = "Node CI"
      check_suite = create(:check_suite_for_actions_app, :success_after_create, repository: repository, creator: user, name: check_suite_name, trigger: nil, event: "pull_request", action: "open")
      workflow_run = check_suite.workflow_run

      decision = ::Permissions::Enforcer.authorize(
        action: :receive_notification,
        actor: user,
        subject: workflow_run,
        context: {
          version: 2,
          "notification.initiator.id": workflow_run.actor.id,
          "notification.initiator.type": "User",
        },
      )

      assert_equal :DENY, decision.result
    end

    test "policy blocks user that is suspended" do
      user = create(:suspended_user)
      repository = create(:private_repository, owner: user)
      check_suite_name = "Node CI"
      check_suite = create(:check_suite_for_actions_app, :success_after_create, repository: repository, creator: user, name: check_suite_name, trigger: nil, event: "pull_request", action: "open")
      workflow_run = check_suite.workflow_run

      decision = ::Permissions::Enforcer.authorize(
        action: :receive_notification,
        actor: user,
        subject: workflow_run,
        context: {
          version: 2,
          "notification.initiator.id": workflow_run.actor.id,
          "notification.initiator.type": "User",
        },
      )

      assert_equal :DENY, decision.result
    end
  end

  context "#emit_workflow_run_deleted" do
    test "emits a hydro event with the correct payload" do
      payload = {
        repository_id: 3,
        workflow_run_id: 123,
        check_suite_id: 456,
        execution_external_id: SimpleUUID::UUID.new.to_guid
      }

      Actions::WorkflowRun.emit_workflow_run_deleted(**payload)

      assert_hydro_published({
        repository_id: payload[:repository_id],
        workflow_run_id: payload[:workflow_run_id],
        check_suite_id: payload[:check_suite_id],
        workflow_run_backend_id: payload[:execution_external_id]
      }, schema: "github.actions.v0.WorkflowRunDeleted")
    end

    test "emits a hydro events for each execution when a workflow run is deleted" do
      check_suite = create :check_suite_for_actions_app, :success_after_create, repository: @repository
      workflow_run = check_suite.workflow_run
      workflow_run.create_new_workflow_execution(external_id: SimpleUUID::UUID.new.to_guid, attempt: 2)
      workflow_run.reload

      workflow_run.destroy

      num_executions = workflow_run.workflow_run_executions.size
      assert_hydro_messages(count: num_executions, schema: "github.actions.v0.WorkflowRunDeleted")

      workflow_run.workflow_run_executions.each do |execution|
        assert_hydro_published({
          repository_id: workflow_run.repository_id,
          workflow_run_id: workflow_run.id,
          check_suite_id: workflow_run.check_suite_id,
          workflow_run_backend_id: execution.external_id
        }, schema: "github.actions.v0.WorkflowRunDeleted")
      end
    end
  end

  context "opt out of results" do
    test "return true from opt_out_from_results if the repository is opted out" do
      check_suite = create :check_suite_for_actions_app, :success_after_create, repository: @repository
      workflow_run = check_suite.workflow_run
      GitHub.flipper[:actions_opt_out_results_service].enable(@repository)
      assert workflow_run.opt_out_from_results?
    end
    test "return true from opt_out_from_results if the org is opted out" do
      check_suite = create :check_suite_for_actions_app, :success_after_create, repository: @repository
      workflow_run = check_suite.workflow_run
      GitHub.flipper[:actions_opt_out_results_service].enable(@owner)
      assert workflow_run.opt_out_from_results?
    end
    test "return false from logs_via_results_service if opt_out_from_results return true" do
      check_suite = create :check_suite_for_actions_app, :success_after_create, repository: @repository
      workflow_run = check_suite.workflow_run
      GitHub.flipper[:actions_opt_out_results_service].enable(@owner)
      GitHub.flipper[:actions_favor_results_service_logs].enable(@repository)
      refute workflow_run.logs_via_results_service?
    end
    test "return true from logs_via_results_service if opt_out_from_results return false" do
      check_suite = create :check_suite_for_actions_app, :success_after_create, repository: @repository
      workflow_run = check_suite.workflow_run
      GitHub.flipper[:actions_opt_out_results_service].disable(@owner)
      GitHub.flipper[:actions_favor_results_service_logs].enable(@repository)
      assert workflow_run.logs_via_results_service?
    end
  end

  context "head_branch" do
    test "head_branch returns the correctly qualified ref branches" do
      branch_workflow_run = create_workflow_run(head_branch: "refs/heads/master")
      tag_workflow_run = create_workflow_run(head_branch: "refs/tags/my-tag")

      assert_equal "master", branch_workflow_run.head_branch
      assert_equal "refs/heads/master", branch_workflow_run.head_branch(fully_qualified: true)

      assert_equal "my-tag", tag_workflow_run.head_branch
      assert_equal "refs/tags/my-tag", tag_workflow_run.head_branch(fully_qualified: true)
    end
  end

  test "is deleted with repository soft-delete" do
    other_workflow_run = create(:check_suite_for_actions_app, :success_after_create).workflow_run

    assert_destroyed_in_background_with_parent do |config|
      config.parent_record = @repository
      config.expect_destroyed = [@complex_check_suite.workflow_run]
      config.expect_not_destroyed = [other_workflow_run]
      config.soft_delete = ->(repo) { repo.remove(User.ghost, synchronous: true) }
    end
  end

  context "#trigger" do
    test "returns the trigger if it exists" do
      push = create(:push, repository: @repository)
      workflow_run = create_workflow_run(push)

      assert_equal push, workflow_run.trigger
    end

    test "batches queries for multiple triggers" do
      push = create(:push, repository: @repository)
      workflow_run_push = create_workflow_run(push)

      issue = create(:issue, repository: @repository)
      workflow_run_issue = create_workflow_run(issue)

      deployment_1 = create(:deployment, repository: @repository)
      workflow_run_deployment_1 = create_workflow_run(deployment_1)

      deployment_2 = create(:deployment, repository: @repository)
      workflow_run_deployment_2 = create_workflow_run(deployment_2)

      workflow_runs = [workflow_run_push, workflow_run_issue, workflow_run_deployment_1, workflow_run_deployment_2]
      assert_query_count_per_table({
        pushes: 1,
        issues: 1,
        deployments: 1, # still only one query here, even though we have multiple deployment triggers
      }) do
        GitHub::PrefillAssociations.prefill_batch_method(workflow_runs, :trigger)
      end

      # the triggers should all be preloaded by the above call, so no more queries should be executed here.
      assert_no_queries do
        assert_equal push, workflow_runs[0].trigger
        assert_equal issue, workflow_runs[1].trigger
        assert_equal deployment_1, workflow_runs[2].trigger
        assert_equal deployment_2, workflow_runs[3].trigger
      end
    end
  end
end
