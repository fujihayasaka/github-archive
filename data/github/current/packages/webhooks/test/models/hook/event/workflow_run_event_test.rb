# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventWorkflowRunEventTest < GitHub::TestCase
  include HookEventTestHelper
  include GitHub::LoggerHelper

  fixtures do
    GitHub.stubs(:actions_enabled?).returns(true)
    make_trusted_oauth_apps_owner

    @repository   = create :repository, from_example: :simple
    @actions_app  = create :launch_integration

    sha = @repository.heads.find("master").target_oid
    @workflow = create(:workflow, repository: @repository, path: ".github/workflows/main.yml")
    check_suite = create(:check_suite_for_actions_app,
      status: :in_progress,
      conclusion: nil,
      head_sha: sha,
      repository: @repository,
      head_repository: @repository,
      event: "push",
      workflow_file_path: ".github/workflows/main.yml",
      completed_log_url: "https://logs.github.com/something",
      rerequestable: true,
      created_at: 3.weeks.ago
    )

    @workflow_run = check_suite.workflow_run
    @installation = make_integration_installation integration: @actions_app, target: @repository.owner, permissions: { "actions" => :write }
  end

  context "#run_id" do
    test "is required" do
      assert_event_required_attributes Hook::Event::WorkflowRunEvent, :run_id
    end
  end

  context "#workflow_run" do
    test "returns the specified workflow_run" do
      event = Hook::Event::WorkflowRunEvent.new(run_id: @workflow_run.id, action: "completed")
      assert_equal @workflow_run, event.workflow_run
    end
  end

  context "#target_repository" do
    test "returns the specified target_repository" do
      event = Hook::Event::WorkflowRunEvent.new(run_id: @workflow_run.id, action: "completed")
      assert_equal @repository, event.target_repository
    end
  end

  context "#actor" do
    test "returns the workflow_run creator" do
      event = Hook::Event::WorkflowRunEvent.new(run_id: @workflow_run.id, action: "completed")
      assert_equal @workflow_run.check_suite.creator, event.actor
    end
  end

  context "#deliverable?" do
    test "returns true if the workflow_run & repo exists." do
      event = Hook::Event::WorkflowRunEvent.new(run_id: @workflow_run.id, action: "completed")
      assert event.deliverable?
    end

    test "returns false if the workflow_run does not exist." do
      event = Hook::Event::WorkflowRunEvent.new(run_id: @workflow_run.id + 1000, action: "completed")
      refute event.deliverable?
    end

    test "returns false if the workflow is not active." do
      @workflow.state = "deleted"
      @workflow.save
      event = Hook::Event::WorkflowRunEvent.new(run_id: @workflow_run.id, action: "completed")
      refute event.deliverable?
      @workflow.state = "active"
      @workflow.save!
    end

    test "returns false if the repository does not exist." do
      event = Hook::Event::WorkflowRunEvent.new(run_id: @workflow_run.id, action: "completed")
      event.workflow_run.repository = nil
      refute event.deliverable?
    end
  end

  context "#filterable_for_actions?" do
    test "filterable_for_actions? returns false when the run does not exist" do

      event = Hook::Event::WorkflowRunEvent.new(run_id: @workflow_run.id + 1000, action: "completed")

      refute event.filterable_for_actions?
    end

    test "filterable_for_actions? returns false when the repository does not exist" do
      event = Hook::Event::WorkflowRunEvent.new(run_id: @workflow_run.id, action: "completed")
      event.workflow_run.repository = nil

      refute event.filterable_for_actions?
    end

    test "filterable_for_actions? returns true when the repository exists" do
      event = Hook::Event::WorkflowRunEvent.new(run_id: @workflow_run.id, action: "completed")

      assert event.filterable_for_actions?
    end
  end

  context "#initialize_primary_resource" do
    test "initializes the primary resource data when available" do
      GitHub.flipper[:prehydrate_primary_webhook_data_for_workflow_run].enable

      GitHub::MysqlInstrumenter.reset_stats
      GitHub::MysqlInstrumenter.with_track do
        event = Hook::Event::WorkflowRunEvent.new(run_id: @workflow_run.id, action: "completed", primary_resource_data: @workflow_run.attributes)
        assert_equal @workflow_run, event.instance_variable_get(:@workflow_run)
        GitHub::MysqlInstrumenter.queries.each do |query|
          if ApplicationRecord::RepositoriesActionsChecks == GitHub::MysqlInstrumenter.queries.first.connection_class
            assert query.on_primary
          end
        end
      end

      GitHub::MysqlInstrumenter.reset_stats
      GitHub::MysqlInstrumenter.with_track do
        event = Hook::Event::WorkflowRunEvent.new(run_id: @workflow_run.id, action: "completed")
        assert_nil event.instance_variable_get(:@workflow_run)
        assert_empty GitHub::MysqlInstrumenter.queries.select { |q| q.connection_class == ApplicationRecord::RepositoriesActionsChecks }
      end

      GitHub.flipper[:prehydrate_primary_webhook_data_for_workflow_run].disable
      GitHub::MysqlInstrumenter.reset_stats
      GitHub::MysqlInstrumenter.with_track do
        event = Hook::Event::WorkflowRunEvent.new(run_id: @workflow_run.id, action: "completed", primary_resource_data: @workflow_run.attributes)
        assert_nil event.instance_variable_get(:@workflow_run)
        assert_empty GitHub::MysqlInstrumenter.queries.select { |q| q.connection_class == ApplicationRecord::RepositoriesActionsChecks }
      end
    end
  end

  context "a workflow_file_ref is present" do
    test "it should be deleted and not raise an error" do
      GitHub.flipper[:prehydrate_primary_webhook_data_for_workflow_run].enable
      extra_attributes = { "workflow_file_ref" => "test", :super_fake_attribute => "bad data to break AR!" }
      primary_resource_data = @workflow_run.attributes.merge(extra_attributes)
      event = Hook::Event::WorkflowRunEvent.new(run_id: @workflow_run.id, action: "completed", primary_resource_data: primary_resource_data)
    end
  end

  context "metrics" do
    unless GitHub.enterprise?
      test "instruments prehydration_workflow_run_queries" do
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
        GitHub.flipper["prehydrate_primary_webhook_data_for_workflow_run"].enable
        GitHub.flipper[:webhooks_skip_manual_query_for_check_suite_for_workflow_run].disable
        # accessing event.workflow_run should not increment the query counter because the FF is on and the primary_resource_data is in the payload
        event = Hook::Event::WorkflowRunEvent.new(run_id: @workflow_run.id, action: "completed", primary_resource_data: @workflow_run.attributes)
        _ = event.workflow_run
        mysql_metrics = GitHub.dogstats.distributions("hook.event.prehydration_workflow_run_queries", tags: ["cluster:application_record/repositories_actions_checks"])
        assert_equal 0, mysql_metrics[0].value

        # this should increment the counter because the primary resource is missing
        GitHub.dogstats.reset
        event = Hook::Event::WorkflowRunEvent.new(run_id: @workflow_run.id, action: "completed")
        _ = event.workflow_run
        mysql_metrics = GitHub.dogstats.distributions("hook.event.prehydration_workflow_run_queries", tags: ["cluster:application_record/repositories_actions_checks"])
        refute_empty mysql_metrics
        assert_equal 2, mysql_metrics[0].value

        # this should increment the counter because the FF is off
        GitHub.dogstats.reset
        GitHub.flipper["prehydrate_primary_webhook_data_for_workflow_run"].disable
        event = Hook::Event::WorkflowRunEvent.new(run_id: @workflow_run.id, action: "completed", primary_resource_data: @workflow_run.attributes)
        _ = event.workflow_run
        mysql_metrics = GitHub.dogstats.distributions("hook.event.prehydration_workflow_run_queries", tags: ["cluster:application_record/repositories_actions_checks"])
        refute_empty mysql_metrics
        assert_equal 2, mysql_metrics[0].value
      end

      test "skips manual query to primary database for check_suite" do
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
        GitHub.flipper["prehydrate_primary_webhook_data_for_workflow_run"].enable
        GitHub.flipper[:webhooks_skip_manual_query_for_check_suite_for_workflow_run].enable
        ActiveRecord::Base.expects(:connected_to_many).never
        CheckSuite.expects(:find_by).never
        attrs = @workflow_run.attributes
        event = Hook::Event::WorkflowRunEvent.new(run_id: @workflow_run.id, action: "completed", primary_resource_data: attrs)
      end

      test "executes manual query to primary database for check_suite" do
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
        GitHub.flipper["prehydrate_primary_webhook_data_for_workflow_run"].enable
        GitHub.flipper[:webhooks_skip_manual_query_for_check_suite_for_workflow_run].disable
        CheckSuite.expects(:find_by).once
        attrs = @workflow_run.attributes
        event = Hook::Event::WorkflowRunEvent.new(run_id: @workflow_run.id, action: "completed", primary_resource_data: attrs)
      end
    end
  end
end
