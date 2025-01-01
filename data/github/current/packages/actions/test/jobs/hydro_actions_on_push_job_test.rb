# typed: true
# frozen_string_literal: true

require "test_helper"

class HydroActionsOnPushJobTest < GitHub::TestCase
  include HydroMessageJobTestHelpers
  include PushTestHelper

  fixtures do
    @owner = create :user
    @repo = create :repository, owner: @owner, from_example: :post_receive_job_test

    example_repo_snapshot

    @action_metadata_content = {
      "name" => "Cache",
      "description" => "Cache artifacts like dependencies and build outputs to improve workflow execution time",
      "branding" => {
        "icon" => "archive",
        "color" => "gray-dark",
      },
    }.to_yaml
  end

  setup do
    example_repo_restore

    GitHub.stubs(:actions_enabled?).returns(true)
  end

  def push_file(path:, content: , ref:, large_push: false)
    commit_data = {
      message: "Push file",
      committer: @owner,
    }

    commit = ref.append_commit(commit_data, @owner) do |files|
      files.add(path, content)
    end

    large_push_threshold = large_push ? 0 : Pushes::CommitsHelper::LARGE_PUSH_THRESHOLD

    Pushes::CommitsHelper.stub_const(:LARGE_PUSH_THRESHOLD, large_push_threshold) do
      message = {
        repository_id: @repo.id,
        ref_updates: [{ ref: ref.qualified_name, before: GitHub::NULL_OID, after: commit.oid }],
        pushed_at: 1.minute.ago,
        pusher: @owner.login,
      }
      perform_hydro_message_job(message, schema: "github.repositories.v1.Pushed", queue: "hydro_actions_on_push")
    end
  end

  context "Workflows" do
    test "Creates Actions workflows when pushing to the default branch" do
      workflow_path = ".github/workflows/ci.yaml"

      push_file(path: workflow_path, content: "name: CI", ref: @repo.default_branch_ref)

      refute_nil Actions::Workflow.find_by(repository: @repo, path: workflow_path)
    end

    test "Does not create Actions workflows when pushing to other branches" do
      workflow_path = ".github/workflows/ci.yaml"
      topic_ref = @repo.refs.find("topic")

      push_file(path: workflow_path, content: "name: CI", ref: topic_ref)

      assert_nil Actions::Workflow.find_by(repository: @repo, path: workflow_path)
    end

    test "Refreshes Actions workflows for large pushes" do
      # Workflow does not exist in the repository and should be deleted by refresh_workflows
      workflow_to_delete = @repo.workflows.create!(name: "Blank", path: ".github/workflows/blank.yaml", present_in_default_branch: true)

      workflow_path = ".github/workflows/ci.yaml"

      push_file(path: workflow_path, content: "name: CI", ref: @repo.default_branch_ref, large_push: true)

      refute_nil Actions::Workflow.find_by(repository: @repo, path: workflow_path)

      workflow_to_delete.reload
      assert_predicate workflow_to_delete, :deleted?
    end

    test "Does not refresh Actions workflows for small pushes" do
      # Workflow does not exist in the repository and would be deleted by refresh_workflows
      workflow_to_delete = @repo.workflows.create!(name: "Blank", path: ".github/workflows/blank.yaml", present_in_default_branch: true)

      workflow_path = ".github/workflows/ci.yaml"

      push_file(path: workflow_path, content: "name: CI", ref: @repo.default_branch_ref, large_push: false)

      refute_nil Actions::Workflow.find_by(repository: @repo, path: workflow_path)

      workflow_to_delete.reload
      refute_predicate workflow_to_delete, :deleted?
    end

    test "refreshing Actions workflows keeps manually disabled workflows disabled" do
      # workflow exists in repository and is manually disabled
      workflow = create(:workflow, repository: @repo, name: "Node CI", state: "disabled_manually")
      @repo.default_branch_ref.append_commit({ committer: @repo.owner, message: "Updating a file" }, @owner) do |files|
        files.add(workflow.path, "name: Node CI\non: push")
      end
      refute_nil @repo.workflows.find_by(name: "Node CI")

      push_file(path: ".github/workflows/some_other_file.yaml", content: "name: CI", ref: @repo.default_branch_ref, large_push: true)

      persisted_workflow = @repo.workflows.find_by(name: "Node CI")
      assert persisted_workflow
      assert_equal "disabled_manually", persisted_workflow.state
    end
  end

  context "Repository actions" do
    test "Creates repository actions for the default branch" do
      assert_equal 0, @repo.actions.count

      push_file(path: "action.yaml", content: @action_metadata_content, ref: @repo.default_branch_ref)

      assert_equal 1, @repo.actions.count

      action = @repo.actions.first
      assert_equal action.path, "action.yaml"
      assert_equal action.name, "Cache"
      assert_equal action.description, "Cache artifacts like dependencies and build outputs to improve workflow execution time"
      assert_equal action.icon_name, "archive"
      assert_equal action.color, RepositoryActions::Colors.select_by_name_or_hex("gray-dark")[:color_hex]
    end

    test "Does not create repository actions for other branches" do
      assert_equal 0, @repo.actions.count

      topic_ref = @repo.refs.find("topic")

      push_file(path: "action.yaml", content: @action_metadata_content, ref: topic_ref)

      assert_equal 0, @repo.actions.count
    end
  end

  test "does not update Actions workflows on delete" do
    ref = @repo.default_branch_ref
    commit = ref.append_commit({ message: "Push file", committer: @owner }, @owner) do |files|
      files.add("foo", "dsfdsfsdfsd")
    end

    message = {
      repository_id: @repo.id,
      ref_updates: [{ ref: ref.qualified_name, before: commit.oid, after: GitHub::NULL_OID }],
      pushed_at: 1.minute.ago,
      pusher: @owner.login,
    }

    Repository.any_instance.expects(:update_repository_workflows).never

    perform_hydro_message_job(message, schema: "github.repositories.v1.Pushed", queue: "hydro_actions_on_push")
  end

  test "skips updates for non default branch" do
    Repository.any_instance.expects(:update_repository_workflows).never
    Repository.any_instance.expects(:update_repository_actions).never

    message = {
      repository_id: @repo.id,
      ref_updates: [{ ref: "refs/heads/foo", before: SecureRandom.hex(20), after: SecureRandom.hex(20) }],
      pushed_at: 1.minute.ago,
      pusher: @owner.login,
    }

    perform_hydro_message_job(message, schema: "github.repositories.v1.Pushed", queue: "hydro_actions_on_push")
  end
end
