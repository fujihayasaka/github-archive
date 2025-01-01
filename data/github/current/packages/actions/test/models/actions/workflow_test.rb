# typed: false
# frozen_string_literal: true

require "test_helper"

class Actions::WorkflowTest < GitHub::TestCase
  include AuditLog::IntegrationTestHelpers
  include HydroTestHelpers
  include BackgroundDeletesTestHelpers

  fixtures do
    make_trusted_oauth_apps_owner

    @repository = create :repository
    @owner = @repository.owner
    @actions_app = create :launch_integration

    @installation = make_integration_installation integration: @actions_app, target: @owner, permissions: { "actions" => :write }
  end

  setup do
    GitHub.stubs(:actions_enabled?).returns(true)

    example_repo :simple, @repository
    @default_branch = @repository.default_branch
    @default_ref = "refs/heads/#{@repository.default_branch}"
    sha = @repository.refs[@repository.default_branch].commit.oid

    @branch = "branch"
    @branch_ref = "refs/heads/#{@branch}"
    @repository.heads.create(@branch, sha, @owner)
  end

  def create_workflow(branch = @default_branch, workflow_file_path = ".github/workflows/❤️.yml")
    check_suite_name = "Node CI"
    commit = @repository.refs.find(branch).append_commit({ message: "Add a thing", author: @owner }, @owner) do |changes|
      changes.add(workflow_file_path, "name: #{check_suite_name}")
    end

    check_suite = create(:check_suite, github_app: @actions_app, repository: @repository, head_sha: commit.oid, name: check_suite_name, workflow_file_path: workflow_file_path)
    check_suite.workflow_run.workflow
  end

  def commit_workflow(path, content, branch = @default_branch, repository = @repository)
    commit = repository.refs.find(branch).append_commit({ message: "Add workflow", author: repository.owner }, repository.owner) do |changes|
      changes.add(path, content)
    end
  end

  def create_workflow_state_change_hydro_payload(workflow, state, repository, actor)
    {
      workflow_id: workflow.id,
      workflow_file_path: workflow.path,
      workflow_state: state,
      branch_ref: "refs/heads/#{repository.default_branch}",
      installation_id: GitHub.launch_github_app.installations_on(repository.owner)&.with_repository(repository)&.first&.id,
      environment: workflow.lab? ? "lab" : "production",
      actor: Hydro::EntitySerializer.user(actor),
      repository: Hydro::EntitySerializer.repository(repository),
    }
  end

  def create_pinned_workflow_activity_hydro_payload(workflow, event, repository, actor)
    {
      workflow_repository_id: repository.id,
      workflow_id: workflow.id,
      actor_id: actor&.id,
      event: event,
    }
  end

  context "create workflows" do
    test "does not create workflow when file is outside of workflow directory" do
      path = ".github/workflows-not-supported/ci.yaml"
      commit = commit_workflow(path, "name: CI")

      @repository.update_repository_workflows(@default_ref, nil, commit.oid)

      assert_nil Actions::Workflow.find_by(repository: @repository, path: path)
    end

    test "does not create workflow when file is not pushed to default branch" do
      path = ".github/workflows-not-supported/ci.yaml"
      commit = commit_workflow(path, "name: CI", @branch_ref)

      @repository.update_repository_workflows(@branch_ref, nil, commit.oid)

      assert_nil Actions::Workflow.find_by(repository: @repository, path: path)
    end

    test "creates workflow when file is pushed" do
      repository = create :repository, from_example: :simple
      default_branch = repository.default_branch

      path = ".github/workflows/ci.yaml"
      commit = commit_workflow(path, "name: CI", default_branch, repository)

      repository.update_repository_workflows("refs/heads/#{default_branch}", nil, commit.oid)

      workflow = Actions::Workflow.find_by(repository: repository, path: path)
      refute_nil workflow
      assert_equal "CI", workflow.name
      assert_equal "active", workflow.state
      assert workflow.present_in_default_branch
    end

    test "creates workflow with path as name when file is pushed" do
      repository = create :repository, from_example: :simple
      default_branch = repository.default_branch

      path = ".github/workflows/ci.yaml"
      commit = commit_workflow(path, "", default_branch, repository)

      repository.update_repository_workflows("refs/heads/#{default_branch}", nil, commit.oid)

      workflow = Actions::Workflow.find_by(repository: repository, path: path)
      refute_nil workflow
      assert_equal path, workflow.name
      assert_equal "active", workflow.state
      assert workflow.present_in_default_branch
    end

    test "creates lab workflow when file is pushed" do
      repository = create :repository, from_example: :simple
      default_branch = repository.default_branch

      path = ".github/workflows-lab/ci.yaml"
      commit = commit_workflow(path, "", default_branch, repository)

      repository.update_repository_workflows("refs/heads/#{default_branch}", nil, commit.oid)

      workflow = Actions::Workflow.find_by(repository: repository, path: path)
      refute_nil workflow
      assert_equal path, workflow.name
      assert workflow.present_in_default_branch
    end

    test "creates workflows when multiple commits are pushed to an empty repo" do
      new_repo = create :repository, from_example: :empty
      owner = new_repo.owner

      default_ref = new_repo.heads.build(new_repo.default_branch)
      refute_nil default_ref
      first_workflow_path = ".github/workflows/first.yaml"
      first_commit = default_ref.append_commit({ message: "Add first workflow", author: owner }, owner) do |changes|
        changes.add(first_workflow_path, "name: First")
      end

      second_workflow_path = ".github/workflows/second.yaml"
      second_commit = default_ref.append_commit({ message: "Add second workflow", author: owner }, owner) do |changes|
        changes.add(second_workflow_path, "name: Second")
      end

      new_repo.update_repository_workflows(default_ref.qualified_name, GitHub::NULL_OID, second_commit.oid)

      assert_equal 2, new_repo.workflows.count
      first_workflow = Actions::Workflow.find_by(repository: new_repo, path: first_workflow_path)
      refute_nil first_workflow
      assert_equal "First", first_workflow.name
      assert_equal first_workflow_path, first_workflow.path

      second_workflow = Actions::Workflow.find_by(repository: new_repo, path: second_workflow_path)
      refute_nil second_workflow
      assert_equal "Second", second_workflow.name
      assert_equal second_workflow_path, second_workflow.path
    end
  end

  context "update workflows" do
    test "updates workflow when modified file is pushed" do
      workflow = create_workflow
      commit = commit_workflow(workflow.path, "name: New CI")

      @repository.update_repository_workflows(@default_ref, nil, commit.oid)

      assert_equal "New CI", workflow.reload.name
      assert_equal "active", workflow.state
    end

    test "marks deleted workflow as active when modified file is pushed" do
      workflow = create_workflow
      workflow.update!(state: :deleted)
      commit = commit_workflow(workflow.path, "name: New CI")

      @repository.update_repository_workflows(@default_ref, nil, commit.oid)

      assert_equal "active", workflow.reload.state
    end

    if GitHub.hydro_enabled?
      test "publishes github.actions.v0.WorkflowStateChange when state changes for scheduled workflows" do
        workflow = create_workflow
        workflow.stubs(:scheduled?).returns(true)
        workflow.disable(@owner)
        workflow.reload

        assert_hydro_published(create_workflow_state_change_hydro_payload(workflow, "disabled_manually", @repository, nil), schema: "github.actions.v0.WorkflowStateChange")
      end

      test "publishes github.actions.v0.WorkflowStateChange when state changes to active for scheduled workflows" do
        workflow = create_workflow
        workflow.stubs(:scheduled?).returns(true)
        workflow.enable(@owner)
        workflow.reload

        assert_hydro_published(create_workflow_state_change_hydro_payload(workflow, "active", @repository, @repository.owner), schema: "github.actions.v0.WorkflowStateChange")
      end

      test "update does not trigger a hydro event if state does not change" do
        workflow = create_workflow
        workflow.stubs(:scheduled?).returns(true)
        workflow.update!(path: "new path")

        refute_hydro_messages(schema: "github.actions.v0.WorkflowStateChange")
      end

      test "update does not trigger a hydro event if workflow is not scheduled" do
        workflow = create_workflow
        workflow.stubs(:scheduled?).returns(false)
        workflow.update!(state: :deleted)

        refute_hydro_messages(schema: "github.actions.v0.WorkflowStateChange")
      end
    end

    test "keeps disabled workflow as disabled when modified file is pushed" do
      workflow = create_workflow
      workflow.disable(@owner)
      commit = commit_workflow(workflow.path, "name: New CI")

      @repository.update_repository_workflows(@default_ref, nil, commit.oid)

      assert_equal "disabled_manually", workflow.reload.state
    end

    test "updates workflow when modified file without name is pushed" do
      workflow = create_workflow
      commit = commit_workflow(workflow.path, "")

      @repository.update_repository_workflows(@default_ref, nil, commit.oid)

      assert_equal workflow.path, workflow.reload.name
    end

    test "creates new workflow when file is renamed" do
      workflow = create_workflow
      new_path = ".github/workflows/new_path.yml"

      before = @repository.refs.find(@default_branch).target
      after = @repository.refs.find(@default_branch).append_commit({ message: "Rename workflow", author: @owner }, @owner) do |changes|
        content = @repository.blob(before.oid, workflow.path).data
        changes.move(workflow.path, new_path, content)
      end

      assert_nil Actions::Workflow.find_by(repository: @repository, path: new_path)

      @repository.update_repository_workflows(@default_ref, before.oid, after.oid)

      assert_equal "deleted", workflow.reload.state

      new_workflow = Actions::Workflow.find_by(repository: @repository, path: new_path)

      refute_nil new_workflow
      assert_equal "Node CI", new_workflow.reload.name
      assert_equal "active", new_workflow.reload.state
    end

    test "deletes workflow when file is renamed to a path that doesn't match the workflow regex" do
      workflow = create_workflow
      new_path = ".github/workflows/subfolder/❤️.yml"

      before = @repository.refs.find(@default_branch).target
      after = @repository.refs.find(@default_branch).append_commit({ message: "Rename workflow", author: @owner }, @owner) do |changes|
        content = @repository.blob(before.oid, workflow.path).data
        changes.move(workflow.path, new_path, content)
      end

      @repository.update_repository_workflows(@default_ref, before.oid, after.oid)

      assert_equal "deleted", workflow.reload.state

      assert_nil Actions::Workflow.find_by(repository: @repository, path: new_path)
    end

    test "creates new workflow when file is renamed from a path that didn't match the workflow regex" do
      path = ".github/workflows/subfolder/❤️.yml"
      new_path = ".github/workflows/new_path_2.yml"
      content = "name: Node CI"
      commit = commit_workflow(path, content)

      before = @repository.refs.find(@default_branch).target
      after = @repository.refs.find(@default_branch).append_commit({ message: "Rename workflow", author: @owner }, @owner) do |changes|
        content = @repository.blob(before.oid, path).data
        changes.move(path, new_path, content)
      end

      assert_nil Actions::Workflow.find_by(repository: @repository, path: path)
      assert_nil Actions::Workflow.find_by(repository: @repository, path: new_path)

      @repository.update_repository_workflows(@default_ref, before.oid, after.oid)

      new_workflow = Actions::Workflow.find_by(repository: @repository, path: new_path)

      refute_nil new_workflow
      assert_equal "Node CI", new_workflow.reload.name
      assert_equal "active", new_workflow.reload.state
    end

    test "keeps workflow default branch status when pushing to default branch" do
      workflow = create_workflow
      assert workflow.present_in_default_branch

      commit = commit_workflow(workflow.path, "name: Update CI")
      @repository.update_repository_workflows(@default_ref, nil, commit.oid)

      assert workflow.reload.present_in_default_branch
    end

    test "keeps workflow default branch status when pushing to non-default branch" do
      path = ".github/workflows/path_not_in_default.yml"
      workflow = create_workflow(@branch, path)
      refute workflow.present_in_default_branch

      commit = commit_workflow(path, "name: New CI")
      @repository.update_repository_workflows(@branch_ref, nil, commit.oid)

      refute workflow.reload.present_in_default_branch
    end

    test "updates workflow default branch status when file is renamed" do
      workflow = create_workflow
      assert workflow.present_in_default_branch
      new_path = ".github/workflows/new.yml"

      before = @repository.refs.find(@default_branch).target
      after = @repository.refs.find(@default_branch).append_commit({ message: "Rename workflow", author: @owner }, @owner) do |changes|
        content = @repository.blob(before.oid, workflow.path).data
        changes.move(workflow.path, new_path, content)
      end

      @repository.update_repository_workflows(@default_ref, before.oid, after.oid)

      refute workflow.reload.present_in_default_branch

      new_workflow = Actions::Workflow.find_by(repository: @repository, path: new_path)

      refute_nil new_workflow
      assert new_workflow.present_in_default_branch
    end
  end

  context "delete workflows" do
    test "marks a workflow as deleted when the file is deleted on a push" do
      workflow = create_workflow

      before = @repository.refs.find(@default_branch).target
      after = @repository.refs.find(@default_branch).append_commit({ message: "Delete a thing", author: @owner }, @owner) do |changes|
        changes.remove(workflow.path)
      end

      @repository.update_repository_workflows(@default_ref, before.oid, after.oid)

      assert_equal "deleted", workflow.reload.state
      refute workflow.present_in_default_branch
    end

    test "does not mark a workflow as deleted when a file is deleted on a non-default branch" do
      repository = create :repository, from_example: :simple
      default_branch = repository.default_branch

      commit = repository.refs.find(default_branch).append_commit({ message: "Add a workflow file", author: repository.owner }, repository.owner) do |changes|
        changes.add(".github/workflows/delete.yml", "name: Node CI")
      end

      check_suite = create(:check_suite_for_actions_app, repository: repository, head_sha: commit.oid, name: "Node CI", workflow_file_path: ".github/workflows/delete.yml")
      workflow = check_suite.workflow_run.workflow

      new_branch = "new-branch"
      sha = repository.refs[default_branch].commit.oid
      repository.heads.create(new_branch, sha, repository.owner)

      before = repository.refs.find(new_branch).target
      after = repository.refs.find(new_branch).append_commit({ message: "Delete workflow file", author: repository.owner }, repository.owner) do |changes|
        changes.remove(workflow.path)
      end

      repository.update_repository_workflows("refs/heads/#{new_branch}", before.oid, after.oid)

      assert_equal "active", workflow.reload.state
    end

    test "works if no workflow was deleted" do
      workflow = create_workflow

      before = @repository.refs.find(@default_branch).target
      after = @repository.refs.find(@default_branch).append_commit({ message: "Delete a thing", author: @owner }, @owner) do |changes|
        changes.add("README", "hello world")
      end

      @repository.update_repository_workflows(@default_ref, before.oid, after.oid)

      assert_equal "active", workflow.reload.state
    end

    test "treats renames as deletions" do
      workflow = create_workflow

      before = @repository.refs.find(@default_branch).target
      after = @repository.refs.find(@default_branch).append_commit({ message: "Delete a thing", author: @owner }, @owner) do |changes|
        content = @repository.blob(before.oid, workflow.path).data
        changes.move(workflow.path, ".github/workflows/main.yml", content)
      end

      @repository.update_repository_workflows(@default_ref, before.oid, after.oid)

      assert_equal "deleted", workflow.reload.state
    end

    test "updates workflow default branch status when workflow is deleted from default branch " do
      workflow = create_workflow
      assert workflow.present_in_default_branch

      before = @repository.refs.find(@default_branch).target
      after = @repository.refs.find(@default_branch).append_commit({ message: "Delete a thing", author: @owner }, @owner) do |changes|
        changes.remove(workflow.path)
      end

      @repository.update_repository_workflows(@default_ref, before.oid, after.oid)

      refute workflow.reload.present_in_default_branch
    end
  end

  context "#delete_if_no_runs" do
    test "changes state to deleted if no attached runs" do
      workflow = create(:workflow)

      assert_predicate workflow, :active?

      workflow.delete_if_no_runs

      assert_predicate workflow, :deleted?
    end

    test "does nothing if runs remaining" do
      workflow = create_workflow

      assert workflow.workflow_runs.any?
      assert_predicate workflow, :active?

      workflow.delete_if_no_runs

      assert_predicate workflow, :active?
    end

    test "does nothing if is a workflow dispatch" do
      workflow = create(:workflow)
      workflow.stubs(:has_workflow_dispatch_trigger?).returns(true)

      assert_predicate workflow, :active?

      workflow.delete_if_no_runs

      assert_predicate workflow, :active?
    end
  end

  test "#dynamic_dependabot_workflow?" do
    assert Actions::Workflow.new(path: "dynamic/dependabot/slug").dynamic_dependabot_workflow?

    refute Actions::Workflow.new(path: "dynamic-dependabot-slug.yml").dynamic_dependabot_workflow?
    refute Actions::Workflow.new(path: "dynamic/github-actions/debug.yml").dynamic_dependabot_workflow?
    refute Actions::Workflow.new(path: "dynamic/codespaces/slug").dynamic_dependabot_workflow?
  end

  test "#dynamic_codespaces_workflow?" do
    assert Actions::Workflow.new(path: "dynamic/codespaces/slug").dynamic_codespaces_workflow?

    refute Actions::Workflow.new(path: "dynamic-codespaces-slug.yml").dynamic_codespaces_workflow?
    refute Actions::Workflow.new(path: "dynamic/github-actions/debug.yml").dynamic_codespaces_workflow?
    refute Actions::Workflow.new(path: "dynamic/dependabot/slug").dynamic_codespaces_workflow?
  end

  test "#dynamic_codeql_workflow?" do
    assert Actions::Workflow.new(path: "dynamic/codeql/slug").dynamic_codeql_workflow?

    refute Actions::Workflow.new(path: "dynamic-codeql-slug.yml").dynamic_codeql_workflow?
    refute Actions::Workflow.new(path: "dynamic/github-actions/debug.yml").dynamic_codeql_workflow?
    refute Actions::Workflow.new(path: "dynamic/dependabot/slug").dynamic_codeql_workflow?
  end

  test "#dynamic_pages_workflow?" do
    assert Actions::Workflow.new(path: "dynamic/pages/pages-build-deployment").dynamic_pages_workflow?

    refute Actions::Workflow.new(path: "dynamic/codeql/slug").dynamic_pages_workflow?
    refute Actions::Workflow.new(path: "dynamic-codeql-slug.yml").dynamic_pages_workflow?
    refute Actions::Workflow.new(path: "dynamic/github-actions/debug.yml").dynamic_pages_workflow?
    refute Actions::Workflow.new(path: "dynamic/dependabot/slug").dynamic_pages_workflow?
  end

  test "#dynamic_actions_workflow?" do
    assert Actions::Workflow.new(path: "dynamic/github-actions/debug.yml").dynamic_actions_workflow?
    assert Actions::Workflow.new(path: "dynamic/github-actions-lab/debug.yml").dynamic_actions_workflow?

    refute Actions::Workflow.new(path: ".github/workflows/push.yml").dynamic_actions_workflow?
    refute Actions::Workflow.new(path: "dynamic/dependabot/slug").dynamic_actions_workflow?
    refute Actions::Workflow.new(path: "dynamic/codespaces/slug").dynamic_actions_workflow?
  end

  test "disabled?" do
    assert Actions::Workflow.new(state: "disabled_fork", path: ".github/workflows/main.yml").disabled?
    assert Actions::Workflow.new(state: "disabled_inactivity", path: ".github/workflows/main.yml").disabled?
    assert Actions::Workflow.new(state: "disabled_manually", path: ".github/workflows/main.yml").disabled?

    refute Actions::Workflow.new(state: "active", path: ".github/workflows/main.yml").disabled?
    refute Actions::Workflow.new(state: "deleted", path: ".github/workflows/main.yml").disabled?

    refute Actions::Workflow.new(state: "disabled_fork", path: "dynamic/codespaces/slug").disabled?
    refute Actions::Workflow.new(state: "disabled_inactivity", path: "dynamic/codespaces/slug").disabled?
    refute Actions::Workflow.new(state: "disabled_manually", path: "dynamic/codespaces/slug").disabled?
  end

  test "disableable?" do
    assert Actions::Workflow.new(path: ".github/workflows/main.yml").disableable?
    refute Actions::Workflow.new(path: "dynamic/codespaces/slug").disableable?
    refute Actions::Workflow.new(path: ".github/workflows/required_ci.yml", imposer_repository_id: 10).disableable?
  end

  test "enable" do
    workflow = create_workflow
    workflow.update(state: "disabled_manually")

    events = assert_performed_audit_entries(count: 1, only: "workflows.enable_workflow") do
      workflow.enable(@repository.owner)
    end

    expected_payload = {
      action: "workflows.enable_workflow",
      actor: @repository.owner.login,
      repo: @repository.nwo,
      workflow_id: workflow.id,
      operation_type: "modify"
    }

    assert_subset_hash expected_payload, events.first
    workflow.reload
    assert workflow.enabled_at
    refute workflow.disabled_at
    refute_hydro_messages(schema: "github.actions.v0.WorkflowStateChange")
  end

  test "enable a scheduled workflow" do
    workflow = create_workflow
    workflow.update(state: "disabled_inactivity")
    workflow.stubs(:scheduled?).returns(true)

    events = assert_performed_audit_entries(count: 1, only: "workflows.enable_workflow") do
      workflow.enable(@repository.owner)
    end

    expected_payload = {
      action: "workflows.enable_workflow",
      actor: @repository.owner.login,
      repo: @repository.nwo,
      workflow_id: workflow.id,
      operation_type: "modify"
    }

    assert_subset_hash expected_payload, events.first
    workflow.reload
    assert workflow.enabled_at
    refute workflow.disabled_at

    assert_hydro_published(create_workflow_state_change_hydro_payload(workflow, "active", @repository, @repository.owner), schema: "github.actions.v0.WorkflowStateChange")
  end

  test "enable a workflow that is active" do
    workflow = create_workflow
    refute workflow.enabled_at

    workflow.enable(@repository.owner)

    assert_equal "active", workflow.state
    assert workflow.enabled_at
  end

  test "enable a workflow that is active but will be disabled soon" do
    workflow = create_workflow
    workflow.stubs(:churning?).returns(true)
    refute workflow.enabled_at

    workflow.enable(@repository.owner)

    assert_equal "active", workflow.state
    assert workflow.enabled_at
  end

  test "enable a workflow of a repository owned by business" do
    @repository.transfer_ownership_to(create(:organization, business: create(:business)), actor: @repository.owner)
    @owner = @repository.owner
    workflow = create_workflow
    workflow.update(state: "disabled_manually")

    events = assert_performed_audit_entries(count: 1, only: "workflows.enable_workflow") do
      workflow.enable(@repository.owner)
    end

    expected_payload = {
      action: "workflows.enable_workflow",
      actor: @repository.owner.login,
      repo: @repository.nwo,
      workflow_id: workflow.id,
      operation_type: "modify",
      org: @repository.organization.login,
      org_id: @repository.organization.id,
      business: @repository.business.name,
      business_id: @repository.business.id,
    }

    assert_subset_hash expected_payload, events.first
    workflow.reload
    assert workflow.enabled_at
    refute workflow.disabled_at
  end

  context "#disable" do
    test "sends an audit entry and disables the workflow" do
      workflow = create_workflow

      events = assert_performed_audit_entries(count: 1, only: "workflows.disable_workflow") do
        workflow.disable(@repository.owner)
      end

      expected_payload = {
        action: "workflows.disable_workflow",
        actor: @repository.owner.login,
        repo: @repository.nwo,
        workflow_id: workflow.id,
        operation_type: "modify"
      }

      assert_subset_hash expected_payload, events.first
      workflow.reload
      refute workflow.enabled_at
      assert workflow.disabled_at
      refute_hydro_messages(schema: "github.actions.v0.WorkflowStateChange")
    end

    test "publishes a state change to Hydro for scheduled workflows" do
      Actions::Workflow.any_instance.stubs(:scheduled?).returns(true)
      GitHub.stubs(:enterprise?).returns(true) # rubocop:todo GitHub/DontStubEnterpriseInTests

      workflow = create_workflow
      workflow.stubs(:scheduled?).returns(true)

      events = assert_performed_audit_entries(count: 1, only: "workflows.disable_workflow") do
        workflow.disable(@repository.owner)
      end

      expected_payload = {
        action: "workflows.disable_workflow",
        actor: @repository.owner.login,
        repo: @repository.nwo,
        workflow_id: workflow.id,
        operation_type: "modify"
      }

      assert_subset_hash expected_payload, events.first
      workflow.reload
      refute workflow.enabled_at
      assert workflow.disabled_at
      assert_hydro_published(create_workflow_state_change_hydro_payload(workflow, "disabled_manually", @repository, nil), schema: "github.actions.v0.WorkflowStateChange")
    end

    test "sends an audit log for a workflow in a repository owned by business" do
      @repository.transfer_ownership_to(create(:organization, business: create(:business)), actor: @repository.owner)
      @owner = @repository.owner
      workflow = create_workflow

      events = assert_performed_audit_entries(count: 1, only: "workflows.disable_workflow") do
        workflow.disable(@repository.owner)
      end

      expected_payload = {
        action: "workflows.disable_workflow",
        actor: @repository.owner.login,
        repo: @repository.nwo,
        workflow_id: workflow.id,
        operation_type: "modify",
        org: @repository.organization.login,
        org_id: @repository.organization.id,
        business: @repository.business.name,
        business_id: @repository.business.id,
      }

      assert_subset_hash expected_payload, events.first
      workflow.reload
      refute workflow.enabled_at
      assert workflow.disabled_at
    end

    test "raises an error for inactive workflows" do
      workflow = create_workflow
      workflow.update!(state: :disabled_manually)

      assert_raises Actions::Workflow::NotActiveError do
        workflow.disable(@repository.owner)
      end
    end

    test "raises an error for workflows that can't be disabled" do
      dynamic_workflow = Actions::Workflow.create_or_update_workflow(
        "dynamic/dependabot/dependabot-workflow",
        "Dependabot Workflow",
        @repository, nil, "dynamic",
      )

      assert_raises Actions::Workflow::CannotBeDisabledError do
        dynamic_workflow.disable(@repository.owner)
      end
    end
  end

  context "create or update" do
    test "marks a workflow as disabled for inactivity if the event is schedule and the repository is public" do
      GitHub.stubs(:enterprise?).returns(false) # rubocop:todo GitHub/DontStubEnterpriseInTests
      [true, false].each do |public_repo|
        Actions::Workflow.any_instance.stubs(:scheduled?).returns(true)
        repository = Timecop.travel((Actions::Workflow::REPOSITORY_INACTIVITY_THRESHOLD + 1).days.ago) do
          create :repository, public: public_repo
        end

        workflow = Actions::Workflow.create_or_update_workflow(".github/workflows/main.yml", "Node CI", repository, nil, "schedule")

        if public_repo
          assert_equal "disabled_inactivity", workflow.state
          assert_hydro_published(create_workflow_state_change_hydro_payload(workflow, "disabled_inactivity", repository, nil), schema: "github.actions.v0.WorkflowStateChange")
        else
          assert_equal "active", workflow.state
          refute_hydro_messages(schema: "github.actions.v0.WorkflowStateChange")
        end

        reset_hydro
      end
    end

    test "marks a workflow as disabled for inactivity if the event is schedule and the repository has become inactive again after re-enabling the workflow" do
      Actions::Workflow.any_instance.stubs(:scheduled?).returns(true)
      GitHub.stubs(:enterprise?).returns(false) # rubocop:todo GitHub/DontStubEnterpriseInTests

      threshold = Actions::Workflow::REPOSITORY_INACTIVITY_THRESHOLD
      name = "Node CI"
      workflow_file_path = ".github/workflows/main.yml"
      # We create an old repo
      repository = Timecop.travel((threshold * 2 + 1).days.ago) do
        create(:public_repository)
      end

      # After the threshold, the workflow is marked as disabled
      workflow = Actions::Workflow.create_or_update_workflow(workflow_file_path, name, repository, nil, "schedule")
      assert_equal "disabled_inactivity", workflow.state
      assert_hydro_published(create_workflow_state_change_hydro_payload(workflow, "disabled_inactivity", repository, nil), schema: "github.actions.v0.WorkflowStateChange")
      reset_hydro

      Timecop.travel((threshold + 1).days.ago) do
        # Marking it as enabled in the past. This will set workflow.enabled_at
        workflow.enable(repository.owner)
        assert workflow.enabled_at

        # Triggering it again, in the past, but within the threshold because it will use workflow.enabled_at, keeps it active
        Actions::Workflow.create_or_update_workflow(workflow_file_path, name, repository, nil, "schedule")
        assert_equal "active", workflow.reload.state
        assert_hydro_published(create_workflow_state_change_hydro_payload(workflow, "active", repository, repository.owner), schema: "github.actions.v0.WorkflowStateChange")
        reset_hydro
      end

      # Triggering it again in the present disables it because enabled_at and pushed_at are both outside the threshold
      Actions::Workflow.create_or_update_workflow(workflow_file_path, name, repository, nil, "schedule")
      assert_equal "disabled_inactivity", workflow.reload.state
      assert_hydro_published(create_workflow_state_change_hydro_payload(workflow, "disabled_inactivity", repository, nil), schema: "github.actions.v0.WorkflowStateChange")
    end

    test "enterprise scheduled workflow remains active even after inactivity threshold" do
      Actions::Workflow.any_instance.stubs(:scheduled?).returns(true)
      GitHub.stubs(:enterprise?).returns(true) # rubocop:todo GitHub/DontStubEnterpriseInTests

      threshold = Actions::Workflow::REPOSITORY_INACTIVITY_THRESHOLD
      name = "Node CI"
      workflow_file_path = ".github/workflows/main.yml"
      # Create an old repo
      repository = Timecop.travel((threshold * 2 + 1).days.ago) do
        create(:public_repository)
      end

      # After the threshold, the workflow is not marked as disabled
      workflow = Actions::Workflow.create_or_update_workflow(workflow_file_path, name, repository, nil, "schedule")
      assert_equal "active", workflow.state
      assert_equal 0, hydro_message_count(schema: "github.actions.v0.WorkflowStateChange")
    end

    test "worklows latest_timestamp is updated if there is a push event to the repository so workflows are not disabled" do
      Actions::Workflow.any_instance.stubs(:scheduled?).returns(true)
      threshold = Actions::Workflow::REPOSITORY_INACTIVITY_THRESHOLD
      name = "Node CI"
      workflow_file_path = ".github/workflows/main.yml"

      # the repository threshold is currently set to 60 days, so this creates a run 120 days ago
      repository, workflow = Timecop.travel((threshold * 2).days.ago) do
        repository = create(:public_repository, from_example: :simple)
        commit = repository.refs.find("master").append_commit({ message: "Add a thing", author: repository.owner }, repository.owner)
        workflow = Actions::Workflow.create_or_update_workflow(workflow_file_path, name, repository, nil, "schedule")
        assert_equal "active", workflow.state
        assert workflow.latest_timestamp > threshold.days.ago
        [repository, workflow]

        # push a commit to the repository before the inactivity threshold has been hit, 61 days ago
        Timecop.travel((threshold + 1).days.ago) do
          commit = repository.commits.create({ message: "Add file", author: repository.owner }) do |files|
            files.add "file1.txt", "content"
          end
          repository.refs["master"].update(commit, repository.owner)
        end

        # because of the earlier commit, the latest_timestamp should be newer than the inactivity threshold
        Timecop.travel((2).days.ago) do
          repository.reload
          workflow.reload
          assert workflow.latest_timestamp > threshold.days.ago
        end
      end
    end

    test "marks a dynamically run workflow as active when it is created" do
      @dependabot_app = create(:dependabot_integration)

      workflow = Actions::Workflow.create_or_update_workflow("dynamic/#{@dependabot_app.slug}/dependabot-workflow", "Dependabot Workflow", @repository, nil, "dynamic")

      assert_equal "active", workflow.state
    end

    test "present_in_default_branch stays true during an update when no value is passed in" do
      workflow = create_workflow
      assert workflow.present_in_default_branch

      Actions::Workflow.create_or_update_workflow(workflow.path, workflow.name, workflow.repository, nil)

      assert workflow.reload.present_in_default_branch
    end

    test "present_in_default_branch stays false during an update when no value is passed in" do
      path = ".github/workflows/path_not_in_default.yml"
      workflow = create_workflow(@branch, path)
      refute workflow.present_in_default_branch

      Actions::Workflow.create_or_update_workflow(workflow.path, workflow.name, workflow.repository, nil)

      refute workflow.reload.present_in_default_branch
    end

    test "create a workflow entity representing a required workflow enforced from an org" do
      path = "required/workflow.yml"
      imposer_repo = create(:repository, owner: @owner)
      Actions::Workflow.create_or_update_workflow("required/workflow.yml", "Awesome required workflow", @repository, nil, imposer_repository_id: imposer_repo.id)

      workflow = Actions::Workflow.where(repository_id: @repository.id, path: "required/workflow.yml", imposer_repository_id: imposer_repo.id).first
      assert_equal imposer_repo.id, workflow.imposer_repository_id
      assert_equal "active", workflow.state
    end

    test "don't populate imposer repository id for workflows other than required workflows" do
      path = ".github/workflows/workflow.yml"
      Actions::Workflow.create_or_update_workflow(".github/workflows/workflow.yml", "Awesome simple workflow", @repository, nil)

      workflows = Actions::Workflow.where(repository_id: @repository.id, path: path)
      assert_equal 1, workflows.count
      assert_equal "Awesome simple workflow", workflows.first.name
    end

    test "create a normal workflow and required workflow entity in the same repository with the same path and check if there are no conflicts" do
      imposer_repo = create(:repository, owner: @owner)
      required_workflow_path = ".github/workflow/test.yml"
      Actions::Workflow.create_or_update_workflow(required_workflow_path, "Awesome required workflow", @repository, nil, imposer_repository_id: imposer_repo.id)

      normal_workflow_path = ".github/workflow/test.yml"
      normal_workflow = create_workflow(@branch, normal_workflow_path)

      workflows = Actions::Workflow.where(repository_id: @repository.id, path: normal_workflow.path)
      assert_equal 2, workflows.count

      workflows = Actions::Workflow.where(repository_id: @repository.id, path: normal_workflow.path, imposer_repository_id: 0)
      assert_equal 1, workflows.count

      workflows = Actions::Workflow.where(repository_id: @repository.id, path: normal_workflow.path, imposer_repository_id: imposer_repo.id)
      assert_equal 1, workflows.count
    end

    test "present_in_default_branch updated when false passed in" do
      workflow = create_workflow
      assert workflow.present_in_default_branch

      Actions::Workflow.create_or_update_workflow(workflow.path, workflow.name, workflow.repository, nil, present_in_default_branch: false)

      refute workflow.reload.present_in_default_branch
    end

    test "present_in_default_branch updated when true passed in" do
      path = ".github/workflows/path_not_in_default.yml"
      workflow = create_workflow(@branch, path)
      refute workflow.present_in_default_branch

      Actions::Workflow.create_or_update_workflow(workflow.path, workflow.name, workflow.repository, nil, present_in_default_branch: true)

      assert workflow.reload.present_in_default_branch
    end
  end

  test "does not send warning or disabled emails for private or non-scheduled workflows" do
    threshold = Actions::Workflow::REPOSITORY_INACTIVITY_THRESHOLD
    name = "Node CI"
    workflow_file_path = ".github/workflows/main.yml"
    # old, private repository
    private_repository = Timecop.travel((threshold + 1).days.ago) do
      create(:private_repository)
    end
    perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
      Actions::Workflow.create_or_update_workflow(workflow_file_path, name, private_repository, nil, "schedule")
    end

    #old, public repo with non-sheduled workflow
    public_repository = Timecop.travel((threshold + 1).days.ago) do
      create(:public_repository)
    end
    perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
      Actions::Workflow.create_or_update_workflow(workflow_file_path, name, public_repository, nil)
    end
    assert_equal 0, ActionMailer::Base.deliveries.count
    refute_hydro_messages(schema: "github.actions.v0.WorkflowStateChange")
  end

  test "does not send any emails before window" do
    name = "Node CI"
    workflow_file_path = ".github/workflows/main.yml"
    # We create an old repo
    repository = Timecop.travel(1.day.ago) do
      create(:public_repository)
    end

    perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
      Actions::Workflow.create_or_update_workflow(workflow_file_path, name, repository, nil, "schedule")
      Actions::Workflow.create_or_update_workflow(workflow_file_path, name, repository, nil, "schedule")
      Actions::Workflow.create_or_update_workflow(workflow_file_path, name, repository, nil, "schedule")
    end
    assert_equal 0, ActionMailer::Base.deliveries.count
    refute_hydro_messages(schema: "github.actions.v0.WorkflowStateChange")
  end

  test "sends 1 warning email during window" do
    GitHub.stubs(:enterprise?).returns(false) # rubocop:todo GitHub/DontStubEnterpriseInTests

    threshold = Actions::Workflow::REPOSITORY_INACTIVITY_THRESHOLD
    window = Actions::Workflow::INACTIVITY_WARNING_WINDOW
    repo_age = threshold - window + 1
    name = "Node CI"
    workflow_file_path = ".github/workflows/main.yml"
    # We create an old repo
    repository = Timecop.travel(repo_age.days.ago) do
      create(:public_repository)
    end

    workflow = perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
      Actions::Workflow.create_or_update_workflow(workflow_file_path, name, repository, nil, "schedule")
      Actions::Workflow.create_or_update_workflow(workflow_file_path, name, repository, nil, "schedule")
      Actions::Workflow.create_or_update_workflow(workflow_file_path, name, repository, nil, "schedule")
    end

    # Validate that we persist the fact that a warning was sent
    kv_key = ["inactive-workflow-warning", repository.id, workflow.id].compact.join("-")
    assert Actions::KV.for_partition_key(repository.id).exists(kv_key).value { false }

    assert_equal 1, ActionMailer::Base.deliveries.count
    assert ActionMailer::Base.deliveries[0].Subject.value.include? "will be disabled"
    ActionMailer::Base.deliveries.clear
  end

  test "sends 1 disabled email after window" do
    GitHub.stubs(:enterprise?).returns(false) # rubocop:todo GitHub/DontStubEnterpriseInTests

    Timecop.freeze(Time.new(2024, 3, 5, 0, 8, 0).utc) do
      threshold = Actions::Workflow::REPOSITORY_INACTIVITY_THRESHOLD
      window = Actions::Workflow::INACTIVITY_WARNING_WINDOW
      repo_age = 2 * threshold
      name = "Node CI"
      workflow_file_path = ".github/workflows/main.yml"
      # We create an old repo
      repository = Timecop.travel(repo_age.days.ago) do
        create(:public_repository)
      end

      workflow = perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
        Actions::Workflow.create_or_update_workflow(workflow_file_path, name, repository, nil, "schedule")
        Actions::Workflow.create_or_update_workflow(workflow_file_path, name, repository, nil, "schedule")
        Actions::Workflow.create_or_update_workflow(workflow_file_path, name, repository, nil, "schedule")
      end

      assert_equal 1, ActionMailer::Base.deliveries.count
      assert ActionMailer::Base.deliveries[0].Subject.value.include? "has been disabled"
      assert_hydro_published(create_workflow_state_change_hydro_payload(workflow, "disabled_inactivity", repository, nil), schema: "github.actions.v0.WorkflowStateChange")
    end
  end

  test "sends no disabled email after window when enterprise" do
    GitHub.stubs(:enterprise?).returns(true) # rubocop:todo GitHub/DontStubEnterpriseInTests
    Actions::Workflow.any_instance.stubs(:scheduled?).returns(true)

    threshold = Actions::Workflow::REPOSITORY_INACTIVITY_THRESHOLD
    window = Actions::Workflow::INACTIVITY_WARNING_WINDOW
    repo_age = 2 * threshold
    name = "Node CI"
    workflow_file_path = ".github/workflows/main.yml"
    # We create an old repo
    repository = Timecop.travel(repo_age.days.ago) do
      create(:public_repository)
    end

    workflow = perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
      Actions::Workflow.create_or_update_workflow(workflow_file_path, name, repository, nil, "schedule")
      Actions::Workflow.create_or_update_workflow(workflow_file_path, name, repository, nil, "schedule")
      Actions::Workflow.create_or_update_workflow(workflow_file_path, name, repository, nil, "schedule")
    end

    puts ActionMailer::Base.deliveries
    assert_equal 0, ActionMailer::Base.deliveries.count
    assert_equal 0, hydro_message_count(schema: "github.actions.v0.WorkflowStateChange")
  end

  test "warning email sent during inactivity window and a disabled email is sent after the window" do
    Timecop.freeze(Time.new(2024, 3, 5, 0, 8, 0).utc) do
      Actions::Workflow.any_instance.stubs(:scheduled?).returns(true)
      GitHub.stubs(:enterprise?).returns(false) # rubocop:todo GitHub/DontStubEnterpriseInTests

      threshold = Actions::Workflow::REPOSITORY_INACTIVITY_THRESHOLD
      name = "Node CI"
      workflow_file_path = ".github/workflows/main.yml"
      # We create an old repo
      repository = Timecop.travel((2 * threshold).days.ago) do
        create(:public_repository)
      end

      # The first scheduled workflow is triggered in the window, before the threshold is reached
      Timecop.travel((threshold + 1).days.ago) do
        workflow = perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
          Actions::Workflow.create_or_update_workflow(workflow_file_path, name, repository, nil, "schedule")
        end

        # Validate that we persist the fact that a warning was sent
        kv_key = ["inactive-workflow-warning", repository.id, workflow.id].compact.join("-")
        assert Actions::KV.for_partition_key(repository.id).exists(kv_key).value { false }
      end

      assert_equal 1, ActionMailer::Base.deliveries.count
      assert ActionMailer::Base.deliveries[0].Subject.value.include? "will be disabled"
      ActionMailer::Base.deliveries.clear
      refute_hydro_messages(schema: "github.actions.v0.WorkflowStateChange")

      # The second scheduled workflow is triggered after the threshold is reached, there should only be a disabled email sent if enable_fair_use is enabled
      workflow = perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
        Actions::Workflow.create_or_update_workflow(workflow_file_path, name, repository, nil, "schedule")
      end

      assert_equal 1, ActionMailer::Base.deliveries.count
      assert ActionMailer::Base.deliveries[0].Subject.value.include? "has been disabled"
      assert_hydro_published(create_workflow_state_change_hydro_payload(workflow, "disabled_inactivity", repository, nil), schema: "github.actions.v0.WorkflowStateChange")
    end
  end

  test "sends warning email for each expiring workflow" do
    GitHub.stubs(:enterprise?).returns(false) # rubocop:todo GitHub/DontStubEnterpriseInTests

    threshold = Actions::Workflow::REPOSITORY_INACTIVITY_THRESHOLD
    window = Actions::Workflow::INACTIVITY_WARNING_WINDOW
    repo_age = threshold - window + 1
    name = "Node CI"
    workflow_file_path = ".github/workflows/main.yml"
    # We create an old repo
    repository = Timecop.travel(repo_age.days.ago) do
      create(:public_repository)
    end

    workflow1 = nil
    workflow2 = nil
    perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
      workflow1 = Actions::Workflow.create_or_update_workflow(workflow_file_path, name, repository, nil, "schedule")
      workflow2 = Actions::Workflow.create_or_update_workflow(workflow_file_path + "_2", name + "_2", repository, nil, "schedule")
    end

    # Validate that we persist the fact that a warning was sent
    kv_key1 = ["inactive-workflow-warning", repository.id, workflow1.id].compact.join("-")
    assert Actions::KV.for_partition_key(repository.id).exists(kv_key1).value { false }
    kv_key2 = ["inactive-workflow-warning", repository.id, workflow2.id].compact.join("-")
    assert Actions::KV.for_partition_key(repository.id).exists(kv_key1).value { false }

    assert_equal 2, ActionMailer::Base.deliveries.count
    assert ActionMailer::Base.deliveries[0].Subject.value.include? "will be disabled"
    assert ActionMailer::Base.deliveries[1].Subject.value.include? "will be disabled"
    refute_hydro_messages(schema: "github.actions.v0.WorkflowStateChange")
  end

  test "sends disabled email for each expiring scheduled workflow" do
    Timecop.freeze(Time.new(2024, 3, 5, 0, 8, 0).utc) do
      Actions::Workflow.any_instance.stubs(:scheduled?).returns(true)
      GitHub.stubs(:enterprise?).returns(false) # rubocop:todo GitHub/DontStubEnterpriseInTests

      threshold = Actions::Workflow::REPOSITORY_INACTIVITY_THRESHOLD
      window = Actions::Workflow::INACTIVITY_WARNING_WINDOW
      repo_age = threshold * 2
      name = "Node CI"
      workflow_file_path = ".github/workflows/main.yml"
      # We create an old repo
      repository = Timecop.travel(repo_age.days.ago) do
        create(:public_repository)
      end

      workflows = []

      perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
        workflows.push(Actions::Workflow.create_or_update_workflow(workflow_file_path, name, repository, nil, "schedule"))
        workflows.push(Actions::Workflow.create_or_update_workflow(workflow_file_path + "_2", name + "_2", repository, nil, "schedule"))
      end

      assert_equal 2, ActionMailer::Base.deliveries.count
      assert ActionMailer::Base.deliveries[0].Subject.value.include? "has been disabled"
      assert ActionMailer::Base.deliveries[1].Subject.value.include? "has been disabled"
      assert_hydro_published(create_workflow_state_change_hydro_payload(workflows[0], "disabled_inactivity", repository, nil), schema: "github.actions.v0.WorkflowStateChange")
      assert_hydro_published(create_workflow_state_change_hydro_payload(workflows[1], "disabled_inactivity", repository, nil), schema: "github.actions.v0.WorkflowStateChange")
    end
  end

  test "valid required workflow paths with metadata" do
    [
      ["required/1234/required_workflows/abc.yml", true],
      ["required/12432412535/.github/workflows/abc.yml", true],
      ["required/1/abc.yml", true],
      [".github/workflows/abc.yml", false],
      ["required CI", false],
      ["required/workflow/name", false],
      ["required/workflows/name.yml", false],
      ["required/.github/workflows/name.yml", false],
      ["required/1workflows/name.yml", false],
      ["required/213213/21workflows/name.yml", true],
      ["required/213213/21/workflows/name.yml", true],
      [".required/workflows/test.yml", false],
      ["anotherrequired/1234/required_workflows/abc.yml", false],
      ["1234/abc.yml", false],
      ["abc.yml", false],
      ["1234", false],
      ["dynamic/abc.yml", false],
    ].each do |path, expected_result|
      assert_equal expected_result, Actions::Workflow::REQUIRED_WORKFLOWS_PATH_METADATA_REGEX.match?(path)
    end
  end

  context "#filename" do
    test "returns filename as expected for dynamic workflows" do
      assert_equal "codespaces/prebuild.yml", Actions::Workflow.new(path: "dynamic/codespaces/prebuild.yml").filename
    end

    test "returns filename as expected for normal workflows" do
      assert_equal "sample.yml", Actions::Workflow.new(path: ".github/workflows/sample.yml").filename
    end

    test "returns filename as expected for required workflows" do
      source_repo = create(:repository, owner: @owner)

      assert_equal "required/#{source_repo.nwo}/.github/workflows/required.yml", Actions::Workflow.new(path: ".github/workflows/required.yml", repository_id: @repository.id, imposer_repository_id: source_repo.id).filename
    end
  end

  context "#find_from_filename" do
    test "returns required workflow entity based on filename" do
      source_repo = create(:repository, owner: @owner)
      req_workflow = Actions::Workflow.new(name: "Required CI", path: ".github/workflows/required.yml", repository_id: @repository.id, imposer_repository_id: source_repo.id)
      req_workflow.save

      normal_workflow = Actions::Workflow.new(name: "Normal CI", path: ".github/workflows/required.yml", repository_id: @repository.id)
      normal_workflow.save

      assert_equal "Required CI", Actions::Workflow.find_from_filename("required/#{source_repo.nwo}/#{req_workflow.path}").name
    end

    test "returns non required workflow entity based on filename" do
      source_repo = create(:repository, owner: @owner)
      req_workflow = Actions::Workflow.new(name: "Required CI", path: ".github/workflows/required.yml", repository_id: @repository.id, imposer_repository_id: source_repo.id)
      req_workflow.save

      normal_workflow = Actions::Workflow.new(name: "Normal CI", path: ".github/workflows/required.yml", repository_id: @repository.id)
      normal_workflow.save

      assert_equal "Normal CI", Actions::Workflow.find_from_filename("#{normal_workflow.path}").name
    end
  end

  context "#parsed_workflow" do
    test "parse a required workflow and test for workflow_dispatch_trigger" do
      source_repo = create(:repository, owner: @owner)
      ref = source_repo.heads.read(source_repo.default_branch)

      path = ".github/workflows/required.yml"
      ref.append_commit({ message: "Add workflow", author: source_repo.owner }, source_repo.owner) do |files|
        files.add(path, "on: workflow_dispatch")
      end

      req_workflow = Actions::Workflow.new(name: "Required CI", path: path, repository_id: @repository.id, imposer_repository_id: source_repo.id)
      req_workflow.save

      req_workflow_parsed = req_workflow.parsed_workflow
      assert req_workflow_parsed.has_workflow_dispatch_trigger?
    end
  end

  context "#extract_dynamic_workflowfile_path" do
    test "parse workflow file path and check for good dynamic workflow path" do
      is_dynamic, integration, slug  = Actions::Workflow.extract_dynamic_workflowfile_path("dynamic/codespaces/prebuild.yml")
      assert is_dynamic
      assert_equal "codespaces", integration
      assert_equal "prebuild.yml", slug
    end

    test "check for an giberish sent over to try and extract the dynamic workflow path" do
      is_dynamic, integration, slug  = Actions::Workflow.extract_dynamic_workflowfile_path("UYTDJSGHJADJHAGDJGbhagshdjgahjsd")
      assert_not is_dynamic
      assert_nil integration
      assert_nil slug
    end

    test "check for a workflow path that is not of type dynamic" do
      is_dynamic, integration, slug  = Actions::Workflow.extract_dynamic_workflowfile_path(".github/workflows/sample.yml")
      assert_not is_dynamic
      assert_nil integration
      assert_nil slug
    end

    test "check for a nil workflow path" do
      is_dynamic, integration, slug  = Actions::Workflow.extract_dynamic_workflowfile_path(nil)
      assert_not is_dynamic
      assert_nil integration
      assert_nil slug
    end
  end

  test "parse a required workflow with push trigger and test for workflow_dispatch_trigger" do
    source_repo = create(:repository, owner: @owner)
    ref = source_repo.heads.read(source_repo.default_branch)

    path = ".github/workflows/required.yml"
    ref.append_commit({ message: "Add workflow", author: source_repo.owner }, source_repo.owner) do |files|
      files.add(path, "on: push")
    end

    req_workflow = Actions::Workflow.new(name: "Required CI", path: path, repository_id: @repository.id, imposer_repository_id: source_repo.id)
    req_workflow.save

    req_workflow_parsed = req_workflow.parsed_workflow
    refute req_workflow_parsed.has_workflow_dispatch_trigger?
  end

  test "parse a normal workflow and test for workflow_dispatch_trigger" do
    ref = @repository.heads.read(@repository.default_branch)

    path = ".github/workflows/ci.yml"
    ref.append_commit({ message: "Add workflow", author: @repository.owner }, @repository.owner) do |files|
      files.add(path, "on: workflow_dispatch")
    end

    workflow = Actions::Workflow.new(name: "CI", path: path, repository_id: @repository.id)
    workflow.save

    workflow_parsed = workflow.parsed_workflow
    assert workflow_parsed.has_workflow_dispatch_trigger?
  end

  context "#permalink" do
    test "handles basic filenames" do
      workflow = create(:workflow, repository: @repository, path: ".github/workflows/ci.yml")
      expected = "#{@repository.permalink(include_host: true)}/actions/workflows/#{workflow.filename}"

      assert_equal expected, workflow.permalink
    end

    test "excludes host" do
      workflow = create(:workflow, repository: @repository, path: ".github/workflows/ci.yml")
      expected = "#{@repository.permalink(include_host: false)}/actions/workflows/#{workflow.filename}"

      assert_equal expected, workflow.permalink(include_host: false)
    end

    test "handles workflow labs" do
      workflow = create(:workflow, repository: @repository, path: ".github/workflows-lab/ci.yml")
      expected = "#{@repository.permalink(include_host: false)}/actions/workflows/#{workflow.filename}?lab=true"

      assert_equal expected, workflow.permalink(include_host: false)
    end

    test "escapes filename for URL" do
      workflow = create(:workflow, repository: @repository, path: ".github/workflows/@##@$*()@)!jijoi.c.yaml")
      expected = "#{@repository.permalink(include_host: false)}/actions/workflows/@%23%23@$*()@)!jijoi.c.yaml"

      assert_equal expected, workflow.permalink(include_host: false)
    end
  end

  context "#pinned_workflow" do
    test "pin and unpin a workflow" do
      workflow = create(:workflow, repository: @repository, path: ".github/workflows/ci.yml")
      refute workflow.is_pinned?
      refute workflow.pinned_workflow.present?

      events = assert_performed_audit_entries(count: 1, only: "workflows.pin_workflow") do
        workflow.pin(@owner)
      end
      workflow.reload
      assert workflow.is_pinned?
      assert workflow.pinned_workflow.present?
      assert_hydro_published(create_pinned_workflow_activity_hydro_payload(workflow, :PINNED, @repository, @owner), schema: "github.actions.v0.PinnedWorkflowsActivity")

      events = assert_performed_audit_entries(count: 1, only: "workflows.unpin_workflow") do
        workflow.unpin(@owner)
      end
      workflow.reload
      refute workflow.is_pinned?
      refute workflow.pinned_workflow.present?
      assert_hydro_published(create_pinned_workflow_activity_hydro_payload(workflow, :UNPINNED, @repository, @owner), schema: "github.actions.v0.PinnedWorkflowsActivity")
    end

    test "unpins workflow if state changed to inactive" do
      workflow = create(:workflow, repository: @repository, path: ".github/workflows/ci.yml")
      refute workflow.is_pinned?
      refute workflow.pinned_workflow.present?

      events = assert_performed_audit_entries(count: 1, only: "workflows.pin_workflow") do
        workflow.pin(@owner)
      end
      workflow.reload
      assert workflow.is_pinned?
      assert workflow.pinned_workflow.present?
      assert_hydro_published(create_pinned_workflow_activity_hydro_payload(workflow, :PINNED, @repository, @owner), schema: "github.actions.v0.PinnedWorkflowsActivity")

      events = assert_performed_audit_entries(count: 0) do
        workflow.state = "disabled_fork"
        workflow.save!
      end

      workflow.reload
      refute workflow.is_pinned?
      refute workflow.pinned_workflow.present?
      assert_hydro_published(create_pinned_workflow_activity_hydro_payload(workflow, :UNPINNED, @repository, nil), schema: "github.actions.v0.PinnedWorkflowsActivity")
    end

    test "disable states unpin workflow" do
      %w(deleted disabled_fork disabled_inactivity disabled_manually).each do |inactive_state|
        workflow = create(:workflow, repository: @repository, path: ".github/workflows/ci-#{inactive_state}.yml")
        refute workflow.is_pinned?
        refute workflow.pinned_workflow.present?

        events = assert_performed_audit_entries(count: 1, only: "workflows.pin_workflow") do
          workflow.pin(@owner)
        end
        workflow.reload
        assert workflow.is_pinned?
        assert workflow.pinned_workflow.present?
        assert_hydro_published(create_pinned_workflow_activity_hydro_payload(workflow, :PINNED, @repository, @owner), schema: "github.actions.v0.PinnedWorkflowsActivity")

        events = assert_performed_audit_entries(count: 0) do
          workflow.state = inactive_state
          workflow.save!
        end

        workflow.reload
        refute workflow.is_pinned?
        refute workflow.pinned_workflow.present?
        assert_hydro_published(create_pinned_workflow_activity_hydro_payload(workflow, :UNPINNED, @repository, nil), schema: "github.actions.v0.PinnedWorkflowsActivity")
      end
    end
  end

  context "#pin" do
    test "raises error if already pinned" do
      workflow = create(:workflow, repository: @repository)
      workflow.pin(@owner)

      assert_raises Actions::Workflow::AlreadyPinnedError do
        workflow.reload.pin(@owner)
      end
    end

    test "raises error if already max pinned workflows already pinned" do
      Actions::PinnedWorkflow.stub_const(:MAXIMUM_PINNED_WORKFLOWS, 1) do
        workflow = create(:workflow, repository: @repository)
        workflow.pin(@owner)
        workflow2 = create(:workflow, repository: @repository)
        assert_raises Actions::Workflow::MaxPinnedWorkflowsReachedError do
          workflow2.pin(@owner)
        end
      end
    end

    test "raises error if workflow is not active" do
      workflow = create(:workflow, repository: @repository, state: "disabled_manually")
      assert_raises Actions::Workflow::CannotPinInactiveWorkflowError do
        workflow.pin(@owner)
      end

      workflow.update(state: "deleted")
      assert_raises Actions::Workflow::CannotPinInactiveWorkflowError do
        workflow.reload.pin(@owner)
      end
    end

    test "raises error if user does not have permission to pin" do
      workflow = create(:workflow, repository: @repository)

      # no user
      assert_raises Actions::Workflow::UserCannotPinWorkflowError do
        workflow.pin(nil)
      end

      # user without write access
      user = create(:user)
      assert_raises Actions::Workflow::UserCannotPinWorkflowError do
        workflow.pin(user)
      end
    end
  end

  context "#unpin" do
    test "raises error if not pinned" do
      workflow = create(:workflow, repository: @repository)

      assert_raises Actions::Workflow::AlreadyUnpinnedError do
        workflow.unpin(@owner)
      end
    end

    test "raises error if user does not have permission to unpin" do
      workflow = create(:workflow, repository: @repository)
      workflow.pin(@owner)
      workflow.reload

      # no user
      assert_raises Actions::Workflow::UserCannotPinWorkflowError do
        workflow.unpin(nil)
      end

      # user without write access
      user = create(:user)
      assert_raises Actions::Workflow::UserCannotPinWorkflowError do
        workflow.unpin(user)
      end
    end
  end

  test "is deleted with repository" do
    workflow = Actions::Workflow.create_or_update_workflow(".github/workflows/main.yml", "Node CI", @repository, nil, "schedule")
    other_repository = create :repository
    other_workflow = Actions::Workflow.create_or_update_workflow(".github/workflows/main.yml", "Node CI", other_repository, nil, "schedule")

    assert_destroyed_in_background_with_parent do |config|
      config.parent_record = @repository
      config.expect_destroyed = [workflow]
      config.expect_not_destroyed = [other_workflow]
    end
  end
end
