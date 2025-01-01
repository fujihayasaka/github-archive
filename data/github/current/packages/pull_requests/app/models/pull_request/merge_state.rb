# typed: true
# frozen_string_literal: true

# Whether or not a pull request can be merged, and whether or not the tests are passing.
class PullRequest::MergeState
  include GitHub::BatchMethod
  include GitHub::Memoizer

  class UnexpectedState < StandardError; end

  sig { returns(PullRequest) }
  attr_reader :pull

  attr_reader :viewer

  sig { returns(T.nilable(Symbol)) }
  attr_reader :merge_method

  sig { returns(T::Boolean) }
  attr_reader :skip_checks

  sig { params(pull: PullRequest, viewer: T.nilable(User), merge_method: T.nilable(Symbol), skip_checks: T::Boolean).void }
  def initialize(pull, viewer: nil, merge_method: nil, skip_checks: false)
    @pull   = pull
    @viewer = viewer
    @merge_method = merge_method
    @skip_checks = skip_checks
  end

  def mergeable
    pull.currently_mergeable?
  end

  def ready_for_auto_merge_job?
    clean? || unstable? || has_hooks? || unknown?
  end

  def draft?
    pull.draft?
  end

  def clean_status?
    combined_status = pull.combined_status
    return true unless combined_status.any?
    combined_status.green?
  end

  def has_pre_receive_hooks?
    pull.repository&.has_pre_receive_hooks?
  end

  def dirty_status?
    !clean_status?
  end

  def dirty?
    status == :dirty
  end

  def clean?
    status == :clean
  end

  def unstable?
    status == :unstable
  end

  def unknown?
    status == :unknown
  end

  def has_hooks?
    status == :has_hooks
  end

  def behind?
    status == :behind
  end

  def has_unverified_email?
    return false unless viewer
    repo = pull.repository
    authorization = ContentAuthorizer.authorize(viewer, :pull_request, :merge, repo: repo, owner: T.must(repo).owner)
    !authorization.authorized?
  end

  def admin_override_possible?
    if draft?
      false
    elsif blocked_by_base_branch_locked_for_merge_queue?
      false
    ##
    # If the required linear history rule is configured in a non-bypassable ruleset, we must exclude any rules attached to
    # bypassable rulesets to ensure the merge box is able to render the bypass checkbox and the squash/rebase options.
    elsif %i(blocked behind).include?(status) && (can_update_ref? || (merge_method != :merge && blocked_only_by_required_linear_history?(exclude_bypassable_rules: true)))
      true
    elsif mergeable && viewer && protected_branch_policy_unfulfilled? &&
        overrideable_rule_type? && can_update_ref?
      true
    else
      false
    end
  end

  def status
    start_time = GitHub::Dogstats.monotonic_time
    result = async_status.sync
  ensure
    GitHub.dogstats.distribution_timing_since(
      "pull_request.merge_state.status.duration",
      start_time,
      tags: [
        "from:#{GitHub.context[:from]}",
        "method:#{GitHub.context[:method] || GitHub.context[:request_method]}",
        "pull_merged:#{pull.merged?}",
        "status_memoized:#{!defined?(@async_status).nil?}",
        "result:#{result}",
        "resolves_early:#{mergeable == false || mergeable.nil? || has_unverified_email?}",
        "viewer_truthy:#{!!viewer}",
      ]
    )
  end

  def async_status
    @async_status ||= begin
      return Promise.resolve(:dirty) if mergeable == false
      return Promise.resolve(:unknown) if mergeable.nil?
      return Promise.resolve(:blocked) if has_unverified_email?

      Promise.all([pull.async_historical_comparison, async_base_branch_rule_evaluator, pull.async_repository]).then do |_, rule_evaluator, repository|
        (viewer && rule_evaluator.present? ? async_batch_rules_engine_evaluation_result : Promise.resolve(nil)).then do
          if viewer && protected_branch_policy_unfulfilled?
            async_merge_queue_deploy_then_merge?.then do |merge_queue_deploy_then_merge_enabled|
              failed_rule_types = rules_engine_evaluation_result.failed_rule_types
              registered_rules = MergeConditions::PullRequestRules.get_rules_to_consider(repository, merge_queue_deploy_then_merge_enabled, merge_method, skip_checks)

              case
              when failed_rule_types.include?("required_status_checks")
                if loose_policy? || up_to_date?
                  :blocked
                else
                  :behind
                end
              when (failed_rule_types & registered_rules).any?
                :blocked
              when rules_engine_evaluation_result.git_error?
                :unknown
              when failed_rule_types.include?("merge_queue")
                if blocked_by_invalid_merge_queue_config?
                  :blocked
                else
                  # :merge_queue is enforced at merge time so treat this as though there is no policy violation.
                  protected_branch_policy_fulfilled_status
                end
              when failed_rule_types.include?("required_linear_history")
                # :merge_commit is enforced at merge time so treat this as though there is no policy violation.
                protected_branch_policy_fulfilled_status
              when merge_method == :squash && (failed_rule_types & RuleEngine::Evaluator::COMMIT_METADATA_RULE_TYPES).any?
                protected_branch_policy_fulfilled_status
              else
                report_unexpected_state
                :blocked
              end
            end
          elsif blocked_by_base_branch_locked_for_merge_queue?
            :blocked
          else
            protected_branch_policy_fulfilled_status
          end
        end
      end
    end
  end

  def protected_branch_policy_fulfilled_status
    if pull.action_required_check_suites(head_sha: pull.head_sha).any?
      :unstable
    elsif dirty_status?
      :unstable
    elsif has_pre_receive_hooks?
      :has_hooks
    elsif clean_status?
      :clean
    end
  end

  # Public: Is the merge of this PR blocked by the pull request review policy?
  def blocked_by_review_policy?
    return false if in_merge_queue?
    return false unless T.must(pull.repository).plan_supports?(:protected_branches)

    viewer && review_policy_unfulfilled?
  end

  def blocked_by_non_overridable_non_review_policy?
    # True when
    # 1. A non-overrideable reason code is present that is not a review policy
    # 2. The review policy can be overridden
    rules_engine_evaluation_result.can_bypass_rule_type?("pull_request") &&
    !rules_engine_evaluation_result.rules_fulfilled? &&
      !(rules_engine_evaluation_result.failed_rule_types - ["pull_request"]).empty? &&
      !rules_engine_evaluation_result.action_permitted?
  end

  def in_merge_queue?
    pull.merge_queue_enabled? && pull.in_merge_queue?
  end

  # Public: Is the merge of this PR blocked by the required signatures policy?
  def blocked_by_required_signatures?
    rules_engine_evaluation_result.rule_type_failed?("required_signatures")
  end

  def blocked_by_lock_branch?
    rules_engine_evaluation_result.rule_type_failed?("lock_branch")
  end

  def blocked_by_update_branch?
    rules_engine_evaluation_result.rule_type_failed?("update")
  end

  # Public: Is the merge of this PR blocked by protected branch authorized users/teams?
  def blocked_by_unauthorized_protection?
    rules_engine_evaluation_result.rule_type_failed?("authorization")
  end

  # Public: Is the merge of this PR blocked only by required linear history of the base branch?
  def blocked_only_by_required_linear_history?(exclude_bypassable_rules: false)
    failed_rule_types = rules_engine_evaluation_result.failed_rule_types

    if exclude_bypassable_rules
      failed_rule_types = failed_rule_types.reject { |rule_type| rules_engine_evaluation_result.can_bypass_rule_type?(rule_type) }
    end

    failed_rule_types == ["required_linear_history"]
  end

  def blocked_by_required_deployments?
    return false if async_merge_queue_deploy_then_merge?.sync
    rules_engine_evaluation_result.rule_type_failed?("required_deployments")
  end

  def blocked_by_required_review_thread_resolution?
    return false if in_merge_queue?
    return true if pull_request_review_policy_decision.thread_resolution_required?

    rules_engine_evaluation_result.rule_type_failed?("required_review_thread_resolution")
  end

  def blocked_by_status_checks?
    rules_engine_evaluation_result.rule_type_failed?("required_status_checks")
  end

  def blocked_by_status_check_integrations?
    rule_runs = rules_engine_evaluation_result.runs_by_rule_type("required_status_checks")
    rule_runs.any? { |run| run.reason_code == :required_status_check_integrations && run.failed? }
  end

  def blocked_by_status_check_integrations_message
    rule_runs = rules_engine_evaluation_result.runs_by_rule_type("required_status_checks")
    failed_run = rule_runs.find { |run| run.reason_code == :required_status_check_integrations && run.failed? }
    failed_run&.message
  end

  def blocked_by_rules_message
    ignored_rules = MergeConditions::PullRequestRules::PULL_REQUEST_MERGEABILITY_IGNORE_RULE_TYPES.dup
    if async_merge_queue_deploy_then_merge?.sync
      ignored_rules << "required_deployments"
    end

    failed_run = rules_engine_evaluation_result.rule_runs.reject do |run|
      ignored_rules.include?(run.rule_type)
    end.find(&:failed?)
    # Temporary workaround for complex error messages (i.e. file path)
    # TODO: Remove this once we have a better way to display simple error messages
    failed_run&.message&.split("\n")&.first
  end

  def blocked_by_base_branch_locked_for_merge_queue?
    return @blocked_by_base_branch_locked_for_merge_queue unless @blocked_by_base_branch_locked_for_merge_queue.nil?
    @blocked_by_base_branch_locked_for_merge_queue = @pull.branch_locked_for_merge_queue?
  end

  def blocked_by_workflow_updates?
    viewer && rules_engine_evaluation_result.rule_type_failed?("workflow_updates")
  end

  def blocked_by_workflow_updates_message
    rule_runs = rules_engine_evaluation_result.runs_by_rule_type("workflow_updates")
    failed_run = rule_runs.find { |run| run.reason_code == :workflow_updates && run.failed? }
    failed_run&.message
  end

  def blocked_by_invalid_merge_queue_config?
    rule_runs = rules_engine_evaluation_result.runs_by_rule_type("merge_queue")
    rule_runs.any? { |run| run.evaluation_metadata["duplicate_merge_queue"] && run.failed? }
  end

  sig { returns T.nilable(String) }
  def blocked_by_invalid_merge_queue_config_message
    rule_runs = rules_engine_evaluation_result.runs_by_rule_type("merge_queue")
    failed_run = rule_runs.find { |run| run.evaluation_metadata["duplicate_merge_queue"] && run.failed? }
    failed_run&.message
  end

  # Public: Can a user merge this PullRequest into the head_ref?
  # This takes into account various policy decision around protected branches,
  # admin overrides, etc.  See RuleEngine::Evaluator for details.
  #
  # Returns a Boolean
  def can_update_ref?
    result = rules_engine_evaluation_result
    return false if result.nil?

    result.action_permitted?
  end

  # Public: Return the RuleSuite for the current viewer for this Merge State
  #
  # If there is not a valid merge commit, this will return a RuleSuite with rules_unfulfilled and result of :git_error
  #
  # Returns a RuleEngine::RuleSuite
  batch_method(:rules_engine_evaluation_result, RuleEngine::RuleSuite) do |merge_states|
    merge_states = T.cast(merge_states, T::Enumerable[PullRequest::MergeState])

    merge_states.group_by { |s| [s.pull.repository, s.viewer] }.map do |repo_and_viewer, merge_states|
      repo, viewer = repo_and_viewer
      ref_updates_by_state = merge_states.to_h do |merge_state|
        [merge_state, merge_state.ref_update_for_merge[0]]
      end

      valid = ref_updates_by_state.filter_map { |ms, ref_update| [ms, ref_update] if !ref_update.blank? }.to_h
      suites = RuleEngine::Evaluator.evaluate_rules(T.must(repo), valid.values, viewer, dry_run: true)

      ref_updates_by_state.transform_values do |ref_update|
        suite = suites.find { |s| s.ref_update == ref_update }
        suite || RuleEngine::RuleSuite.object_missing(T.must(repo), viewer)
      end
    end.reduce(T.let({}, T::Hash[PullRequest::MergeState, RuleEngine::RuleSuite])) { |a, b| a.merge(b) }
  end

  # Public: The PullRequestReviewRule for the current actor (ie viewer)
  # for this Pull Request
  #
  # Returns a PullRequestReviewRule::Decision
  def pull_request_review_policy_decision
    async_pull_request_review_policy_decision.sync
  end

  def async_pull_request_review_policy_decision
    return Promise.resolve(@pull_request_review_policy_decision) if defined?(@pull_request_review_policy_decision)

    ref_update = ref_update_for_merge[0].presence || Git::Ref::Update::Null.create_for_merge_conflict(pull)
    async_base_branch_rule_evaluator.then do |base_branch_rule_evaluator|
      RuleEngine::PullRequestReviewRule.async_check_pull_request(pull_request: pull, actor: viewer, ref_update: ref_update, policy_evaluator: base_branch_rule_evaluator)
      .then { |value| @pull_request_review_policy_decision = value }
    end
  end

  # Public: Return all the enforced PullRequestReview involved in determining the
  # protected branch decision.
  #
  # Returns a collection of PullRequestReview
  def reviews
    pull_request_review_policy_decision.reviews
  end

  def requested_changes?
    pull_request_review_policy_decision.instrumentation_payload[:has_requested_changes]
  end

  def required_approving_review_count
    base_branch_rule_evaluator&.required_approving_review_count
  end

  def review_policy_decision_reason_summary
    review_policy_decision_reason&.summary
  end

  def review_policy_decision_reason_message
    review_policy_decision_reason&.message
  end

  def unfulfilled_protected_branch_policy_reason_codes
    return [] unless protected_branch_policy_unfulfilled?
    rules_engine_evaluation_result.legacy_reason_codes
  end

  sig { returns([T.nilable(Git::Branch::Update), T::Array[String]]) }
  def ref_update_for_merge
    return [@ref_update_for_merge, []] if defined?(@ref_update_for_merge)
    merge_errors = check_pull_for_merge_errors
    @ref_update_for_merge = build_ref_update_for_merge if merge_errors.empty?
    [@ref_update_for_merge, merge_errors]
  end

  private

  # Allows for clearer error messages
  def check_pull_for_merge_errors
    merge_errors = []
    # Branch has been deleted, so we can't merge
    merge_errors << "Missing base branch, cannot merge" if pull.current_base_sha.blank?
    # Merge commit hasn't been built, so we can't merge yet.
    merge_errors << "Missing merge commit, cannot merge" if pull.merge_commit_sha.blank?
    merge_errors
  end

  # Setup the RefUpdate for the merge commit
  def build_ref_update_for_merge
    refname    = "refs/heads/#{pull.base_ref_name}"
    before_oid = pull.current_base_sha
    after_oid  = pull.merge_commit_sha

    Git::Branch::Update.new(repository: pull.repository, refname: refname,
                         before_oid: before_oid, after_oid: after_oid, pull_request: pull, merge_method:)
  end

  def protected_branch_policy_unfulfilled?
    return false if base_branch_rule_evaluator.blank?
    !rules_engine_evaluation_result.rules_fulfilled?
  end

  def up_to_date?
    !pull.behind_base?
  end

  def loose_policy?
    !base_branch_rule_evaluator&.strict_required_status_checks_policy?
  end

  def review_policy_decision_reason
    pull_request_review_policy_decision.reason
  end

  def review_policy_not_satisfied_decision_reason
    decision_reason = review_policy_decision_reason
    decision_reason if decision_reason.code == :review_policy_not_satisfied
  end

  def review_policy_unfulfilled?
    review_policy_not_satisfied_decision_reason.present?
  end

  def report_unexpected_state
    boom = UnexpectedState.new("Protected branch policy failed for unexpected reasons")
    boom.set_backtrace(caller.join("\n"))
    Failbot.push_sensitive("gh.protected_branch_policy.rules_engine_evaluation.failed_result": rules_engine_evaluation_result.failed_rule_types.inspect) do
      Failbot.report_trace(boom, "gh.pull_request.id": pull.id)
    end
  end

  sig { returns(T.nilable(BranchRuleEvaluator)) }
  def base_branch_rule_evaluator
    pull.base_branch_rule_evaluator
  end

  sig { returns(Promise[T.nilable(BranchRuleEvaluator)]) }
  def async_base_branch_rule_evaluator
    pull.async_batch_base_branch_rule_evaluator
  end

  # an admin can override these and merge directly
  def overrideable_rule_type?
    failed_types = rules_engine_evaluation_result.failed_rule_types
    # overrideable if the only failing rules are :required_linear_history or :merge_queue
    !failed_types.empty? && (failed_types - %w[required_linear_history merge_queue merge_queue_locked_ref]).empty?
  end

  sig { returns(Promise[T::Boolean]) }
  memoize def async_merge_queue_deploy_then_merge?
    async_base_branch_rule_evaluator.then do |evaluator|
      next false if evaluator.blank?
      next false unless evaluator.merge_queue_enabled?

      pull.async_merge_queue.then do |merge_queue|
        next false unless merge_queue.present?
        merge_queue.async_actor_controlled_merging?
      end
    end
  end
end
