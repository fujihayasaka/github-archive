# typed: false
# frozen_string_literal: true

require "test_helper"

class ActionWorkflowFilesTest < GitHub::TestCase

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    make_trusted_oauth_apps_owner

    @repo = create :repository, from_example: :simple

    example_repo_snapshot

    @commit_metadata = { committer: @repo.owner, message: "Updating a file" }

    @lab_app = create(:integration, default_permissions: { "metadata" => :read })

    @check_suite = create(:check_suite_for_actions_app, repository: @repo)
    @lab_check_suite = create(:check_suite_for_actions_app, repository: @repo, github_app: @lab_app)

    create(:check_suite, repository: @repo) # make sure we are not querying check suites from another app
  end

  setup do
    GitHub.stubs(:launch_lab_github_app).returns(@lab_app)
    GitHub.stubs(:actions_enabled?).returns(true)
    example_repo_restore
    reset_cache
  end

  context "#actions_check_suites" do
    test "returns only check suites for prod github actions app" do
      disable_feature_flag(:launch_lab, @repo)

      assert_same_elements [@check_suite], @repo.actions_check_suites
    end

    test "returns also lab check suites when feature flag enabled" do
      enable_feature_flag(:launch_lab, @repo)

      assert_same_elements [@check_suite, @lab_check_suite], @repo.actions_check_suites
    end
  end

  context "#workflow_file_present?" do
    test "returns false if no .github folder" do
      @repo.heads.find_or_build("no-github-folder-branch")
      refute @repo.workflow_file_present?("no-github-folder-branch")
    end

    test "returns false if branch doesn't exist" do
      refute @repo.workflow_file_present?("definitely-not-a-real-branch")
    end

    test "returns false if no yml files in .github/workflows" do
      ref = @repo.heads.find_or_build("no-yml-files-branch")

      ref.append_commit(@commit_metadata, @repo.owner) do |files|
        files.add(".github/workflows/mike.md", "i am file")
      end

      refute @repo.workflow_file_present?("no-yml-files-branch")
    end

    test "returns true if there is a yml files in .github/workflows" do
      %w[yml yaml].each do |extension|
        ref = @repo.heads.find_or_build("workflow-files-branch")

        ref.append_commit(@commit_metadata, @repo.owner) do |files|
          files.add(".github/workflows/mike.#{extension}", "i am file")
        end

        assert @repo.workflow_file_present?("workflow-files-branch")
      end
    end

    test "returns true if there is a yml files in .github/workflows-lab" do
      %w[yml yaml].each do |extension|
        ref = @repo.heads.find_or_build("workflow-lab-files-branch")

        ref.append_commit(@commit_metadata, @repo.owner) do |files|
          files.add(".github/workflows-lab/mike.#{extension}", "i am file")
        end

        assert @repo.workflow_file_present?("workflow-lab-files-branch")
      end
    end
  end

  context "#persist_existing_workflows" do
    test "creates workflow records for files in .github/workflows" do
      ref = @repo.heads.find("master")

      ref.append_commit(@commit_metadata, @repo.owner) do |files|
        files.add(".github/workflows/main.yml", "name: Node CI\non: push")
      end

      persisted_workflows = @repo.persist_existing_workflows

      workflow = @repo.workflows.find_by(name: "Node CI")
      assert workflow
      assert_equal "active", workflow.state
      assert workflow.present_in_default_branch
      assert_equal 1, persisted_workflows.size
      assert_equal workflow, persisted_workflows.first
    end

    test "creates disabled workflow in a forked repository for files in .github/workflows with a schedule on them" do
      ref = @repo.heads.find("master")

      ref.append_commit(@commit_metadata, @repo.owner) do |files|
        files.add(".github/workflows/main.yml", "name: Node CI\non: schedule")
      end

      fork_owner = create(:user)
      fork_repo = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @repo.fork(forker: fork_owner) }.first

      [true, false].each do |public_repo|
        fork_repo.update(public: public_repo)
        persisted_workflows = fork_repo.persist_existing_workflows(disable_scheduled_workflows_on_fork: true)

        workflow = fork_repo.workflows.find_by(name: "Node CI")
        assert workflow
        assert_equal 1, persisted_workflows.size
        assert_equal workflow, persisted_workflows.first
        if public_repo
          assert_equal "disabled_fork", workflow.state
        else
          assert_equal "active", workflow.state
        end
      end
    end
  end

  context "#refresh_workflows" do
    test "creates workflow when pushing to default branch" do
      ref = @repo.heads.read("master")
      path = ".github/workflows/ci.yaml"
      ref.append_commit({ message: "Create workflow", author: @repo.owner }, @repo.owner) do |files|
        files.add(path, "name: CI")
      end

      @repo.refresh_workflows

      workflow = Actions::Workflow.find_by(repository: @repo, path: path)
      refute_nil workflow
      assert_equal "active", workflow.state
      assert workflow.present_in_default_branch
    end

    test "does not create workflow when pushing to non-default branch" do
      branch_ref = @repo.heads.find_or_build("branch")

      path = ".github/workflows/ci.yaml"
      branch_ref.append_commit({ message: "Create workflow", author: @repo.owner }, @repo.owner) do |files|
        files.add(path, "name: CI")
      end

      @repo.refresh_workflows

      workflow = Actions::Workflow.find_by(repository: @repo, path: path)
      assert_nil workflow
    end

    test "deletes and creates new workflow when workflow file is renamed" do
      old_path = ".github/workflows/ci.yaml"
      new_path = ".github/workflows/new-ci.yaml"
      ref = @repo.heads.read("master")

      ref.append_commit(@commit_metadata, @repo.owner) do |files|
        files.add(old_path, "name: CI")
      end

      old_workflow = @repo.persist_existing_workflows.first
      refute_nil old_workflow
      assert_equal "active", old_workflow.state

      ref.append_commit({ message: "Move workflow", author: @repo.owner }, @repo.owner) do |files|
        files.move(old_path, new_path, "name: CI")
      end

      @repo.refresh_workflows

      assert_equal "deleted", old_workflow.reload.state
      refute old_workflow.present_in_default_branch

      new_workflow = Actions::Workflow.find_by(repository: @repo, path: new_path)
      refute_nil new_workflow
      assert_equal "active", new_workflow.state
      assert new_workflow.present_in_default_branch
    end

    test "deletes workflow when workflow file is deleted" do
      path = ".github/workflows/ci.yaml"
      ref = @repo.heads.read("master")

      ref.append_commit({ message: "Create workflow", author: @repo.owner }, @repo.owner) do |files|
        files.add(path, "name: CI")
      end

      workflow = @repo.persist_existing_workflows.first
      refute_nil workflow
      assert_equal "active", workflow.state

      ref.append_commit({ message: "Delete workflow", author: @repo.owner }, @repo.owner) do |files|
        files.remove(path)
      end

      @repo.refresh_workflows

      assert_equal "deleted", workflow.reload.state
      refute workflow.present_in_default_branch
    end

    test "does not create workflow when workflow file create and deleted in same push" do
      path = ".github/workflows/ci.yaml"
      ref = @repo.heads.read("master")

      ref.append_commit({ message: "Create workflow", author: @repo.owner }, @repo.owner) do |files|
        files.add(path, "name: CI")
      end

      ref.append_commit({ message: "Delete workflow", author: @repo.owner }, @repo.owner) do |files|
        files.remove(path)
      end

      @repo.refresh_workflows

      assert_nil Actions::Workflow.find_by(repository: @repo, path: path)

    end

    test "manually disabled workflows in default branch stay disabled" do
      workflow = create(:workflow, repository: @repo, name: "Node CI", state: "disabled_manually")
      ref = @repo.heads.find("master")

      ref.append_commit(@commit_metadata, @repo.owner) do |files|
        files.add(workflow.path, "name: Node CI\non: push")
      end

      @repo.refresh_workflows

      persisted_workflow = @repo.workflows.find_by(name: "Node CI")
      assert persisted_workflow
      assert_equal "disabled_manually", persisted_workflow.state
    end
  end

  context "#workflow_hash" do
    test "handles a missing name by putting the path in the badge_url" do
      workflow = create(:workflow, repository: @repo, name: "")
      result = Api::Serializer.serialize(:workflow_hash, workflow)

      assert_match /.*#{@repo.nwo}\/workflows\/#{workflow.path}\/badge.svg/, result[:badge_url]
    end

    test "handles a newline in the workflow name" do
      workflow = create(:workflow, repository: @repo, name: "something with\na line break\n")
      result = Api::Serializer.serialize(:workflow_hash, workflow)

      safe_name = Addressable::URI.encode_component(workflow.url_safe_name, Addressable::URI::CharacterClasses::PATH)

      assert_match /.*#{@repo.nwo}\/workflows\/#{safe_name}\/badge.svg/, result[:badge_url]
    end

    test "handles dynamic workflows using by_file method" do
      workflow = create(:workflow, repository: @repo, path: "dynamic/pages/pages-build-deployment")
      result = Api::Serializer.serialize(:workflow_hash, workflow)
      assert_match /.*\/actions\/workflows\/pages\/pages-build-deployment\/badge.svg/, result[:badge_url]
      # dynamic workflows don't have a link to a `/blob` path
      refute_match /blob/, result[:html_url]
    end
  end

  context "#workflow_triggers" do
    test "returns an empty array if there is no workflows folder" do
      refute @repo.includes_directory? Actions::Workflow::WORKFLOWS_PATH
      assert_equal Set[], @repo.send(:workflow_triggers, @repo.default_branch_ref.target_oid, Actions::Workflow::WORKFLOWS_PATH)
    end

    test "are parsed out of workflow files on the default branch" do
      assert_equal "master", @repo.default_branch
      ref = @repo.heads.find("master")

      ref.append_commit(@commit_metadata, @repo.owner) do |files|
        files.add(".github/workflows/1.yml", "name: Test\non: [status, check_run]")
        files.add(".github/workflows/2.yml", "name: Test\non: [status, issues]")
      end

      assert_equal Set["check_run", "issues", "status"], @repo.send(:workflow_triggers, @repo.default_branch_ref.target_oid, Actions::Workflow::WORKFLOWS_PATH)
    end

    test "are parsed out of lab workflow files on the default branch" do
      assert_equal "master", @repo.default_branch
      ref = @repo.heads.find("master")

      ref.append_commit(@commit_metadata, @repo.owner) do |files|
        files.add(".github/workflows-lab/1.yml", "name: Test\non: [status, check_run]")
        files.add(".github/workflows-lab/2.yml", "name: Test\non: [status, issues]")
        files.add(".github/workflows/1.yml", "name: Test\non: [status, pull_request_target, gollum]") # Not a lab workflow
      end

      assert_equal Set["check_run", "issues", "status"], @repo.send(:workflow_triggers, @repo.default_branch_ref.target_oid, Actions::Workflow::WORKFLOWS_LAB_PATH, lab: true)
    end

    test "are not parsed out of workflow files on the non default branch" do
      assert_equal "master", @repo.default_branch

      ref = @repo.heads.find_or_build("workflow-files-branch")

      ref.append_commit(@commit_metadata, @repo.owner) do |files|
        files.add(".github/workflows/1.yml", "name: Test\non: [status, check_run]")
        files.add(".github/workflows/2.yml", "name: Test\non: [status, issues]")
      end

      assert_equal Set[], @repo.send(:workflow_triggers, @repo.default_branch_ref.target_oid, Actions::Workflow::WORKFLOWS_PATH)
    end

    test "only returns default branch events" do
      assert_equal "master", @repo.default_branch
      ref = @repo.heads.find("master")

      ref.append_commit(@commit_metadata, @repo.owner) do |files|
        files.add(".github/workflows/1.yml", "name: Test\non: [status, check_run]")
        files.add(".github/workflows/2.yml", "name: Test\non: [status, issues, push, pull_request, workflow_dispatch]")
      end

      assert_equal Set["check_run", "issues", "status"], @repo.send(:workflow_triggers, @repo.default_branch_ref.target_oid, Actions::Workflow::WORKFLOWS_PATH)
    end

    test "returns an empty set if no workflows are triggered by default branch events" do
      assert_equal "master", @repo.default_branch
      ref = @repo.heads.find("master")

      ref.append_commit(@commit_metadata, @repo.owner) do |files|
        files.add(".github/workflows/1.yml", "name: Test\non: [push]")
        files.add(".github/workflows/2.yml", "name: Test\non: [pull_request]")
      end

      assert_equal Set[], @repo.send(:workflow_triggers, @repo.default_branch_ref.target_oid, Actions::Workflow::WORKFLOWS_PATH)
    end

    test "returns all default branch events when over the workflow file limit" do
      assert_equal "master", @repo.default_branch
      ref = @repo.heads.find("master")

      ref.append_commit(@commit_metadata, @repo.owner) do |files|
        (0..100).each do |i|
          files.add(".github/workflows/#{i}.yml", "name: Test\non: [status, issues]")
        end
      end

      assert_equal Repository::WorkflowsDependency::DEFAULT_BRANCH_EVENTS, @repo.send(:workflow_triggers, @repo.default_branch_ref.target_oid, Actions::Workflow::WORKFLOWS_PATH)
    end

    test "returns all default branch events when no triggers are identified for a workflow" do
      assert_equal "master", @repo.default_branch
      ref = @repo.heads.find("master")

      ref.append_commit(@commit_metadata, @repo.owner) do |files|
        files.add(".github/workflows/1.yml", "name: Test\non: []")
      end

      assert_equal Repository::WorkflowsDependency::DEFAULT_BRANCH_EVENTS, @repo.send(:workflow_triggers, @repo.default_branch_ref.target_oid, Actions::Workflow::WORKFLOWS_PATH)
    end

    test "returns all default branch events when a workflow has a yaml parsing error" do
      assert_equal "master", @repo.default_branch
      ref = @repo.heads.find("master")

      ref.append_commit(@commit_metadata, @repo.owner) do |files|
        files.add(".github/workflows/1.yml", "name: Test\non: [status") # no closing bracket
      end

      assert_equal Repository::WorkflowsDependency::DEFAULT_BRANCH_EVENTS, @repo.send(:workflow_triggers, @repo.default_branch_ref.target_oid, Actions::Workflow::WORKFLOWS_PATH)
    end

    test "returns all default branch events when a large workflow file is truncated" do
      assert_equal "master", @repo.default_branch
      ref = @repo.heads.find("master")

      data = "name: Test\n".dup
      data << "on: [status]\n"

      data << "description: |\n"
      data << "  #{Faker::Lorem.paragraph}\n" * 2_000

      ref.append_commit(@commit_metadata, @repo.owner) do |files|
        files.add(".github/workflows/1.yml", data)
      end

      # Verify the workflow is valid
      assert_equal Set["status"], @repo.send(:workflow_triggers, @repo.default_branch_ref.target_oid, Actions::Workflow::WORKFLOWS_PATH)

      # Now grow the workflow beyond 1MB
      data << "  #{Faker::Lorem.paragraph}\n" * 90_000

      ref.append_commit(@commit_metadata, @repo.owner) do |files|
        files.add(".github/workflows/1.yml", data)
      end

      assert_equal Repository::WorkflowsDependency::DEFAULT_BRANCH_EVENTS, @repo.send(:workflow_triggers, @repo.default_branch_ref.target_oid, Actions::Workflow::WORKFLOWS_PATH)
    end

  end

  context "#has_workflow_trigger_for?" do

    test "returns true for non-default branch events" do
      refute @repo.includes_directory? Actions::Workflow::WORKFLOWS_PATH

      Repository::WorkflowsDependency::NON_DEFAULT_BRANCH_EVENTS.each do |event|
        assert @repo.has_workflow_trigger_for?(event)
      end
    end

    test "returns true if event is 'status' and trigger exists" do
      @repo.default_branch_ref.append_commit(@commit_metadata, @repo.owner) do |files|
        files.add(".github/workflows/1.yml", "name: Test\non: [status, issues]")
      end

      assert @repo.has_workflow_trigger_for?("status")
    end

    test "returns false if event is 'status' and trigger does not exist" do
      @repo.default_branch_ref.append_commit(@commit_metadata, @repo.owner) do |files|
        files.add(".github/workflows/1.yml", "name: Test\non: [issues, gollum]")
      end

      refute @repo.has_workflow_trigger_for?("status")
    end

    test "returns true if event is 'status' and trigger exists for lab" do
      @repo.default_branch_ref.append_commit(@commit_metadata, @repo.owner) do |files|
        files.add(".github/workflows-lab/1.yml", "name: Test\non: [status, issues]")
      end

      assert @repo.has_workflow_trigger_for?("status", lab: true)
    end

    test "returns false if event is 'status' and trigger does not exist for lab" do
      @repo.default_branch_ref.append_commit(@commit_metadata, @repo.owner) do |files|
        files.add(".github/workflows/1.yml", "name: Test\non: [status, issues]")
        files.add(".github/workflows-lab/keep", "Ensure this directory exists")
      end

      refute @repo.has_workflow_trigger_for?("status", lab: true)
    end

    test "caches workflow triggers" do
      # The workflows directory has to exist for the stub to be called.
      @repo.default_branch_ref.append_commit(@commit_metadata, @repo.owner) do |files|
        files.add(".github/workflows/keep", "Ensure this directory exists")
      end

      tree_oid = @repo.tree(@repo.default_branch_ref.target_oid, Actions::Workflow::WORKFLOWS_PATH).oid

      GitHub.cache.allow = /repo:\d+:tree:[a-z\d]+:workflows_tree_triggers:v1/
      @repo.stubs(:workflow_triggers).returns(Set["check_run", "status"]).once

      assert @repo.has_workflow_trigger_for?("status")
      refute @repo.has_workflow_trigger_for?("gollum")

      cache_key = "repo:#{@repo.id}:tree:#{tree_oid}:workflows_tree_triggers:v1"
      assert_equal Set["check_run", "status"], GitHub.cache.get(cache_key)
    end

    test "cache hit following unrelated change" do
      # The workflows directory has to exist for the stub to be called.
      @repo.default_branch_ref.append_commit(@commit_metadata, @repo.owner) do |files|
        files.add(".github/workflows/keep", "Ensure this directory exists")
      end

      tree_oid = @repo.tree(@repo.default_branch_ref.target_oid, Actions::Workflow::WORKFLOWS_PATH).oid

      GitHub.cache.allow = /repo:\d+:tree:[a-z\d]+:workflows_tree_triggers:v1/
      @repo.stubs(:workflow_triggers).returns(Set["check_run", "status"]).once

      assert @repo.has_workflow_trigger_for?("status")
      refute @repo.has_workflow_trigger_for?("gollum")

      cache_key = "repo:#{@repo.id}:tree:#{tree_oid}:workflows_tree_triggers:v1"
      assert_equal Set["check_run", "status"], GitHub.cache.get(cache_key)

      @repo.default_branch_ref.append_commit(@commit_metadata, @repo.owner) do |files|
        files.add("README.md", "This changes the head sha but not the workflows directory tree oid")
      end

      assert @repo.has_workflow_trigger_for?("status")
      refute @repo.has_workflow_trigger_for?("gollum")
    end

    test "cache miss following workflows directory change" do
      # The workflows directory has to exist for the stub to be called.
      @repo.default_branch_ref.append_commit(@commit_metadata, @repo.owner) do |files|
        files.add(".github/workflows/keep", "Ensure this directory exists")
      end

      first_tree_oid = @repo.tree(@repo.default_branch_ref.target_oid, Actions::Workflow::WORKFLOWS_PATH).oid

      GitHub.cache.allow = /repo:\d+:tree:[a-z\d]+:workflows_tree_triggers:v1/
      @repo.stubs(:workflow_triggers).returns(Set["check_run", "status"]).twice

      assert @repo.has_workflow_trigger_for?("status")
      refute @repo.has_workflow_trigger_for?("gollum")

      first_cache_key = "repo:#{@repo.id}:tree:#{first_tree_oid}:workflows_tree_triggers:v1"
      assert_equal Set["check_run", "status"], GitHub.cache.get(first_cache_key)

      @repo.default_branch_ref.append_commit(@commit_metadata, @repo.owner) do |files|
        files.add(".github/workflows/keep2", "This changes both the sha and the tree oid")
      end

      second_tree_oid = @repo.tree(@repo.default_branch_ref.target_oid, Actions::Workflow::WORKFLOWS_PATH).oid

      refute_equal second_tree_oid, first_tree_oid

      assert @repo.has_workflow_trigger_for?("status")
      refute @repo.has_workflow_trigger_for?("gollum")

      second_cache_key = "repo:#{@repo.id}:tree:#{second_tree_oid}:workflows_tree_triggers:v1"
      assert_equal Set["check_run", "status"], GitHub.cache.get(second_cache_key)
    end

    test "returns false when workflows path is missing" do
      workflows_tree = @repo.tree(@repo.default_branch_ref.target_oid, Actions::Workflow::WORKFLOWS_PATH)

      # Verify our example repo doesn't have a workflows directory.
      assert_nil workflows_tree
      refute @repo.has_workflow_trigger_for?("status")
    end

    test "returns false when workflows path is blob" do
      @repo.default_branch_ref.append_commit(@commit_metadata, @repo.owner) do |files|
        files.add(".github/workflows", "I'm a blob, not a tree")
      end

      refute @repo.has_workflow_trigger_for?("status")
    end

    test "returns true and sends a Failbot when an exception is thrown internally" do
      @repo.stubs(:workflow_triggers).raises(StandardError)

      @repo.default_branch_ref.append_commit(@commit_metadata, @repo.owner) do |files|
        files.add(".github/workflows/keep", "Ensure this directory exists so we get to the `workflow_triggers` call")
      end

      Failbot.expects(:report).with(instance_of(StandardError), repo_id: @repo.id, event_name: "status")
      assert_nothing_raised do
        assert @repo.has_workflow_trigger_for?("status")
      end
    end
  end
end
