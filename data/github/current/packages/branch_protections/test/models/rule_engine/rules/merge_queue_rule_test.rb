# typed: true
# frozen_string_literal: true

require "test_helper"

class MergeQueueRuleTest < GitHub::TestCase
  include RulesEngine::RefUpdateTestHelper

  fixtures do
    @user = create(:user)
    @org = create(:organization, admin: @user, plan: "business_plus")
    @repo = create(:repository, owner: @org)
  end

  setup do
    @ref_update = create_branch_update(@repo, name: "main")
    @context = RuleEngine::RuleEvaluationContext.new(@repo, @user)
    @rule = RuleEngine::Rules::MergeQueueRule.new
    @parameter_schema = RuleEngine::Evaluator.rule_impl_for_rule_type("merge_queue")&.parameter_schema
  end

  context "evaluation" do
    test "fails when duplicate merge queues configurations are present" do
      GitHub.flipper[:block_multiple_mq_configs].enable

      @mq1 = build(:repository_rule_configuration, rule_type: "merge_queue")
      @mq2 = build(:repository_rule_configuration, rule_type: "merge_queue")

      result = @rule.evaluate(@context, @ref_update, [@mq1, @mq2])

      assert_equal 2, result.size
      assert result.all? { |r| r.failed? && r.evaluation_metadata["duplicate_merge_queue"] }
    end
  end

  context ".label_for_merge_method" do
    test "produces a unique label for each valid merge method" do
      values = MergeQueues::IConfiguration::MergeMethod.values
      labels = values.map do |merge_method|
        RuleEngine::Rules::MergeQueueRule::Configuration.label_for_merge_method(merge_method)
      end

      assert_equal(values.count, labels.uniq.count)
    end

    test "produces labels that can be transalted back to merge methods" do
      MergeQueues::IConfiguration::MergeMethod.values.each do |merge_method|
        label = RuleEngine::Rules::MergeQueueRule::Configuration.label_for_merge_method(merge_method)
        assert_equal(
          merge_method,
          RuleEngine::Rules::MergeQueueRule::Configuration.merge_method_for_label(label),
        )
      end
    end
  end

  context "#max_wait_for_min_merge_entries_size" do
    test "prefers the higher number when there are multiple configs" do
      config = build_config([
        { min_entries_to_merge_wait_minutes: 3 },
        { min_entries_to_merge_wait_minutes: 7 },
      ])

      assert_equal 7.minutes, config.max_wait_for_min_merge_entries_size
    end
  end

  context "#min_merge_entries_size" do
    test "prefers the higher number when there are multiple configs" do
      config = build_config([
        { min_entries_to_merge: 10 },
        { min_entries_to_merge: 6 },
      ])

      assert_equal 10, config.min_merge_entries_size
    end
  end

  context "#max_merge_entries_size" do
    test "prefers the lower number when there are multiple configs" do
      config = build_config([
        { max_entries_to_merge: 5 },
        { max_entries_to_merge: 6 },
      ])

      assert_equal 5, config.max_merge_entries_size
    end
  end

  context "#max_concurrency" do
    test "prefers the lower number when there are multiple configs" do
      config = build_config([
        { max_entries_to_build: 15 },
        { max_entries_to_build: 20 },
      ])

      assert_equal 15, config.max_concurrency
    end
  end

  context "#max_attempts" do
    test "prefers the lower number when there are multiple configs" do
      config = build_config([
        { check_run_retries_limit: 0 },
        { check_run_retries_limit: 1 },
      ])

      assert_equal 0, config.max_attempts
    end
  end

  context "#actor_controlled_merging" do
    test "is true if any configuration is true" do
      config = build_config([
        { actor_controlled_merging: false },
        { actor_controlled_merging: true },
      ])

      assert config.actor_controlled_merging
    end

    test "is false if all configurations are false" do
      config = build_config([
        { actor_controlled_merging: false },
        { actor_controlled_merging: false },
      ])

      refute config.actor_controlled_merging
    end
  end

  context "#check_response_timeout" do
    test "prefers the higher number when there are multiple configs" do
      config = build_config([
        { check_response_timeout_minutes: 30 },
        { check_response_timeout_minutes: 60 },
      ])

      assert_equal 60.minutes, config.check_response_timeout
    end
  end

  context "#grouping_strategy" do
    test "is AllGreen if any configuration requests AllGreen" do
      config = build_config([
        { grouping_stategy: "HEADGREEN" },
        { grouping_stategy: "ALLGREEN" },
      ])

      assert_equal MergeQueues::IConfiguration::GroupingStrategy::AllGreen, config.grouping_strategy
    end

    test "is HeadGreen if no configuration requests AllGreen" do
      config = build_config([
        { grouping_strategy: "HEADGREEN" },
        { grouping_strategy: "HEADGREEN" },
      ])

      assert_equal MergeQueues::IConfiguration::GroupingStrategy::HeadGreen, config.grouping_strategy
    end
  end

  context "#merge_method" do
    test "is Squash if any configuration requests Squash" do
      config = build_config([
        { merge_method: "MERGE" },
        { merge_method: "SQUASH" },
        { merge_method: "REBASE" }
      ])

      assert_equal MergeQueues::IConfiguration::MergeMethod::Squash, config.merge_method
    end

    test "is Rebase if any configuration requests Rebase but none requests Squash" do
      config = build_config([
        { merge_method: "MERGE" },
        { merge_method: "REBASE" }
      ])

      assert_equal MergeQueues::IConfiguration::MergeMethod::Rebase, config.merge_method
    end

    test "is Merge if no configurations request Rebase or Squash" do
      config = build_config([
        { merge_method: "MERGE" },
      ])

      assert_equal MergeQueues::IConfiguration::MergeMethod::Merge, config.merge_method
    end
  end

  context "wildcards" do
    test "fails validation for asterisk wildcard ref target" do
      ruleset = build(:repository_ruleset, source: @repo, rule_configurations: [
        build(:repository_rule_configuration, :merge_queue),
      ], conditions: [
        build(:repository_rule_condition, :targets_branch, branch_name: "refs/heads/*")
      ])

      assert_raises(ActiveRecord::RecordInvalid) { ruleset.save! }
      assert ruleset.rule_configurations.first.errors.full_messages.first.include?("Wildcard ref names are not supported when merge queue is enabled")
    end

    test "fails validation for question mark wildcard ref target" do
      ruleset = build(:repository_ruleset, source: @repo, rule_configurations: [
        build(:repository_rule_configuration, :merge_queue),
      ], conditions: [
        build(:repository_rule_condition, :targets_branch, branch_name: "refs/heads/?")
      ])

      assert_raises(ActiveRecord::RecordInvalid) { ruleset.save! }
      assert ruleset.rule_configurations.first.errors.full_messages.first.include?("Wildcard ref names are not supported when merge queue is enabled")
    end

    test "fails validation for ~ALL ref target" do
      ruleset = build(:repository_ruleset, source: @repo, rule_configurations: [
        build(:repository_rule_configuration, :merge_queue),
      ], conditions: [
        build(:repository_rule_condition, :targets_all_branches)
      ])

      assert_raises(ActiveRecord::RecordInvalid) { ruleset.save! }
      assert ruleset.rule_configurations.first.errors.full_messages.first.include?("Wildcard ref names are not supported when merge queue is enabled")
    end
  end

  private

  sig { params(configs: T::Array[T::Hash[Symbol, T.untyped]]).returns(RuleEngine::Rules::MergeQueueRule::Configuration) }
  def build_config(configs)
    RuleEngine::Rules::MergeQueueRule::Configuration.new(
      configs: configs.map do |parameters|
        build(
          :repository_rule_configuration,
          rule_type: "merge_queue",
          parameters:,
        )
      end,
      defaults: MergeQueues.default_configuration,
    )
  end
end
