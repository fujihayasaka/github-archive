# typed: true
# frozen_string_literal: true
require "test_helper"

module VariantAnalysis
  class ActionsWorkflowHelperTest < GitHub::TestCase
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
      @controller_repo = create(:repository)
      @language = "ruby"
      @variant_analysis = create(:codeql_variant_analysis, controller_repo: @controller_repo)
      @instructions_url = "https://example.com/instructions.json"
      @repo_count = 10

      @owner = create(:user)
      @actions_ref_user = create(:user)

      @repo1 = create(:repository, owner: @owner)
      @repo2 = create(:repository, owner: @owner)

      @github_org = github_org
      @action_repo = create(:public_repository,
        id: VariantAnalysis::ActionsWorkflowHelper::CODEQL_VARIANT_ANALYSIS_ACTION_REPO_ID,
        name: "codeql-variant-analysis-action",
        owner: @github_org,
        from_example: :simple)

      @action_repo.heads.create("main", @action_repo.default_branch_ref.commit.oid, @action_repo.owner)

      @ref_with_workflow = "ref-with-workflow"
      @action_repo.heads.create(@ref_with_workflow, @action_repo.default_branch_ref.target, @action_repo.owner)
      @action_repo.heads.find(@ref_with_workflow).append_commit({ message: "blah", committer: @github_org.admin }, @github_org.admin) do |files|
        files.add(VariantAnalysis::ActionsWorkflowHelper::WORKFLOW_FILE_PATH, DUMMY_WORKFLOW_CONTENT)
      end

      @ref_without_workflow = "ref-without-workflow"
      @action_repo.heads.create(@ref_without_workflow, @action_repo.default_branch_ref.target, @action_repo.owner)

      workflow_file_path = File.join(File.dirname(__FILE__), "../../../app/helpers/variant_analysis/workflow.yml")
      @actual_workflow_file_contents = File.read(workflow_file_path)
      @default_workflow_contents = @actual_workflow_file_contents.gsub("CODEQL_VARIANT_ANALYSIS_ACTION_REF", "main")
    end

    setup do
      @helper = FakeHelper.new.extend(ActionsWorkflowHelper)
      GitHub.flipper[:mrva_allow_non_default_action_ref].enable(@actions_ref_user)
    end

    context "dotcom", skip_enterprise: true do
      context "#create_workflow_run" do
        test "raises exception when the inputs are too large" do
          long_instructions_url = "x" * MYSQL_TEXT_FIELD_LIMIT

          assert_raises(ActionsWorkflowHelper::InputsTooLarge) do
            @helper.create_workflow_run(
              variant_analysis: @variant_analysis,
              instructions_url: long_instructions_url,
              action_repo_ref: "main",
              repo_count: @repo_count
            )
          end
        end

        test "raises exception when no result from Actions" do
          Repository.any_instance.expects(:run_dynamic_workflow)
            .once
            .returns(nil)

          assert_raises(ActionsWorkflowHelper::UnableToLaunch) do
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

          assert_raises(ActionsWorkflowHelper::UnableToLaunch) do
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

          assert_raises(ActionsWorkflowHelper::UnableToLaunch) do
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
              actor: @variant_analysis.actor,
              ref: @controller_repo.default_branch,
              workflow_name: "CodeQL query",
              slug: "queries",
              integration_name: "codeql",
              inputs: has_entries({
                query_pack_url: regexp_matches(/\Ahttps:\/\/.*\/#{Regexp.quote(@variant_analysis.query_pack_path)}.*/),
                action_repo_ref: "main",
                signed_auth_token: regexp_matches(/.+/),
              })
            }))
            .once
            .returns(mock_actions_result)

          workflow_run_id = create_workflow_run

          assert_equal mock_workflow_run_id, workflow_run_id
        end

        test "creates a workflow run when different action_repo_ref is specified" do
          mock_workflow_run_id = 100
          mock_actions_result = ActionResultMock.new(
            call_succeeded?: true,
            value: WorkflowMock.new(
              workflow_run_id: mock_workflow_run_id
            )
          )

          Repository.any_instance.expects(:run_dynamic_workflow)
            .with(has_entries({
              actor: @variant_analysis.actor,
              ref: @controller_repo.default_branch,
              workflow_name: "CodeQL query",
              slug: "queries",
              integration_name: "codeql",
              inputs: has_entries({
                query_pack_url: regexp_matches(/\Ahttps:\/\/.*\/#{Regexp.quote(@variant_analysis.query_pack_path)}.*/),
                action_repo_ref: @ref_with_workflow,
              })
            }))
            .once
            .returns(mock_actions_result)

          workflow_run_id = create_workflow_run(@ref_with_workflow)

          assert_equal mock_workflow_run_id, workflow_run_id
        end
      end

      context "#check_for_valid_ref" do
        test "has no effect if ref is 'main'" do
          assert_nil @helper.check_for_valid_ref(action_repo_ref: "main", user: @owner)
          assert_nil @helper.check_for_valid_ref(action_repo_ref: "main", user: @actions_ref_user)
        end

        context "when user is not opted into feature flag" do
          test "raises exception if ref is not 'main'" do
            assert_raises(ActionsWorkflowHelper::InvalidActionRepoRef) do
              @helper.check_for_valid_ref(action_repo_ref: "branch", user: @owner)
            end
          end

          test "has no effect if ref is main" do
            assert_nil @helper.check_for_valid_ref(action_repo_ref: "main", user: @owner)
          end
        end

        context "when user is opted into feature flag" do
          test "raises exception is ref doesn't exist" do
            assert_raises(ActionsWorkflowHelper::InvalidActionRepoRef) do
              @helper.check_for_valid_ref(action_repo_ref: "this-branch-does-not-exist", user: @actions_ref_user)
            end
          end

          test "has no effect if ref exists" do
            assert_nil @helper.check_for_valid_ref(action_repo_ref: @ref_with_workflow, user: @actions_ref_user)
          end
        end
      end

      context "#create_repo_nwo_chunks" do
        test "does not split if only a small number of repos" do
          repo_nwos = Array.new(10, "owner/repo")
          chunks = @helper.create_repo_nwo_chunks(@variant_analysis, repo_nwos)

          assert_equal chunks.length, 10
        end

        test "splits into 100 chunks" do
          repo_nwos = Array.new(1000, "owner/repo")
          chunks = @helper.create_repo_nwo_chunks(@variant_analysis, repo_nwos)

          assert_equal chunks.length, 100
        end
      end

      context "#dynamic_workflow_yaml" do
        test "returns default workflow in the default case" do
          workflow_content = @helper.dynamic_workflow_yaml("main", @actions_ref_user)
          assert_equal workflow_content, @default_workflow_contents
        end

        test "returns default workflow when user is not allowed to use non-default refs" do
          GitHub.flipper[:mrva_allow_non_default_action_ref].disable(@actions_ref_user)
          workflow_content = @helper.dynamic_workflow_yaml(@ref_with_workflow, @actions_ref_user)
          assert_equal workflow_content, @default_workflow_contents
        end

        test "returns default workflow when user is allowed but is using main" do
          GitHub.flipper[:mrva_allow_non_default_action_ref].enable(@actions_ref_user)
          workflow_content = @helper.dynamic_workflow_yaml("main", @actions_ref_user)
          assert_equal workflow_content, @default_workflow_contents
        end

        test "reads workflow from repo when user is allowed and is not using main and file exists" do
          GitHub.flipper[:mrva_allow_non_default_action_ref].enable(@actions_ref_user)
          workflow_content = @helper.dynamic_workflow_yaml(@ref_with_workflow, @actions_ref_user)
          assert_equal workflow_content, DUMMY_WORKFLOW_CONTENT
        end

        test "reads workflow from disk and substitutes ref when user is allowed but ref does not contain workflow" do
          GitHub.flipper[:mrva_allow_non_default_action_ref].enable(@actions_ref_user)
          workflow_content = @helper.dynamic_workflow_yaml(@ref_without_workflow, @actions_ref_user)
          assert_equal workflow_content, @actual_workflow_file_contents.gsub("CODEQL_VARIANT_ANALYSIS_ACTION_REF", @action_repo.heads.find(@ref_without_workflow).target.oid)
        end

        test "throws InvalidActionRepoRef when ref does not exist" do
          GitHub.flipper[:mrva_allow_non_default_action_ref].enable(@actions_ref_user)

          assert_raises VariantAnalysis::ActionsWorkflowHelper::InvalidActionRepoRef do
            @helper.dynamic_workflow_yaml("unknown", @actions_ref_user)
          end
        end
      end
    end

    def create_workflow_run(ref = "main")
      @helper.create_workflow_run(
        variant_analysis: @variant_analysis,
        instructions_url: @instructions_url,
        action_repo_ref: ref,
        repo_count: @repo_count
      )
    end
  end
end
