# typed: true
# frozen_string_literal: true

require "test_helper"

module Reachability
  class ActionsWorkflowTest < GitHub::TestCase
    include GitHub::UserTestHelpers

    ActionResultMock = Struct.new(:call_succeeded?, :status, :options, :value)
    WorkflowMock = Struct.new(:workflow_run_id)
    DUMMY_WORKFLOW_CONTENT = <<~WORKFLOW
name: test workflow
on: dynamic
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - run: echo "hello world"
WORKFLOW

    fixtures do
      @github_org = github_org
      @repo1 = create(:public_repository, owner: @github_org, from_example: :simple)

      @repo1.default_branch_ref.append_commit({ message: "blah", committer: @github_org.admin }, @github_org.admin) do |files|
        files.add("filename.yml", DUMMY_WORKFLOW_CONTENT)
      end

      workflow_file_path = File.join(File.dirname(__FILE__), "../../../app/models/reachability/workflow.yml")
      @actual_workflow_file_contents = File.read(workflow_file_path)
    end

    context "dotcom", skip_enterprise: true do
      context "#create_workflow_run" do
        test "raises exception when the inputs are too large" do
          long_job_id = "x" * MYSQL_TEXT_FIELD_LIMIT

          assert_raises(ActionsWorkflow::InputsTooLarge) do
            ActionsWorkflow.create_workflow_run(
              actor: @github_org.admin,
              repo: @repo1,
              sha: @repo1.default_branch_ref.commit.oid,
              job_id: long_job_id
            )
          end
        end

        test "raises exception when no result from Actions" do
          Repository.any_instance.expects(:run_dynamic_workflow)
            .once
            .returns(nil)

          assert_raises(ActionsWorkflow::UnableToLaunch) do
            create_workflow_run
          end
        end

        test "raises exception when result from Actions fails with 422" do
          mock_actions_result = ActionResultMock.new(
            call_succeeded?: false,
            status: 422,
            options: {
              message: "something was invalid"
            }
          )
          Repository.any_instance.expects(:run_dynamic_workflow)
            .once
            .returns(mock_actions_result)

          assert_raises(ActionsWorkflow::UnableToLaunch) do
            create_workflow_run
          end
        end

        test "raises exception when result from Actions fails with with internal error" do
          mock_actions_result = ActionResultMock.new(
            call_succeeded?: false,
            status: 500
          )
          Repository.any_instance.expects(:run_dynamic_workflow)
            .once
            .returns(mock_actions_result)

          assert_raises(ActionsWorkflow::UnableToLaunch) do
            create_workflow_run
          end
        end

        test "creates a workflow run" do
          mock_workflow_run_id = 100
          mock_actions_result = ActionResultMock.new(
            call_succeeded?: true,
            value: WorkflowMock.new(
              workflow_run_id: mock_workflow_run_id
            )
          )

          Repository.any_instance.expects(:run_dynamic_workflow)
            .with(has_entries({
              actor: @github_org.admin,
              ref: @repo1.default_branch_ref.commit.oid,
              workflow_name: "Reachability Analysis",
              slug: "reachability",
              integration_name: "github-advanced-security",
              inputs: has_entries({
                job_id: 1234,
              })
            }))
            .once
            .returns(mock_actions_result)

          workflow_run_id = create_workflow_run

          assert_equal mock_workflow_run_id, workflow_run_id
        end
      end

      context "#dynamic_workflow_yaml" do
        test "reads workflow from disk" do
          workflow_content = ActionsWorkflow.dynamic_workflow_yaml
          assert_equal workflow_content, @actual_workflow_file_contents
        end
      end
    end

    def create_workflow_run
      ActionsWorkflow.create_workflow_run(
        actor: @github_org.admin,
        repo: @repo1,
        sha: @repo1.default_branch_ref.commit.oid,
        job_id: 1234
      )
    end
  end
end
