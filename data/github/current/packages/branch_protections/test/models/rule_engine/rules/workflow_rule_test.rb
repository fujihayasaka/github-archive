# typed: true
# frozen_string_literal: true

require "test_helper"

class WorkflowRuleTest < GitHub::TestCase
  include RulesEngine::RefUpdateTestHelper

  MAIN_SHA = "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24"
  BRANCH_SHA = "e91a032dc9f19058a375fb3db68c9dda73527d13"

  fixtures do
    @org = create :organization, plan: "business_plus"
    @repo = create(:repository, owner: @org, from_example: :simple)

    @random_repo = create :private_repository, from_example: :simple
    @workflow_repo = create :repository, owner: @org, name: "workflow repo", from_example: :simple
    @path = ".github/workflows/test.yml"

    example_repo_snapshot
  end

  setup do
    example_repo_restore

    @ref_updates = create_branch_update(@repo, name: "main", before_oid: MAIN_SHA, after_oid: BRANCH_SHA),
    @context = RuleEngine::RuleEvaluationContext.new(@repo, @user)
    @ruleset = create(:repository_ruleset, source: @org)
    @rule_config = build(
      :repository_rule_configuration,
      rule_type: "workflows",
      repository_ruleset: @ruleset,
      parameters: {}
    )
    @rule = RuleEngine::Rules::WorkflowRule.new

    GitHub.stubs(:actions_enabled?).returns(true)
  end

  test "provides UI with workflow metadata" do
    create_workflow_file(@workflow_repo, "master", @path)
    Actions::Workflow.create_or_update_workflow(@path, "Test", @workflow_repo, nil)
    @rule_config.parameters = {
      workflows: [{
        repository_id: @workflow_repo.id,
        path: @path,
        ref: "refs/heads/master"
      }]
    }

    metadata = @rule.ruleset_ui_metadata(@rule_config)

    assert metadata
    assert_equal 1, metadata[:workflows].length
    assert_equal "Test", metadata[:workflows][0][:name]
    assert_equal @path, metadata[:workflows][0][:path]
    assert_equal @workflow_repo.id, metadata[:workflows][0][:repository][:id]
    assert_equal @workflow_repo.name, metadata[:workflows][0][:repository][:name]
  end

  test "missing workflow does not provide UI with workflow metadata" do
    @rule_config.parameters = {
      workflows: [{
        repository_id: @workflow_repo.id,
        path: @path,
        ref: "refs/heads/master"
      }]
    }

    metadata = @rule.ruleset_ui_metadata(@rule_config)

    assert metadata
    assert_equal 0, metadata[:workflows].length
  end

  test "missing workflow does provide UI with workflow metadata if allow_invalid_path is enabled" do
    @rule_config.parameters = {
      workflows: [{
        repository_id: @workflow_repo.id,
        path: "some-invalid-path/workflow.yml",
        ref: "refs/heads/master",
        allow_invalid_path: true
      }]
    }

    metadata = @rule.ruleset_ui_metadata(@rule_config)

    assert metadata
    assert_equal 1, metadata[:workflows].length
    assert_equal "", metadata[:workflows][0][:name]
    assert_equal "some-invalid-path/workflow.yml", metadata[:workflows][0][:path]
    assert_equal @workflow_repo.id, metadata[:workflows][0][:repository][:id]
    assert_equal @workflow_repo.name, metadata[:workflows][0][:repository][:name]
  end

  test "don't leak repo names during validation" do
    # Create a workflow rule with a repo that should not be visible to the organization
    @rule_config.parameters = {
      workflows: [{
        repository_id: @random_repo.id,
        path: @path,
        ref: "refs/heads/master"
      }]
    }

    @rule_config.save

    assert @rule_config.errors.any?
    @rule_config.errors.each do |error|
      refute error.message.include?(@random_repo.name)
    end
  end

  test "soft deleted repositories do not provide UI with workflow metadata" do
    create_workflow_file(@workflow_repo, "master", @path)
    Actions::Workflow.create_or_update_workflow(@path, "Test", @workflow_repo, nil)
    @rule_config.parameters = {
      workflows: [{
        repository_id: @workflow_repo.id,
        path: @path,
        ref: "refs/heads/master"
      }]
    }

    @workflow_repo.active = false
    @workflow_repo.save!

    metadata = @rule.ruleset_ui_metadata(@rule_config)

    assert metadata
    assert_equal 0, metadata[:workflows].length
  end

  test "missing repositories do not provide UI with workflow metadata" do
    create_workflow_file(@workflow_repo, "master", @path)
    Actions::Workflow.create_or_update_workflow(@path, "Test", @workflow_repo, nil)
    @rule_config.parameters = {
      workflows: [{
        repository_id: @workflow_repo.id,
        path: @path,
        ref: "refs/heads/master"
      }]
    }

    @workflow_repo.destroy!

    metadata = @rule.ruleset_ui_metadata(@rule_config)

    assert metadata
    assert_equal 0, metadata[:workflows].length
  end

  context "#matches_workflow" do
    test "returns :run_missing_workflow_file_ref symbol if workflow run is missing the workflow_file_ref" do
      workflow_config = {
        "repository_id" => @workflow_repo.id,
        "path" => @path,
        "ref" => "refs/heads/master"
      }

      check_suite = create(:check_suite_for_actions_app, repository: @repo, workflow_file_path: "required/#{@workflow_repo.id}/#{@path}")
      Actions::WorkflowRun.any_instance.stubs(:workflow_file_ref).returns(nil)

      response = RuleEngine::Rules::WorkflowRule.matches_workflow?(check_suite, workflow_config)

      assert_equal :run_missing_workflow_file_ref, response

    end

    test "does not match to SHA rule config if workflow_file_ref is populated on the workflow run" do
      workflow_config = {
        "repository_id" => @workflow_repo.id,
        "path" => @path,
        "sha" => "abcdef"
      }

      check_suite = create(:check_suite_for_actions_app, repository: @repo, workflow_file_path: "required/#{@workflow_repo.id}/#{@path}")
      Actions::WorkflowRun.any_instance.stubs(:workflow_file_checkout_sha).returns("abcdef")
      Actions::WorkflowRun.any_instance.stubs(:workflow_file_ref).returns("refs/heads/master")

      response = RuleEngine::Rules::WorkflowRule.matches_workflow?(check_suite, workflow_config)

      assert_equal false, response
    end

    test "matches to SHA rule config if workflow_file_ref is not populated on the workflow run" do
      workflow_config = {
        "repository_id" => @workflow_repo.id,
        "path" => @path,
        "sha" => "abcdef"
      }

      check_suite = create(:check_suite_for_actions_app, repository: @repo, workflow_file_path: "required/#{@workflow_repo.id}/#{@path}")
      Actions::WorkflowRun.any_instance.stubs(:workflow_file_checkout_sha).returns("abcdef")
      Actions::WorkflowRun.any_instance.stubs(:workflow_file_ref).returns(nil)

      response = RuleEngine::Rules::WorkflowRule.matches_workflow?(check_suite, workflow_config)

      assert_equal true, response
    end

    test "matches to ref rule config if workflow_file_ref is populated on the workflow run" do
      workflow_config = {
        "repository_id" => @workflow_repo.id,
        "path" => @path,
        "ref" => "refs/heads/master"
      }

      check_suite = create(:check_suite_for_actions_app, repository: @repo, workflow_file_path: "required/#{@workflow_repo.id}/#{@path}")
      Actions::WorkflowRun.any_instance.stubs(:workflow_file_checkout_sha).returns("abcdef")
      Actions::WorkflowRun.any_instance.stubs(:workflow_file_ref).returns("refs/heads/master")

      response = RuleEngine::Rules::WorkflowRule.matches_workflow?(check_suite, workflow_config)

      assert_equal true, response
    end

    test "matches to SHA & ref rule config if both are populated on the workflow run" do
      workflow_config = {
        "repository_id" => @workflow_repo.id,
        "path" => @path,
        "ref" => "refs/heads/master",
        "sha" => "abcdef"
      }

      check_suite = create(:check_suite_for_actions_app, repository: @repo, workflow_file_path: "required/#{@workflow_repo.id}/#{@path}")
      Actions::WorkflowRun.any_instance.stubs(:workflow_file_checkout_sha).returns("abcdef")
      Actions::WorkflowRun.any_instance.stubs(:workflow_file_ref).returns("refs/heads/master")

      response = RuleEngine::Rules::WorkflowRule.matches_workflow?(check_suite, workflow_config)

      assert_equal true, response
    end
  end

  test "returns invalid message if workflow does not exist" do
    @rule_config.parameters = {
      workflows: [{
        repository_id: @workflow_repo.id,
        path: @path,
        ref: "refs/heads/master"
      }]
    }
    check_suite = create(:check_suite_for_actions_app, repository: @repo, workflow_file_path: "required/#{@workflow_repo.id}/#{@path}",
      head_sha: BRANCH_SHA, status: "completed", completed_at: DateTime.now, conclusion: "failure")
    Actions::WorkflowRun.any_instance.stubs(:workflow_file_ref).returns("refs/heads/master")

    context = RuleEngine::RuleEvaluationContext.new(@repo, @user)

    result = @rule.evaluate(context, @ref_updates.first, [@rule_config])

    assert_equal 1, result.size
    assert result.first.failed?
    assert_equal "Required workflow configuration invalid", result.first.message
  end

  test "evaluates correctly if there are reruns on the same SHA" do
    create_workflow_file(@workflow_repo, "master", @path)
    Actions::Workflow.create_or_update_workflow(@path, "Test", @workflow_repo, nil)

    @rule_config.parameters = {
      workflows: [{
        repository_id: @workflow_repo.id,
        path: @path,
        ref: "refs/heads/master"
      }]
    }

    check_suite_older = Timecop.freeze(3.hours.ago) do
      create(:check_suite_for_actions_app, repository: @repo, workflow_file_path: "required/#{@workflow_repo.id}/#{@path}",
        head_sha: BRANCH_SHA, status: "completed", completed_at: DateTime.now, conclusion: "success")
    end

    check_suite_newer = Timecop.freeze(2.hours.ago) do
      create(:check_suite_for_actions_app, repository: @repo, workflow_file_path: "required/#{@workflow_repo.id}/#{@path}",
        head_sha: BRANCH_SHA, status: "completed", completed_at: DateTime.now, conclusion: "failure")
    end

    Actions::WorkflowRun.any_instance.stubs(:workflow_file_ref).returns("refs/heads/master")
    Actions::WorkflowRun.any_instance.stubs(:workflow_file_checkout_sha).returns("abcdef")

    context = RuleEngine::RuleEvaluationContext.new(@repo, @user)

    result = @rule.evaluate(context, @ref_updates.first, [@rule_config])

    assert_equal 1, result.size
    assert result.first.failed?
    assert_equal "Required workflows 'Test' failed", result.first.message
  end

  test "should return [:deletion] when a rule config with bypass new branch disabled" do
    create_workflow_file(@workflow_repo, "master", @path)
    Actions::Workflow.create_or_update_workflow(@path, "Test", @workflow_repo, nil)
    @rule_config.parameters = {
      workflows: [{
        repository_id: @workflow_repo.id,
        path: @path,
        ref: "refs/heads/master"
      }]
    }

    assert_same_elements [:deletion], @rule.ignore_update_types(@rule_config)

    @rule_config.parameters["do_not_enforce_on_create"] = true
    @rule_config.save
    assert_same_elements [:creation, :deletion], @rule.ignore_update_types(@rule_config)

    @rule_config.parameters["do_not_enforce_on_create"] = false
    @rule_config.save!
    assert_same_elements [:deletion], @rule.ignore_update_types(@rule_config)
  end

  test "ref_update_ignored?" do
    create_workflow_file(@workflow_repo, "master", @path)
    Actions::Workflow.create_or_update_workflow(@path, "Test", @workflow_repo, nil)
    @rule_config.parameters = {
      workflows: [{
        repository_id: @workflow_repo.id,
        path: @path,
        ref: "refs/heads/master"
      }]
    }
    @rule_config.save!

    update_refs = create_branch_update(@repo, name: "main", before_oid: MAIN_SHA, after_oid: BRANCH_SHA)
    create_refs = create_branch_update(@repo, name: "my_branch", before_oid: GitHub::NULL_OID, after_oid: MAIN_SHA)

    @rule_config.parameters["do_not_enforce_on_create"] = true
    @rule_config.save!
    refute @rule.ref_update_ignored?(@context, update_refs, @rule_config)
    assert @rule.ref_update_ignored?(@context, create_refs, @rule_config)

    @rule_config.parameters["do_not_enforce_on_create"] = false
    @rule_config.save!
    refute @rule.ref_update_ignored?(@context, update_refs, @rule_config)
    refute @rule.ref_update_ignored?(@context, create_refs, @rule_config)
  end

  private

  def create_workflow_file(repo, branch, path)
    repo.heads[branch].append_commit({ message: "add workflow", committer: repo.owner }, repo.owner) do |files|
      files.add(path, "some content")
    end
  end
end
