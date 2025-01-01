# typed: true
# frozen_string_literal: true

require "test_helper"

class StatusCheckEvaluatorTest < GitHub::TestCase
  include RulesEngine::RefUpdateTestHelper

  fixtures do
    @owner = create(:user)

    @repo = create(:repository, owner: @owner, from_example: :simple)

    @protected_branch = create(:protected_branch, repository: @repo, required_status_checks_enforcement_level: :non_admins)

    example_repo_snapshot
  end

  setup do
    example_repo_restore
  end

  def status_checks_policy_config(status_checks, strict:)
    build(
      :repository_rule_configuration,
      rule_type: :required_status_checks,
      parameters: {
        strict_required_status_checks_policy: strict
      },
      lazy_parameters: {
        required_status_checks: lambda { status_checks },
      })
  end

  context "with rule" do
    test "fails when the most recent status is failure" do
      @protected_branch.update!(name: "ma*")
      @protected_branch.required_status_checks.create! context: "a context"
      failure_status = create :status, repository: @repo, creator: @owner, sha: @repo.refs["master"].sha, context: "a context", state: "failure"

      ref_update = create_branch_update(@repo,
                                        name: "master",
                                        before_oid: GitHub::NULL_OID, after_oid: @repo.refs["master"].sha)
      config = status_checks_policy_config([RequiredStatusCheck.new(context: "a context")], strict: true)
      decisions = RuleEngine::StatusCheckEvaluator.evaluate(repository: @repo, ref_update: ref_update, rule_configs: [config])
      decision = T.must(decisions[config])
      check_decision = T.must(decision.status_check_results.first&.last)

      refute decision.rules_fulfilled?, "check passed: #{decision}"
      assert_equal failure_status, check_decision.reason_check
      assert_equal :unsuccessful, check_decision.code
    end

    # Originally, single_context_policy's status evaluation was case insensitive
    # I am not sure if this is used by customers, but it is not a bad idea to keep the behavior the same
    test "fails when the most recent status is failure case insensitive" do
      @protected_branch.update!(name: "ma*")
      @protected_branch.required_status_checks.create! context: "a CONTEXT"
      failure_status = create :status, repository: @repo, creator: @owner, sha: @repo.refs["master"].sha, context: "a context", state: "failure"

      ref_update = create_branch_update(@repo,
                                        name: "master",
                                        before_oid: GitHub::NULL_OID, after_oid: @repo.refs["master"].sha)
      config = status_checks_policy_config([RequiredStatusCheck.new(context: "a CONTEXT")], strict: true)
      decisions = RuleEngine::StatusCheckEvaluator.evaluate(repository: @repo, ref_update: ref_update, rule_configs: [config])
      decision = T.must(decisions[config])
      check_decision = T.must(decision.status_check_results.first&.last)

      refute decision.rules_fulfilled?, "check passed: #{decision}"
      assert_equal failure_status, check_decision.reason_check
      assert_equal :unsuccessful, check_decision.code
    end
  end

  context "strict policy" do
    test "succeeds when the most recent status is success" do
      create :status, repository: @repo, creator: @owner, sha: @repo.refs["master"].sha, context: "a context", state: "failure"
      success = create :status, repository: @repo, creator: @owner, sha: @repo.refs["master"].sha, context: "a context", state: "success"
      @protected_branch.required_status_checks.create! context: "a context"

      ref_update = create_branch_update(@repo,
                                        name: @protected_branch.qualified_name,
                                        before_oid: GitHub::NULL_OID, after_oid: @repo.refs["master"].sha)
      config = status_checks_policy_config([RequiredStatusCheck.new(context: "a context")], strict: true)
      decisions = RuleEngine::StatusCheckEvaluator.evaluate(repository: @repo, ref_update: ref_update, rule_configs: [config])
      decision = T.must(decisions[config])
      check_decision = T.must(decision.status_check_results.first&.last)

      assert decision.rules_fulfilled?, "check failed: #{decision}"
      assert_equal success, check_decision.reason_check
      assert_equal :success, check_decision.code
    end

    test "fails when the most recent status is failure" do
      create :status, repository: @repo, creator: @owner, sha: @repo.refs["master"].sha, context: "a context", state: "success"
      failure_status = create :status, repository: @repo, creator: @owner, sha: @repo.refs["master"].sha, context: "a context", state: "failure"
      @protected_branch.required_status_checks.create! context: "a context"

      ref_update = create_branch_update(@repo,
                                        name: @protected_branch.qualified_name,
                                        before_oid: GitHub::NULL_OID, after_oid: @repo.refs["master"].sha)
      config = status_checks_policy_config([RequiredStatusCheck.new(context: "a context")], strict: true)
      decisions = RuleEngine::StatusCheckEvaluator.evaluate(repository: @repo, ref_update: ref_update, rule_configs: [config])
      decision = T.must(decisions[config])
      check_decision = T.must(decision.status_check_results.first&.last)

      refute decision.rules_fulfilled?, "check passed: #{decision}"
      assert_equal failure_status, check_decision.reason_check
      assert_equal :unsuccessful, check_decision.code
    end

    test "fails when there is no most recent status" do
      @protected_branch.required_status_checks.create! context: "a context"

      ref_update = create_branch_update(@repo,
                                        name: @protected_branch.qualified_name,
                                        before_oid: GitHub::NULL_OID, after_oid: @repo.refs["master"].sha)
      config = status_checks_policy_config([RequiredStatusCheck.new(context: "a context")], strict: true)
      decisions = RuleEngine::StatusCheckEvaluator.evaluate(repository: @repo, ref_update: ref_update, rule_configs: [config])
      decision = T.must(decisions[config])
      check_decision = T.must(decision.status_check_results.first&.last)

      refute decision.rules_fulfilled?, "check passed: #{decision}"
      assert_equal "a context", check_decision.reason_check.context
      assert_equal "expected", check_decision.reason_check.state
      assert_equal :missing, check_decision.code
    end

    test "succeeds when the most recent status is success, and is from the required integration" do
      integration = create(:integration)
      create :status, repository: @repo, creator: integration.bot, sha: @repo.refs["master"].sha, context: "a context", state: "failure"
      success = create :status, repository: @repo, creator: integration.bot, sha: @repo.refs["master"].sha, context: "a context", state: "success"
      required_status_check = @protected_branch.required_status_checks.create! context: "a context", integration: integration

      ref_update = create_branch_update(@repo,
                                        name: @protected_branch.qualified_name,
                                        before_oid: GitHub::NULL_OID, after_oid: @repo.refs["master"].sha)
      config = status_checks_policy_config([required_status_check], strict: true)
      decisions = RuleEngine::StatusCheckEvaluator.evaluate(repository: @repo, ref_update: ref_update, rule_configs: [config])
      decision = T.must(decisions[config])
      check_decision = T.must(decision.status_check_results.first&.last)

      assert decision.rules_fulfilled?, "check failed: #{decision}"
      assert_equal success, check_decision.reason_check
      assert_equal :success, check_decision.code
    end

    test "succeeds when the most recent check run is success, and is from the required integration" do
      integration = create(:integration)
      check_suite = create :check_suite, repository: @repo, github_app: integration, head_sha: @repo.refs["master"].sha
      success = create :check_run, :completed, :success, repository: @repo, creator: integration.bot, check_suite: check_suite, display_name: "a context", completed_at: 3.seconds.ago
      required_status_check = @protected_branch.required_status_checks.create! context: "a context", integration: integration

      ref_update = create_branch_update(@repo,
                                        name: @protected_branch.qualified_name,
                                        before_oid: GitHub::NULL_OID, after_oid: @repo.refs["master"].sha)
      config = status_checks_policy_config([required_status_check], strict: true)
      decisions = RuleEngine::StatusCheckEvaluator.evaluate(repository: @repo, ref_update: ref_update, rule_configs: [config])
      decision = T.must(decisions[config])
      check_decision = T.must(decision.status_check_results.first&.last)

      assert decision.rules_fulfilled?, "check failed: #{decision}"
      assert_equal success, T.cast(check_decision.reason_check, CombinedStatus::CheckRunAdapter).__getobj__
      assert_equal :success, check_decision.code
    end

    test "fails when the most recent status is success, but not from the required integration" do
      integration = create(:integration)
      create :status, repository: @repo, creator: integration.bot, sha: @repo.refs["master"].sha, context: "a context", state: "failure"
      create :status, repository: @repo, creator: @owner, sha: @repo.refs["master"].sha, context: "a context", state: "success"
      required_status_check = @protected_branch.required_status_checks.create! context: "a context", integration: integration

      ref_update = create_branch_update(@repo,
                                        name: @protected_branch.qualified_name,
                                        before_oid: GitHub::NULL_OID, after_oid: @repo.refs["master"].sha)
      config = status_checks_policy_config([required_status_check], strict: true)
      decisions = RuleEngine::StatusCheckEvaluator.evaluate(repository: @repo, ref_update: ref_update, rule_configs: [config])
      decision = T.must(decisions[config])
      check_decision = T.must(decision.status_check_results.first&.last)

      refute_predicate decision, :rules_fulfilled?
      assert_equal "a context", check_decision.reason_check.context
      assert_equal "success", check_decision.reason_check.state
      assert_equal :invalid_integration, check_decision.code
    end

    test "fails when tip commit has no statuses, other commit with same tree has passing status" do
      master = @repo.refs.find("master")
      topic = @repo.refs.create("refs/heads/topic", master.target_oid, @owner)

      create_commit(topic, @owner, "new-file.txt")
      create_commit(master, @owner, "new-file.txt")
      assert_equal master.target.tree_oid, topic.target.tree_oid

      merge_commit = create_merge_commit(@repo, @owner, topic.name)

      create :status, repository: @repo, creator: @owner, sha: master.sha, context: "a context", state: "success"
      @protected_branch.required_status_checks.create! context: "a context"

      ref_update = create_branch_update(@repo,
                                        name: @protected_branch.qualified_name,
                                        before_oid: master.sha, after_oid: merge_commit.sha)
      config = status_checks_policy_config([RequiredStatusCheck.new(context: "a context")], strict: true)
      decisions = RuleEngine::StatusCheckEvaluator.evaluate(repository: @repo, ref_update: ref_update, rule_configs: [config])
      decision = T.must(decisions[config])
      check_decision = T.must(decision.status_check_results.first&.last)

      refute decision.rules_fulfilled?, "check passed: #{decision}"
      assert_equal "a context", check_decision.reason_check.context
      assert_equal "expected", check_decision.reason_check.state
      assert_equal :missing, check_decision.code
    end

    test "succeeds when tip commit has passing status, master/before commit with same tree has newer, failing status" do
      master = @repo.refs.find("master")
      topic = @repo.refs.create("refs/heads/topic", master.target_oid, @owner)

      create_commit(topic, @owner, "new-file.txt")
      create_commit(master, @owner, "new-file.txt")
      assert_equal master.target.tree_oid, topic.target.tree_oid

      merge_commit = create_merge_commit(@repo, @owner, topic.name)

      success = create :status, repository: @repo, creator: @owner, sha: topic.sha, context: "a context", state: "success"
      create :status, repository: @repo, creator: @owner, sha: master.sha, context: "a context", state: "failure"
      @protected_branch.required_status_checks.create! context: "a context"

      ref_update = create_branch_update(@repo,
                                        name: @protected_branch.qualified_name,
                                        before_oid: master.sha, after_oid: merge_commit.sha)
      config = status_checks_policy_config([RequiredStatusCheck.new(context: "a context")], strict: true)
      decisions = RuleEngine::StatusCheckEvaluator.evaluate(repository: @repo, ref_update: ref_update, rule_configs: [config])
      decision = T.must(decisions[config])
      check_decision = T.must(decision.status_check_results.first&.last)

      assert decision.rules_fulfilled?, "check failed: #{decision}"
      assert_equal success, check_decision.reason_check
      assert_equal :success, check_decision.code
    end

    test "succeeds when tip commit has passing status, other commit with same tree has newer, failing status" do
      master = @repo.refs.find("master")
      topic_one = @repo.refs.create("refs/heads/topic_one", master.target_oid, @owner)
      topic_two = @repo.refs.create("refs/heads/topic_two", master.target_oid, @owner)

      create_commit(topic_one, @owner, "new-file.txt")
      create_commit(topic_two, @owner, "new-file.txt")
      assert_equal topic_one.target.tree_oid, topic_two.target.tree_oid

      merge_commit = create_merge_commit(@repo, @owner, topic_one.name)

      success = create :status, repository: @repo, creator: @owner, sha: topic_one.sha, context: "a context", state: "success"
      create :status, repository: @repo, creator: @owner, sha: topic_two.sha, context: "a context", state: "failure"
      @protected_branch.required_status_checks.create! context: "a context"

      ref_update = create_branch_update(@repo,
                                        name: @protected_branch.qualified_name,
                                        before_oid: master.sha, after_oid: merge_commit.sha)
      config = status_checks_policy_config([RequiredStatusCheck.new(context: "a context")], strict: true)
      decisions = RuleEngine::StatusCheckEvaluator.evaluate(repository: @repo, ref_update: ref_update, rule_configs: [config])
      decision = T.must(decisions[config])
      check_decision = T.must(decision.status_check_results.first&.last)

      assert decision.rules_fulfilled?, "check failed: #{decision}"
      assert_equal success, check_decision.reason_check
      assert_equal :success, check_decision.code
    end

    test "fails when tip commit has failing status, other commit with same tree has newer, passing status" do
      master = @repo.refs.find("master")
      topic = @repo.refs.create("refs/heads/topic", master.target_oid, @owner)

      create_commit(topic, @owner, "new-file.txt")
      create_commit(master, @owner, "new-file.txt")
      assert_equal master.target.tree_oid, topic.target.tree_oid

      merge_commit = create_merge_commit(@repo, @owner, topic.name)

      create :status, repository: @repo, creator: @owner, sha: topic.sha, context: "a context", state: "failure"
      create :status, repository: @repo, creator: @owner, sha: master.sha, context: "a context", state: "success"
      @protected_branch.required_status_checks.create! context: "a context"

      ref_update = create_branch_update(@repo,
                                        name: @protected_branch.qualified_name,
                                        before_oid: master.sha, after_oid: merge_commit.sha)
      config = status_checks_policy_config([RequiredStatusCheck.new(context: "a context")], strict: true)
      decisions = RuleEngine::StatusCheckEvaluator.evaluate(repository: @repo, ref_update: ref_update, rule_configs: [config])
      decision = T.must(decisions[config])
      check_decision = T.must(decision.status_check_results.first&.last)

      refute decision.rules_fulfilled?, "check passed: #{decision}"
      assert_equal "a context", check_decision.reason_check.context
      assert_equal "failure", check_decision.reason_check.state
      assert_equal :unsuccessful, check_decision.code
    end

    test "fails when empty tip commit has failing status, previous commit with same tree has passing status" do
      master = @repo.refs.find("master")
      topic = @repo.refs.create("refs/heads/topic", master.target_oid, @owner)

      previous_commit = create_commit(topic, @owner, "new-file.txt")
      empty_tip_commit = create_commit(topic, @owner)
      assert_equal previous_commit.tree_oid, empty_tip_commit.tree_oid

      create :status, repository: @repo, creator: @owner, sha: master.sha, context: "a context", state: "success"
      create :status, repository: @repo, creator: @owner, sha: previous_commit.sha, context: "a context", state: "success"
      create :status, repository: @repo, creator: @owner, sha: empty_tip_commit.sha, context: "a context", state: "failure"
      @protected_branch.required_status_checks.create! context: "a context"

      ref_update = create_branch_update(@repo,
                                        name: @protected_branch.qualified_name,
                                        before_oid: master.sha, after_oid: empty_tip_commit.sha)
      config = status_checks_policy_config([RequiredStatusCheck.new(context: "a context")], strict: true)
      decisions = RuleEngine::StatusCheckEvaluator.evaluate(repository: @repo, ref_update: ref_update, rule_configs: [config])
      decision = T.must(decisions[config])
      check_decision = T.must(decision.status_check_results.first&.last)

      refute decision.rules_fulfilled?, "check passed: #{decision}"
      assert_equal "a context", check_decision.reason_check.context
      assert_equal "failure", check_decision.reason_check.state
      assert_equal :unsuccessful, check_decision.code
    end

    test "fails when topic branch is out-of-date but all have success statuses" do
      master = @repo.refs.find("master")
      topic = @repo.refs.create("refs/heads/topic", master.target_oid, @owner)

      create_commit(topic, @owner, "new-file.txt")
      create_commit(master, @owner, "another-new-file.txt")
      merge_commit = create_merge_commit(@repo, @owner, topic.name)

      create :status, repository: @repo, creator: @owner, sha: topic.sha, context: "a context", state: "success"
      create :status, repository: @repo, creator: @owner, sha: master.sha, context: "a context", state: "success"
      @protected_branch.required_status_checks.create! context: "a context"

      ref_update = create_branch_update(@repo,
                                        name: @protected_branch.qualified_name,
                                        before_oid: master.sha, after_oid: merge_commit.sha)
      config = status_checks_policy_config([RequiredStatusCheck.new(context: "a context")], strict: true)
      decisions = RuleEngine::StatusCheckEvaluator.evaluate(repository: @repo, ref_update: ref_update, rule_configs: [config])
      decision = T.must(decisions[config])
      check_decision = T.must(decision.status_check_results.first&.last)

      refute decision.rules_fulfilled?, "check passed: #{decision}"
      assert_equal "a context", check_decision.reason_check.context
      assert_equal "expected", check_decision.reason_check.state
      assert_equal :missing, check_decision.code
    end
  end

  context "loose policy" do
    context "same/similar situations as for the strict policy" do
      test "succeeds when the most recent status is success" do
        create :status, repository: @repo, creator: @owner, sha: @repo.refs["master"].sha, context: "a context", state: "failure"
        success = create :status, repository: @repo, creator: @owner, sha: @repo.refs["master"].sha, context: "a context", state: "success"
        @protected_branch.required_status_checks.create! context: "a context"

        ref_update = create_branch_update(@repo,
                                          name: @protected_branch.qualified_name,
                                          before_oid: GitHub::NULL_OID, after_oid: @repo.refs["master"].sha)
        config = status_checks_policy_config([RequiredStatusCheck.new(context: "a context")], strict: false)
        decisions = RuleEngine::StatusCheckEvaluator.evaluate(repository: @repo, ref_update: ref_update, rule_configs: [config])
        decision = T.must(decisions[config])
        check_decision = T.must(decision.status_check_results.first&.last)

        assert decision.rules_fulfilled?, "check failed: #{decision}"
        assert_equal success, check_decision.reason_check
      end

      test "fails when the most recent status is failure" do
        create :status, repository: @repo, creator: @owner, sha: @repo.refs["master"].sha, context: "a context", state: "success"
        failure_status = create :status, repository: @repo, creator: @owner, sha: @repo.refs["master"].sha, context: "a context", state: "failure"
        @protected_branch.required_status_checks.create! context: "a context"

        ref_update = create_branch_update(@repo,
                                          name: @protected_branch.qualified_name,
                                          before_oid: GitHub::NULL_OID, after_oid: @repo.refs["master"].sha)
        config = status_checks_policy_config([RequiredStatusCheck.new(context: "a context")], strict: false)
        decisions = RuleEngine::StatusCheckEvaluator.evaluate(repository: @repo, ref_update: ref_update, rule_configs: [config])
        decision = T.must(decisions[config])
        check_decision = T.must(decision.status_check_results.first&.last)

        refute decision.rules_fulfilled?, "check passed: #{decision}"
        assert_equal failure_status, check_decision.reason_check
      end

      test "fails when there is no most recent status" do
        @protected_branch.required_status_checks.create! context: "a context"

        ref_update = create_branch_update(@repo,
                                          name: @protected_branch.qualified_name,
                                          before_oid: GitHub::NULL_OID, after_oid: @repo.refs["master"].sha)
        config = status_checks_policy_config([RequiredStatusCheck.new(context: "a context")], strict: false)
        decisions = RuleEngine::StatusCheckEvaluator.evaluate(repository: @repo, ref_update: ref_update, rule_configs: [config])
        decision = T.must(decisions[config])
        check_decision = T.must(decision.status_check_results.first&.last)

        refute decision.rules_fulfilled?, "check passed: #{decision}"
        assert_equal "a context", check_decision.reason_check.context
        assert_equal "expected", check_decision.reason_check.state
      end

      test "fails when parent commit has no statuses, other commit with same tree has passing status" do
        master = @repo.refs.find("master")
        topic_one = @repo.refs.create("refs/heads/topic-one", master.target_oid, @owner)
        topic_two = @repo.refs.create("refs/heads/topic-two", master.target_oid, @owner)

        create_commit(topic_one, @owner, "new-file.txt")
        create_commit(topic_two, @owner, "new-file.txt")

        merge_commit = create_merge_commit(@repo, @owner, topic_one.name)
        assert_equal merge_commit.tree_oid, topic_two.target.tree_oid

        create :status, repository: @repo, creator: @owner, sha: topic_two.sha, context: "a context", state: "success"
        @protected_branch.required_status_checks.create! context: "a context"

        ref_update = create_branch_update(@repo,
                                          name: @protected_branch.qualified_name,
                                          before_oid: master.sha, after_oid: merge_commit.sha)
        config = status_checks_policy_config([RequiredStatusCheck.new(context: "a context")], strict: false)
        decisions = RuleEngine::StatusCheckEvaluator.evaluate(repository: @repo, ref_update: ref_update, rule_configs: [config])
        decision = T.must(decisions[config])
        check_decision = T.must(decision.status_check_results.first&.last)

        refute decision.rules_fulfilled?, "check passed: #{decision}"
        assert_equal "a context", check_decision.reason_check.context
        assert_equal "expected", check_decision.reason_check.state
      end

      test "succeeds when parent commit has passing status, other commit with same tree has newer, failing status" do
        master = @repo.refs.find("master")
        topic_one = @repo.refs.create("refs/heads/topic-one", master.target_oid, @owner)
        topic_two = @repo.refs.create("refs/heads/topic-two", master.target_oid, @owner)

        create_commit(topic_one, @owner, "new-file.txt")
        create_commit(topic_two, @owner, "new-file.txt")

        merge_commit = create_merge_commit(@repo, @owner, topic_one.name)
        assert_equal merge_commit.tree_oid, topic_two.target.tree_oid

        success = create :status, repository: @repo, creator: @owner, sha: topic_one.sha, context: "a context", state: "success"
        create :status, repository: @repo, creator: @owner, sha: topic_two.sha, context: "a context", state: "failure"
        @protected_branch.required_status_checks.create! context: "a context"

        ref_update = create_branch_update(@repo,
                                          name: @protected_branch.qualified_name,
                                          before_oid: master.sha, after_oid: merge_commit.sha)
        config = status_checks_policy_config([RequiredStatusCheck.new(context: "a context")], strict: false)
        decisions = RuleEngine::StatusCheckEvaluator.evaluate(repository: @repo, ref_update: ref_update, rule_configs: [config])
        decision = T.must(decisions[config])
        check_decision = T.must(decision.status_check_results.first&.last)

        assert decision.rules_fulfilled?, "check failed: #{decision}"
        assert_equal success, check_decision.reason_check
      end

      test "fails when parent commit has failing status, other commit with same tree has newer, passing status" do
        master = @repo.refs.find("master")
        topic_one = @repo.refs.create("refs/heads/topic-one", master.target_oid, @owner)
        topic_two = @repo.refs.create("refs/heads/topic-two", master.target_oid, @owner)

        create_commit(topic_one, @owner, "new-file.txt")
        create_commit(topic_two, @owner, "new-file.txt")

        merge_commit = create_merge_commit(@repo, @owner, topic_one.name)
        assert_equal merge_commit.tree_oid, topic_two.target.tree_oid

        create :status, repository: @repo, creator: @owner, sha: topic_one.sha, context: "a context", state: "failure"
        create :status, repository: @repo, creator: @owner, sha: topic_two.sha, context: "a context", state: "success"
        @protected_branch.required_status_checks.create! context: "a context"

        ref_update = create_branch_update(@repo,
                                          name: @protected_branch.qualified_name,
                                          before_oid: master.sha, after_oid: merge_commit.sha)
        config = status_checks_policy_config([RequiredStatusCheck.new(context: "a context")], strict: false)
        decisions = RuleEngine::StatusCheckEvaluator.evaluate(repository: @repo, ref_update: ref_update, rule_configs: [config])
        decision = T.must(decisions[config])
        check_decision = T.must(decision.status_check_results.first&.last)

        refute decision.rules_fulfilled?, "check passed: #{decision}"
        assert_equal "a context", check_decision.reason_check.context
        assert_equal "failure", check_decision.reason_check.state
      end

      test "fails when empty merge commit has failing status, previous commit with same tree has passing status" do
        master = @repo.refs.find("master")
        topic_one = @repo.refs.create("refs/heads/topic_one", master.target_oid, @owner)
        topic_two = @repo.refs.create("refs/heads/topic_two", master.target_oid, @owner)

        previous_commit = create_commit(topic_one, @owner, "new-file.txt")
        empty_commit = create_commit(topic_two, @owner)
        empty_merge_commit = create_merge_commit(@repo, @owner, previous_commit.sha, empty_commit.sha)

        assert_equal previous_commit.tree_oid, empty_merge_commit.tree_oid
        assert_predicate empty_merge_commit, :merge_commit?

        create :status, repository: @repo, creator: @owner, sha: master.sha, context: "a context", state: "success"
        create :status, repository: @repo, creator: @owner, sha: previous_commit.sha, context: "a context", state: "success"
        create :status, repository: @repo, creator: @owner, sha: empty_merge_commit.sha, context: "a context", state: "failure"
        @protected_branch.required_status_checks.create! context: "a context"

        ref_update = create_branch_update(@repo,
                                          name: @protected_branch.qualified_name,
                                          before_oid: master.sha, after_oid: empty_merge_commit.sha)
        config = status_checks_policy_config([RequiredStatusCheck.new(context: "a context")], strict: false)
        decisions = RuleEngine::StatusCheckEvaluator.evaluate(repository: @repo, ref_update: ref_update, rule_configs: [config])
        decision = T.must(decisions[config])
        check_decision = T.must(decision.status_check_results.first&.last)

        refute decision.rules_fulfilled?, "check passed: #{decision}"
        assert_equal "a context", check_decision.reason_check.context
        assert_equal "failure", check_decision.reason_check.state
      end
    end

    context "topic branch is up-to-date with master" do
      test "no status yet => expected status" do
        master = @repo.refs.find("master")
        topic = @repo.refs.create("refs/heads/topic", master.target_oid, @owner)

        create_commit(topic, @owner, "new-file.txt")
        merge_commit = create_merge_commit(@repo, @owner, topic.name)

        @protected_branch.required_status_checks.create! context: "a context"

        ref_update = create_branch_update(@repo,
                                          name: @protected_branch.qualified_name,
                                          before_oid: master.sha, after_oid: merge_commit.sha)
        config = status_checks_policy_config([RequiredStatusCheck.new(context: "a context")], strict: false)
        decisions = RuleEngine::StatusCheckEvaluator.evaluate(repository: @repo, ref_update: ref_update, rule_configs: [config])
        decision = T.must(decisions[config])
        check_decision = T.must(decision.status_check_results.first&.last)

        refute decision.rules_fulfilled?, "check passed: #{decision}"
        assert_equal "a context", check_decision.reason_check.context
        assert_equal "expected", check_decision.reason_check.state
      end

      test "success status on topic branch => update allowed" do
        master = @repo.refs.find("master")
        topic = @repo.refs.create("refs/heads/topic", master.target_oid, @owner)

        create_commit(topic, @owner, "new-file.txt")
        merge_commit = create_merge_commit(@repo, @owner, topic.name)

        create :status, repository: @repo, creator: @owner, sha: topic.sha, context: "a context", state: "failure"
        success = create :status, repository: @repo, creator: @owner, sha: topic.sha, context: "a context", state: "success"
        @protected_branch.required_status_checks.create! context: "a context"

        ref_update = create_branch_update(@repo,
                                          name: @protected_branch.qualified_name,
                                          before_oid: master.sha, after_oid: merge_commit.sha)
        config = status_checks_policy_config([RequiredStatusCheck.new(context: "a context")], strict: false)
        decisions = RuleEngine::StatusCheckEvaluator.evaluate(repository: @repo, ref_update: ref_update, rule_configs: [config])
        decision = T.must(decisions[config])
        check_decision = T.must(decision.status_check_results.first&.last)

        assert decision.rules_fulfilled?, "check failed: #{decision}"
        assert_equal success, check_decision.reason_check
      end

      test "failure status on master branch => update allowed" do
        master = @repo.refs.find("master")
        topic = @repo.refs.create("refs/heads/topic", master.target_oid, @owner)

        create_commit(topic, @owner, "new-file.txt")
        merge_commit = create_merge_commit(@repo, @owner, topic.name)

        success = create :status, repository: @repo, creator: @owner, sha: topic.sha, context: "a context", state: "success"
        create :status, repository: @repo, creator: @owner, sha: master.sha, context: "a context", state: "failure"
        @protected_branch.required_status_checks.create! context: "a context"

        ref_update = create_branch_update(@repo,
                                          name: @protected_branch.qualified_name,
                                          before_oid: master.sha, after_oid: merge_commit.sha)
        config = status_checks_policy_config([RequiredStatusCheck.new(context: "a context")], strict: false)
        decisions = RuleEngine::StatusCheckEvaluator.evaluate(repository: @repo, ref_update: ref_update, rule_configs: [config])
        decision = T.must(decisions[config])
        check_decision = T.must(decision.status_check_results.first&.last)

        assert decision.rules_fulfilled?, "check failed: #{decision}"
        assert_equal success, check_decision.reason_check
      end

      test "failure status on topic branch => update denied" do
        master = @repo.refs.find("master")
        topic = @repo.refs.create("refs/heads/topic", master.target_oid, @owner)

        create_commit(topic, @owner, "new-file.txt")
        merge_commit = create_merge_commit(@repo, @owner, topic.name)

        failure_status = create :status, repository: @repo, creator: @owner, sha: topic.sha, context: "a context", state: "failure"
        @protected_branch.required_status_checks.create! context: "a context"

        ref_update = create_branch_update(@repo,
                                          name: @protected_branch.qualified_name,
                                          before_oid: master.sha, after_oid: merge_commit.sha)
        config = status_checks_policy_config([RequiredStatusCheck.new(context: "a context")], strict: false)
        decisions = RuleEngine::StatusCheckEvaluator.evaluate(repository: @repo, ref_update: ref_update, rule_configs: [config])
        decision = T.must(decisions[config])
        check_decision = T.must(decision.status_check_results.first&.last)

        refute decision.rules_fulfilled?, "check passed: #{decision}"
        assert_equal failure_status, check_decision.reason_check
      end

      test "pending status on topic branch => update denied" do
        master = @repo.refs.find("master")
        topic = @repo.refs.create("refs/heads/topic", master.target_oid, @owner)

        create_commit(topic, @owner, "new-file.txt")
        merge_commit = create_merge_commit(@repo, @owner, topic.name)

        pending_status = create :status, repository: @repo, creator: @owner, sha: topic.sha, context: "a context", state: "pending"
        @protected_branch.required_status_checks.create! context: "a context"

        ref_update = create_branch_update(@repo,
                                          name: @protected_branch.qualified_name,
                                          before_oid: master.sha, after_oid: merge_commit.sha)
        config = status_checks_policy_config([RequiredStatusCheck.new(context: "a context")], strict: false)
        decisions = RuleEngine::StatusCheckEvaluator.evaluate(repository: @repo, ref_update: ref_update, rule_configs: [config])
        decision = T.must(decisions[config])
        check_decision = T.must(decision.status_check_results.first&.last)

        refute decision.rules_fulfilled?, "check passed: #{decision}"
        assert_equal pending_status, check_decision.reason_check
      end

      test "commit with same tree OID has failure status" do
        master = @repo.refs.find("master")
        topic = @repo.refs.create("refs/heads/topic", master.target_oid, @owner)
        create_commit(topic, @owner, "new-file.txt")
        another_topic = @repo.refs.create("refs/heads/another-topic", master.target_oid, @owner)
        create_commit(another_topic, @owner, "new-file.txt")

        assert_equal topic.target.tree_oid, another_topic.target.tree_oid

        merge_commit = create_merge_commit(@repo, @owner, topic.name)

        create :status, repository: @repo, creator: @owner, sha: another_topic.sha, context: "a context", state: "success"
        @protected_branch.required_status_checks.create! context: "a context"

        ref_update = create_branch_update(@repo,
                                          name: @protected_branch.qualified_name,
                                          before_oid: master.sha, after_oid: merge_commit.sha)
        config = status_checks_policy_config([RequiredStatusCheck.new(context: "a context")], strict: false)
        decisions = RuleEngine::StatusCheckEvaluator.evaluate(repository: @repo, ref_update: ref_update, rule_configs: [config])
        decision = T.must(decisions[config])
        check_decision = T.must(decision.status_check_results.first&.last)

        refute decision.rules_fulfilled?, "check passed: #{decision}"
        assert_equal "a context", check_decision.reason_check.context
        assert_equal "expected", check_decision.reason_check.state
      end
    end

    context "topic branch is out-of-date with master" do
      test "no status yet => expected status" do
        master = @repo.refs.find("master")
        topic = @repo.refs.create("refs/heads/topic", master.target_oid, @owner)

        create_commit(topic, @owner, "new-file.txt")
        create_commit(master, @owner, "another-new-file.txt")
        merge_commit = create_merge_commit(@repo, @owner, topic.name)

        @protected_branch.required_status_checks.create! context: "a context"

        ref_update = create_branch_update(@repo,
                                          name: @protected_branch.qualified_name,
                                          before_oid: master.sha, after_oid: merge_commit.sha)
        config = status_checks_policy_config([RequiredStatusCheck.new(context: "a context")], strict: false)
        decisions = RuleEngine::StatusCheckEvaluator.evaluate(repository: @repo, ref_update: ref_update, rule_configs: [config])
        decision = T.must(decisions[config])
        check_decision = T.must(decision.status_check_results.first&.last)

        refute decision.rules_fulfilled?, "check passed: #{decision}"
        assert_equal "a context", check_decision.reason_check.context
        assert_equal "expected", check_decision.reason_check.state
      end

      test "success status on topic branch => update allowed" do
        master = @repo.refs.find("master")
        topic = @repo.refs.create("refs/heads/topic", master.target_oid, @owner)

        create_commit(topic, @owner, "new-file.txt")
        create_commit(master, @owner, "another-new-file.txt")
        merge_commit = create_merge_commit(@repo, @owner, topic.name)

        create :status, repository: @repo, creator: @owner, sha: topic.sha, context: "a context", state: "failure"
        success = create :status, repository: @repo, creator: @owner, sha: topic.sha, context: "a context", state: "success"
        @protected_branch.required_status_checks.create! context: "a context"

        ref_update = create_branch_update(@repo,
                                          name: @protected_branch.qualified_name,
                                          before_oid: master.sha, after_oid: merge_commit.sha)
        config = status_checks_policy_config([RequiredStatusCheck.new(context: "a context")], strict: false)
        decisions = RuleEngine::StatusCheckEvaluator.evaluate(repository: @repo, ref_update: ref_update, rule_configs: [config])
        decision = T.must(decisions[config])
        check_decision = T.must(decision.status_check_results.first&.last)

        assert decision.rules_fulfilled?, "check failed: #{decision}"
        assert_equal success, check_decision.reason_check
      end

      test "failure status on master branch => update allowed" do
        master = @repo.refs.find("master")
        topic = @repo.refs.create("refs/heads/topic", master.target_oid, @owner)

        create_commit(topic, @owner, "new-file.txt")
        create_commit(master, @owner, "another-new-file.txt")
        merge_commit = create_merge_commit(@repo, @owner, topic.name)

        success = create :status, repository: @repo, creator: @owner, sha: topic.sha, context: "a context", state: "success"
        create :status, repository: @repo, creator: @owner, sha: master.sha, context: "a context", state: "failure"
        @protected_branch.required_status_checks.create! context: "a context"

        ref_update = create_branch_update(@repo,
                                          name: @protected_branch.qualified_name,
                                          before_oid: master.sha, after_oid: merge_commit.sha)
        config = status_checks_policy_config([RequiredStatusCheck.new(context: "a context")], strict: false)
        decisions = RuleEngine::StatusCheckEvaluator.evaluate(repository: @repo, ref_update: ref_update, rule_configs: [config])
        decision = T.must(decisions[config])
        check_decision = T.must(decision.status_check_results.first&.last)

        assert decision.rules_fulfilled?, "check failed: #{decision}"
        assert_equal success, check_decision.reason_check
      end

      test "failure status on topic branch => update denied" do
        master = @repo.refs.find("master")
        topic = @repo.refs.create("refs/heads/topic", master.target_oid, @owner)

        create_commit(topic, @owner, "new-file.txt")
        create_commit(master, @owner, "another-new-file.txt")
        merge_commit = create_merge_commit(@repo, @owner, topic.name)

        failure_status = create :status, repository: @repo, creator: @owner, sha: topic.sha, context: "a context", state: "failure"
        @protected_branch.required_status_checks.create! context: "a context"

        ref_update = create_branch_update(@repo,
                                          name: @protected_branch.qualified_name,
                                          before_oid: master.sha, after_oid: merge_commit.sha)
        config = status_checks_policy_config([RequiredStatusCheck.new(context: "a context")], strict: false)
        decisions = RuleEngine::StatusCheckEvaluator.evaluate(repository: @repo, ref_update: ref_update, rule_configs: [config])
        decision = T.must(decisions[config])
        check_decision = T.must(decision.status_check_results.first&.last)

        refute decision.rules_fulfilled?, "check passed: #{decision}"
        assert_equal failure_status, check_decision.reason_check
      end

      test "pending status on topic branch => update denied" do
        master = @repo.refs.find("master")
        topic = @repo.refs.create("refs/heads/topic", master.target_oid, @owner)

        create_commit(topic, @owner, "new-file.txt")
        create_commit(master, @owner, "another-new-file.txt")
        merge_commit = create_merge_commit(@repo, @owner, topic.name)

        pending_status = create :status, repository: @repo, creator: @owner, sha: topic.sha, context: "a context", state: "pending"

        @protected_branch.required_status_checks.create! context: "a context"

        ref_update = create_branch_update(@repo,
                                          name: @protected_branch.qualified_name,
                                          before_oid: master.sha, after_oid: merge_commit.sha)
        config = status_checks_policy_config([RequiredStatusCheck.new(context: "a context")], strict: false)
        decisions = RuleEngine::StatusCheckEvaluator.evaluate(repository: @repo, ref_update: ref_update, rule_configs: [config])
        decision = T.must(decisions[config])
        check_decision = T.must(decision.status_check_results.first&.last)

        refute decision.rules_fulfilled?, "check passed: #{decision}"
        assert_equal pending_status, check_decision.reason_check
      end
    end

    context "mutli context case" do
      test "succeeds when the most recent two check runs are a success, and are from the required integration" do
        integration = create(:integration)
        check_suite = create :check_suite, repository: @repo, github_app: integration, head_sha: @repo.refs["master"].sha
        check1 = create :check_run, :completed, :success, repository: @repo, creator: integration.bot, check_suite: check_suite, display_name: "context1", completed_at: 3.seconds.ago
        check2 = create :check_run, :completed, :success, repository: @repo, creator: integration.bot, check_suite: check_suite, display_name: "context2", completed_at: 5.seconds.ago
        required_status_check1 = @protected_branch.required_status_checks.create! context: "context1", integration: integration
        required_status_check2 = @protected_branch.required_status_checks.create! context: "context2", integration: integration

        ref_update = create_branch_update(@repo,
                                          name: @protected_branch.qualified_name,
                                          before_oid: GitHub::NULL_OID, after_oid: @repo.refs["master"].sha)
        config = status_checks_policy_config([required_status_check1, required_status_check2], strict: true)
        decisions = RuleEngine::StatusCheckEvaluator.evaluate(repository: @repo, ref_update: ref_update, rule_configs: [config])
        decision = T.must(decisions[config])
        check_decisions = T.must(decision.status_check_results.values)

        assert decision.rules_fulfilled?, "check failed: #{decision}"
        assert_equal 2, check_decisions.size
        assert check_decisions.all?(&:success?)
        assert_same_elements([check1, check2], check_decisions.map { |d| T.cast(d.reason_check, CombinedStatus::CheckRunAdapter).__getobj__ })
      end

      test "fails when one of the two status checks are a failure" do
        integration = create(:integration)
        check_suite = create :check_suite, repository: @repo, github_app: integration, head_sha: @repo.refs["master"].sha
        create :check_run, :completed, :success, repository: @repo, creator: integration.bot, check_suite: check_suite, display_name: "context1", completed_at: 3.seconds.ago
        create :check_run, :completed, :failure, repository: @repo, creator: integration.bot, check_suite: check_suite, display_name: "context2", completed_at: 5.seconds.ago
        required_status_check1 = @protected_branch.required_status_checks.create! context: "context1", integration: integration
        required_status_check2 = @protected_branch.required_status_checks.create! context: "context2", integration: integration

        ref_update = create_branch_update(@repo,
                                          name: @protected_branch.qualified_name,
                                          before_oid: GitHub::NULL_OID, after_oid: @repo.refs["master"].sha)
        config = status_checks_policy_config([required_status_check1, required_status_check2], strict: true)
        decisions = RuleEngine::StatusCheckEvaluator.evaluate(repository: @repo, ref_update: ref_update, rule_configs: [config])
        decision = T.must(decisions[config])
        check_decisions = T.must(decision.status_check_results.values)

        assert_equal 1, decisions.size
        assert_equal 2, check_decisions.size
        assert_equal 1, check_decisions.count { |d| d.success? }
        assert_equal 1, check_decisions.count { |d| !d.success? }
      end
    end
  end

  context "multi-policy" do
    test "fails when the most recent status is failure" do
      @protected_branch.update!(name: "ma*")
      @protected_branch.required_status_checks.create! context: "a context"
      failure_status = create :status, repository: @repo, creator: @owner, sha: @repo.refs["master"].sha, context: "a context", state: "failure"

      # second policy
      pb2 = create(:protected_branch, repository: @repo, required_status_checks_enforcement_level: :non_admins)
      pb2.required_status_checks.create! context: "second context"
      success_status = create :status, repository: @repo, creator: @owner, sha: @repo.refs["master"].sha, context: "second context", state: "success"

      configs = [@protected_branch, pb2].map(&:required_status_checks_policy)

      ref_update = create_branch_update(@repo,
                                        name: "master",
                                        before_oid: GitHub::NULL_OID, after_oid: @repo.refs["master"].sha)
      decisions = RuleEngine::StatusCheckEvaluator.evaluate(repository: @repo, ref_update: ref_update, rule_configs: configs)

      pb1_decision = T.must(decisions[configs[0]])
      pb1_check_decision = T.must(pb1_decision.status_check_results.first&.last)
      refute pb1_decision.rules_fulfilled?
      assert_equal failure_status, pb1_check_decision.reason_check

      pb2_decision = T.must(decisions[configs[1]])
      pb2_check_decision = T.must(pb2_decision.status_check_results.first&.last)
      assert pb2_decision.rules_fulfilled?
      assert_equal success_status, pb2_check_decision.reason_check
    end
  end

  def create_commit(ref, owner, filename = nil)
    ref.append_commit({ message: "Commit on #{ref.name}",
                        committer: owner },
                      owner) do |files|
      files.add(filename, "New file") if filename
    end
  end

  def create_merge_commit(repo, owner, head_branch_name, base_branch_name = "master")
    repo.commits.create_merge_commit(owner, base_branch_name, head_branch_name).first
  end
end
