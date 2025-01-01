# typed: true
# frozen_string_literal: true

require "test_helper"

class RulesEngine::WorkflowHelperTest < GitHub::TestCase
  include RulesEngine::RefUpdateTestHelper

  fixtures do
    @org = create :organization, plan: "business_plus"
    @repo = create(:repository, owner: @org, name: "org repo", from_example: :simple)
    @workflow_repo = create(:repository, owner: @org, name: "workflow repo", from_example: :simple)
    @private_repo = create(:private_repository, name: "private", owner: @org, from_example: :simple)
    @random_repo = create(:repository, from_example: :simple)

    @other_org = create :organization, plan: "business_plus"
    @other_repo = create(:repository, owner: @other_org, name: "other repo", from_example: :simple)

    @path = ".github/workflows/test.yml"

    example_repo_snapshot
  end

  setup do
    example_repo_restore
  end

  context "workflow repo sugggestions" do
    test "returns all repos" do
      results = RulesEngine::WorkflowsHelper.workflow_repo_suggestions(@org, "")
      assert_equal 3, results.size
      assert [@workflow_repo, @private_repo, @repo].all? { |repo| results.any? { |result| result[:id] == repo.id } }
    end

    test "returns only matching repo" do
      results = RulesEngine::WorkflowsHelper.workflow_repo_suggestions(@org, "private")
      assert_equal 1, results.size
      assert_equal @private_repo.id, T.must(results.first)[:id]
    end
  end

  context "%workflows_for_ref_update" do
    test "returns matching workflows" do
      create_workflow_file(@workflow_repo, "master", @path)

      ruleset = create :repository_ruleset, :targets_default_branch, :targets_all_repos, source: @org
      create(:repository_rule_configuration, rule_type: "workflows", repository_ruleset: ruleset, parameters: {
        workflows: [{
          repository_id: @workflow_repo.id,
          path: @path,
          ref: "refs/heads/master"
        }]
      })

      before = @repo.heads["master"].target_oid
      after = @repo.commits.create({ message: "New commit", committer: @repo.owner }, before) do |files|
        files.add "New file", "New file"
      end.oid

      ref_update = create_branch_update(@repo, name: "master", before_oid: before, after_oid: after)

      results = RulesEngine::WorkflowsHelper.workflows_for_ref_update(ref_update)

      assert_equal 1, results.size
      result = T.must(results[0])

      assert_equal @workflow_repo, result[:repository]
      assert_equal @path, result[:path]
      assert_equal "refs/heads/master", result[:ref]
      assert_nil result[:sha]
    end

    test "does not return workflows that do not match" do
      create_workflow_file(@workflow_repo, "master", @path)

      ruleset = create :repository_ruleset, :targets_all_repos, source: @org
      create(:repository_rule_configuration, rule_type: "workflows", repository_ruleset: ruleset, parameters: {
        workflows: [{
          repository_id: @workflow_repo.id,
          path: @path,
          ref: "refs/heads/master"
        }]
      })
      create(:repository_rule_condition, :targets_branch, branch_name: "refs/heads/dev", repository_ruleset: ruleset)

      before = @repo.heads["master"].target_oid
      after = @repo.commits.create({ message: "New commit", committer: @repo.owner }, before) do |files|
        files.add "New file", "New file"
      end.oid

      ref_update = create_branch_update(@repo, name: "master", before_oid: before, after_oid: after)

      results = RulesEngine::WorkflowsHelper.workflows_for_ref_update(ref_update)

      assert_equal 0, results.size
    end

    test "does not return invalid workflows" do
      create_workflow_file(@workflow_repo, "master", @path)

      ruleset = create :repository_ruleset, :targets_default_branch, :targets_all_repos, source: @org
      rule_config = create(:repository_rule_configuration, rule_type: "workflows", repository_ruleset: ruleset, parameters: {
        workflows: [{
          repository_id: @workflow_repo.id,
          path: @path,
          ref: "refs/heads/master"
        }]
      })
      # Ignore validation which would not allow a bad ref
      rule_config.parameters["workflows"][0]["ref"] = "refs/heads/does_not_exist"
      rule_config.save(validate: false)

      before = @repo.heads["master"].target_oid
      after = @repo.commits.create({ message: "New commit", committer: @repo.owner }, before) do |files|
        files.add "New file", "New file"
      end.oid

      ref_update = create_branch_update(@repo, name: "master", before_oid: before, after_oid: after)

      results = RulesEngine::WorkflowsHelper.workflows_for_ref_update(ref_update)

      assert_equal 0, results.size
    end
  end

  context "#validate_workflows" do
    test "validates workflow repo exists" do
      workflows = [
        [@org, {
          repository_id: -500000,
          path: @path,
          ref: "refs/heads/master"
        }.stringify_keys]
      ]
      results = RulesEngine::WorkflowsHelper.validate_workflows(workflows)

      assert_equal 1, results.size
      result = T.must(results[0])

      refute result[:valid]
      assert_equal :repo_not_found, result[:error_code]
      assert_equal @path, result[:workflow]["path"]
    end

    test "validates actions sharing enabled" do
      create_workflow_file(@private_repo, "master", @path)

      workflows = [
        [@org, {
          repository_id: @private_repo.id,
          path: @path,
          ref: "refs/heads/master"
        }.stringify_keys]
      ]
      @private_repo.set_actions_repository_share_policy(policy: Configurable::ActionsRepositorySharePolicy::NONE, actor: @private_repo.owner)

      results = RulesEngine::WorkflowsHelper.validate_workflows(workflows)

      assert_equal 1, results.size
      result = T.must(results[0])

      refute result[:valid]
      assert_equal :actions_sharing_disabled, result[:error_code]
      assert_equal @path, result[:workflow]["path"]
    end

    test "validates ref exists" do
      create_workflow_file(@workflow_repo, "master", @path)

      workflows = [
        [@org, {
          repository_id: @workflow_repo.id,
          path: @path,
          ref: "refs/heads/does_not_exist"
        }.stringify_keys]
      ]

      results = RulesEngine::WorkflowsHelper.validate_workflows(workflows)

      assert_equal 1, results.size
      result = T.must(results[0])

      refute result[:valid]
      assert_equal :ref_not_found, result[:error_code]
      assert_equal @path, result[:workflow]["path"]
    end

    test "validates sha is reachable" do
      create_workflow_file(@workflow_repo, "master", @path)

      workflows = [
        [@org, {
          repository_id: @workflow_repo.id,
          path: @path,
          sha: "a" * 40
        }.stringify_keys]
      ]

      results = RulesEngine::WorkflowsHelper.validate_workflows(workflows)

      assert_equal 1, results.size
      result = T.must(results[0])

      refute result[:valid]
      assert_equal :sha_not_found, result[:error_code]
      assert_equal @path, result[:workflow]["path"]
    end

    test "validates path exists" do
      workflows = [
        [@org, {
          repository_id: @workflow_repo.id,
          path: @path,
          ref: "refs/heads/master"
        }.stringify_keys]
      ]

      results = RulesEngine::WorkflowsHelper.validate_workflows(workflows)

      assert_equal 1, results.size
      result = T.must(results[0])

      refute result[:valid]
      assert_equal :workflow_not_found, result[:error_code]
      assert_equal @path, result[:workflow]["path"]

      create_workflow_file(@workflow_repo, "master", @path)

      results = RulesEngine::WorkflowsHelper.validate_workflows(workflows)

      result = T.must(results[0])
      assert result[:valid]
    end

    test "supports tags" do
      workflows = [
        [@org, {
          repository_id: @workflow_repo.id,
          path: @path,
          ref: "refs/tags/test"
        }.stringify_keys]
      ]

      results = RulesEngine::WorkflowsHelper.validate_workflows(workflows)

      assert_equal 1, results.size
      result = T.must(results[0])

      refute result[:valid]
      assert_equal :ref_not_found, result[:error_code]
      assert_equal @path, result[:workflow]["path"]

      create_workflow_file(@workflow_repo, "refs/tags/test", @path)

      results = RulesEngine::WorkflowsHelper.validate_workflows(workflows)

      result = T.must(results[0])
      assert result[:valid]
    end

    test "validates path exists at sha" do
      workflows = [
        [@org, {
          repository_id: @workflow_repo.id,
          path: @path,
          ref: "refs/heads/master",
          sha: @workflow_repo.heads["master"].target_oid
        }.stringify_keys]
      ]

      results = RulesEngine::WorkflowsHelper.validate_workflows(workflows)

      assert_equal 1, results.size
      result = T.must(results[0])

      refute result[:valid]
      assert_equal :workflow_not_found, result[:error_code]
      assert_equal @path, result[:workflow]["path"]

      create_workflow_file(@workflow_repo, "master", @path)
      workflows[0][1]["sha"] = @workflow_repo.heads["master"].target_oid

      results = RulesEngine::WorkflowsHelper.validate_workflows(workflows)

      result = T.must(results[0])
      assert result[:valid]
    end

    test "validates repo in org" do
      create_workflow_file(@random_repo, "master", @path)

      workflows = [
        [@org, {
          repository_id: @random_repo.id,
          path: @path,
          ref: "refs/heads/master"
        }.stringify_keys]
      ]

      results = RulesEngine::WorkflowsHelper.validate_workflows(workflows)

      assert_equal 1, results.size
      result = T.must(results[0])

      refute result[:valid]
      assert_equal :not_in_org, result[:error_code]
      assert_equal @path, result[:workflow]["path"]
    end
  end

  test "validates path is in .github/workflows" do
    create_workflow_file(@workflow_repo, "master", "invalid/path/test.yml")

    workflows = [
      [@org, {
        repository_id: @workflow_repo.id,
        path: "invalid/path/test.yml",
        ref: "refs/heads/master"
      }.stringify_keys]
    ]

    results = RulesEngine::WorkflowsHelper.validate_workflows(workflows)

    assert_equal 1, results.size
    result = T.must(results[0])

    refute result[:valid]
    assert_equal :workflow_path_invalid, result[:error_code]
    assert_equal "invalid/path/test.yml", result[:workflow]["path"]
  end

  test "validates paths with lab workflows are valid" do
    lab_workflow_path = ".github/workflows-lab/test.yml"
    create_workflow_file(@workflow_repo, "master", lab_workflow_path)

    workflows = [
      [@org, {
        repository_id: @workflow_repo.id,
        path: lab_workflow_path,
        ref: "refs/heads/master"
      }.stringify_keys]
    ]

    results = RulesEngine::WorkflowsHelper.validate_workflows(workflows)

    assert_equal 1, results.size
    result = T.must(results[0])

    assert result[:valid]
    assert_equal lab_workflow_path, result[:workflow]["path"]
  end

  test "validates path is not a subdirectory" do
    create_workflow_file(@workflow_repo, "master", ".github/workflows/subdirectory/test.yml")

    workflows = [
      [@org, {
        repository_id: @workflow_repo.id,
        path: ".github/workflows/subdirectory/test.yml",
        ref: "refs/heads/master"
      }.stringify_keys]
    ]

    results = RulesEngine::WorkflowsHelper.validate_workflows(workflows)

    assert_equal 1, results.size
    result = T.must(results[0])

    refute result[:valid]
    assert_equal :workflow_path_no_subdir, result[:error_code]
    assert_equal ".github/workflows/subdirectory/test.yml", result[:workflow]["path"]
  end

  test "validate workflow_suggestions returns all workflows" do
    create_workflow_file(@workflow_repo, "master", @path)

    Actions::Workflow.new(repository: @workflow_repo, path: @path, name: "workflow-1").save!
    Actions::Workflow.new(repository: @workflow_repo, path: ".github/workflows/foo.yaml", name: "original-do-not-steal").save!

    # imposed workflow
    Actions::Workflow.new(repository: @workflow_repo, path: ".github/workflows/external.yaml", name: "imposed", imposer_repository_id: 18).save!
    results = RulesEngine::WorkflowsHelper.workflow_suggestions(@workflow_repo)

    assert_equal 2, results.size
    assert results.any? { |result| result[:name] == "workflow-1" }
    assert results.any? { |result| result[:name] == "original-do-not-steal" }
    refute results.any? { |result| result[:name] == "imposed" }
  end


  test "allows invalid path if allow_invalid_path is enabled" do
    create_workflow_file(@workflow_repo, "master", "invalid/path/test.yml")

    workflows = [
      [@org, {
        repository_id: @workflow_repo.id,
        path: "invalid/path/test.yml",
        ref: "refs/heads/master",
        allow_invalid_path: true,
      }.stringify_keys]
    ]

    results = RulesEngine::WorkflowsHelper.validate_workflows(workflows)

    assert_equal 1, results.size
    result = T.must(results[0])

    assert result[:valid]
  end

  test "allows subdirectory path if allow_invalid_path is enabled" do
    create_workflow_file(@workflow_repo, "master", ".github/workflows/subdirectory/test.yml")

    workflows = [
      [@org, {
        repository_id: @workflow_repo.id,
        path: ".github/workflows/subdirectory/test.yml",
        ref: "refs/heads/master",
        allow_invalid_path: true,
      }.stringify_keys]
    ]

    results = RulesEngine::WorkflowsHelper.validate_workflows(workflows)

    assert_equal 1, results.size
    result = T.must(results[0])

    assert result[:valid]
  end

  private

  def create_workflow_file(repo, branch_or_ref, path)
    ref = branch_or_ref.starts_with?("refs/") ? branch_or_ref : "refs/heads/#{branch_or_ref}"
    unless repo.refs.exist?(ref)
      repo.refs.create(ref, repo.heads[repo.default_branch].target_oid, repo.owner)
    end
    repo.refs[ref].append_commit({ message: "add workflow", committer: repo.owner }, repo.owner) do |files|
      files.add(path, "some content")
    end
  end
end
