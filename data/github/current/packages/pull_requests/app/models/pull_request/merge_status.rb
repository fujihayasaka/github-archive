# typed: true
# frozen_string_literal: true

class PullRequest::MergeStatus < CombinedStatus
  attr_reader :target_branch

  def initialize(repo, sha, target_branch:, target_policy_evaluator: nil, **kwargs)
    @target_branch = target_branch
    @target_policy_evaluator = target_policy_evaluator if target_policy_evaluator

    unless target_branch.is_a?(String)
      raise ArgumentError, "PR combined status missing target branch"
    end

    super(repo, sha, **kwargs)
  end

  def self.merge_statuses_for_pulls(repo, pulls, with_check_runs: false, current_user: nil)
    current_by_sha = Statuses.domain.current_statuses_for_shas_group_by(repository_id: repo.id, shas: pulls.map(&:head_sha).compact, group_by: Statuses::Domain::GroupByField::SHA)

    policy_evaluators = pulls.map(&:base_branch_rule_evaluator).compact
    combined_statuses = {}
    check_runs_by_sha = {}

    if with_check_runs
      check_runs_by_sha = fetch_pulls_check_runs(repo, pulls, current_user)
    end

    pulls.each do |pull|
      sha = pull.head_sha
      next unless sha

      statuses_for_sha = current_by_sha.fetch(sha, [])
      check_runs_for_sha = check_runs_by_sha.fetch(sha, nil)
      target_policy_evaluator = policy_evaluators.find do |policy_evaluator|
        policy_evaluator.matches?(pull.base_ref_name)
      end

      combined_statuses[sha] = new(repo, sha,
        statuses: statuses_for_sha,
        check_runs: check_runs_for_sha,
        target_branch: pull.base_ref_name,
        target_policy_evaluator: target_policy_evaluator
      )
    end
    combined_statuses
  end

  def self.fetch_pulls_check_runs(repo, pulls, current_user)
    Checks.domain.check_runs.latest_for_shas(pulls.map(&:head_sha).uniq, repository_id: repo.id)
  end

  # Are there any pending/expected statuses?
  #
  # Returns Boolean
  def incomplete?
    statuses.any? { |status| %w[pending expected].include?(status.state) }
  end

  # Return the latest status for each context for the repository with expected
  # statuses. See CombinedStatus#status_checks.
  #
  # Returns an Array of Statuses
  def status_checks
    @pr_memoized_statuses ||= prepend_expected_statuses(super)
  end

  private

  # Internal: Prepend any branch status policy expected statuses to a list of
  # statuses. If an expected context already has a status created, we'll omit
  # the expected status.
  #
  # statuses - Array of Statuses
  #
  # Returns an Array of Statuses.
  def prepend_expected_statuses(statuses)
    if evaluator = target_branch_policy_evaluator
      current_statuses_with_expected = evaluator.current_statuses_with_expected(statuses)
      required_workflow_statuses = evaluator.required_workflow_statuses(sha:, include_optional: true)

      return current_statuses_with_expected if required_workflow_statuses.none?

      if required_workflow_statuses.any?
        required_workflow_status_check_suites = required_workflow_statuses.map(&:check_suite).compact.map(&:id)
        current_statuses_with_expected.reject! do |status|
          status.class == CombinedStatus::CheckRunAdapter && required_workflow_status_check_suites.include?(status.check_suite_id)
        end
      end

      current_statuses_with_expected + required_workflow_statuses
    else
      statuses
    end
  end

  sig { returns(T.nilable(BranchRuleEvaluator)) }
  def target_branch_policy_evaluator
    return @target_policy_evaluator if defined?(@target_policy_evaluator)

    @target_policy_evaluator = BranchRuleEvaluator.for_repository_with_branch_name(repository, target_branch)
  end
end
