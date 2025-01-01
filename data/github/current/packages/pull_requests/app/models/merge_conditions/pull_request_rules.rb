# typed: true
# frozen_string_literal: true

class MergeConditions::PullRequestRules < MergeConditions::BaseMergeCondition
  include GitHub::Memoizer

  sig { returns(T.nilable(RuleEngine::RuleSuite)) }
  attr_accessor :rule_suite

  def display_name
    "Repo rules"
  end

  def description
    "Pull request repository rules"
  end

  def message
    if evaluation_result.errors.any?
      rule_suite&.message
    else
      nil
    end
  end

  def async_condition
    Promise.all([
      async_merge_queue_deploy_then_merge?,
      async_rules_engine_evaluation_result
    ]).then do |merge_queue_deploy_then_merge, rule_suite|
      self.rule_suite = rule_suite
      failed_rule_types = rule_suite.failed_rule_types
      registered_rules = get_rules_to_consider(merge_queue_deploy_then_merge)

      if (failed_rule_types & registered_rules).any?
        evaluation_result.errors << rule_suite.message
      end
    end
  end

  sig { override.returns(T.any(PullRequests::PageData::MergeBox::MergeRequirementsPayload::MergeConditionPayload, PullRequests::PageData::MergeBox::MergeRequirementsPayload::ConflictMergeConditionPayload)) }
  def condition_payload
    payload = super
    payload.ruleRollups = async_rule_rollups.sync.map(&:payload)

    payload
  end

  sig { returns(Promise[T::Array[RulesEngine::RepositoryRuleRollup]]) }
  def async_rule_rollups
    async_merge_queue_deploy_then_merge?.then do |merge_queue_deploy_then_merge|
      rules_to_consider = get_rules_to_consider(merge_queue_deploy_then_merge)
      T.must(rule_suite).rule_runs
              .map(&:rule_type)
              .uniq
              .filter { |rule_type| rules_to_consider.include?(rule_type) }
              .map    { |rule_type| RulesEngine::RepositoryRuleRollup.new(T.must(rule_suite), rule_type) }
    end
  end

  # returns the list of rules minus any rules that shouldn't be considered for PR mergeability
  def get_rules_to_consider(merge_queue_deploy_then_merge)
    registered_rules = RuleEngine::Evaluator::REGISTERED_RULES.keys
    registered_rules -= PullRequest::MergeState::PULL_REQUEST_MERGEABILITY_IGNORE_RULE_TYPES

    # Merge-Then-Deploy configured Merge Queues utilize required deployments, but those deployments
    # won't happen to the PR's head_ref/sha. This branch protection rule is enforced at merge time,
    # which happens within the merge queue with a different git ref.
    if merge_queue_deploy_then_merge
      registered_rules -= %w[required_deployments]
    end

    registered_rules
  end

  memoize def async_merge_queue_deploy_then_merge?
    pull_request.async_merge_queue_enabled?.then do |merge_queue_enabled|
      next false unless merge_queue_enabled

      pull_request.async_merge_queue.then do |merge_queue|
        next false unless merge_queue.present?
        merge_queue.async_actor_controlled_merging?
      end
    end
  end

  memoize def async_rules_engine_evaluation_result
    Promise.all([pull_request.async_repository,
                pull_request.async_base_repository,
                pull_request.async_head_repository
    ]).then do |repositories|
      networks = repositories.compact.map(&:async_network)
      users = [pull_request.async_base_user, pull_request.async_head_user, pull_request.async_user]
      Promise.all(networks + users).then do
        pull_request.merge_state(viewer: user).async_batch_rules_engine_evaluation_result
      end
    end
  end
end
