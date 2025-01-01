# typed: true
# frozen_string_literal: true

# TODO: Rename to RefRuleState
# TODO: Inherit from RuleEngine::RuleState
class BranchRuleEvaluator
  include GitHub::BatchMethod
  include GitHub::Memoizer
  include Scientist
  extend RuleEngine::Timing

  sig { params(repository: Repository, user: T.untyped, branch_name: String).returns(Symbol) }
  def self.branch_commitability_status(repository, user, branch_name)
    return :blocked unless user
    return :allowed unless repository.supports_protected_branches?
    evaluator = for_repository_with_branch_name(repository, branch_name)
    return :allowed unless evaluator

    evaluator.commit_authorized_status(user)
  end

  # Returns the rule state for the given tag in the given repository.
  sig { params(repository: Repository, tag_name: String).returns(T.nilable(BranchRuleEvaluator)) }
  def self.for_repository_with_tag_name(repository, tag_name)
    return nil unless repository.supports_protected_branches?

    evaluator = BranchRuleEvaluator.new(repository, "refs/tags/#{tag_name}")
    evaluator if evaluator.rule_configs.any?
  end

  # Returns a promise that resolves to the protection for the given branch
  # name in the given repository.
  sig { params(repository: Repository, branch_name: String).returns(Promise[T.nilable(BranchRuleEvaluator)]) }
  def self.async_for_repository_with_branch_name(repository, branch_name)
    return Promise.resolve(T.let(nil, T.nilable(BranchRuleEvaluator))) unless repository.supports_protected_branches?

    evaluator = BranchRuleEvaluator.new(repository, "refs/heads/#{branch_name}")
    evaluator.async_batch_rule_configs.then do |rule_configs|
      evaluator if rule_configs.any?
    end
  end

  # Returns the protection for the given branch name in the given repository.
  sig { params(repository: Repository, branch_name: String).returns(T.nilable(BranchRuleEvaluator)) }
  def self.for_repository_with_branch_name(repository, branch_name)
    return nil unless repository.supports_protected_branches?

    evaluator = BranchRuleEvaluator.new(repository, "refs/heads/#{branch_name}")
    evaluator if evaluator.rule_configs.any?
  end

  # Returns a mapping of branch names to protections for the given repository and branch names.
  sig { params(repository: Repository, branch_names: T::Array[String]).returns(T::Hash[String, BranchRuleEvaluator]) }
  def self.for_repository_with_branch_names(repository, branch_names)
    evaluator_by_branch = branch_names.uniq.map do |branch_name|
      [branch_name, BranchRuleEvaluator.new(repository, "refs/heads/#{branch_name}")]
    end.to_h

    if FeatureFlag.vexi.enabled_or_raise?(:use_billing_locked_rather_than_disabled) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
      GitHub::PrefillAssociations.prefill_batch_method([repository], :plan_customer_disabled?)
    end
    GitHub::PrefillAssociations.prefill_batch_method(evaluator_by_branch.values, :rule_configs)

    evaluator_by_branch.select { |_, evaluator| evaluator.rule_configs.any? && repository.supports_protected_branches? }
  end

  include RuleEngine::Rules::AuthorizationRule::StatusMethods
  include RuleEngine::Rules::DeletionRule::StatusMethods
  include RuleEngine::Rules::LinearHistoryRule::StatusMethods
  include RuleEngine::Rules::NonFastForwardRule::StatusMethods
  include RuleEngine::Rules::MergeQueueRule::StatusMethods
  include RuleEngine::Rules::PullRequestRule::StatusMethods
  include RuleEngine::Rules::RequiredDeploymentsRule::StatusMethods
  include RuleEngine::Rules::RequiredSignaturesRule::StatusMethods
  include RuleEngine::Rules::RequiredStatusChecksRule::StatusMethods
  include RuleEngine::Rules::LockBranchRule::StatusMethods
  include RuleEngine::Rules::UpdateRule::StatusMethods
  include RuleEngine::Rules::WorkflowRule::StatusMethods
  include RuleEngine::Rules::CodeScanningRule::StatusMethods
  include RuleEngine::Rules::LicenseComplianceScanningRule::StatusMethods
  include RuleEngine::Rules::CopilotCodeReviewRule::StatusMethods
  include RuleEngine::Rules::CommitMessagePatternRule::StatusMethods

  sig { returns(Repository) }
  attr_reader :repository

  sig { returns(String) }
  attr_reader :ref_name

  sig { params(repository: Repository, ref_name: String).void }
  def initialize(repository, ref_name)
    @repository = repository
    @ref_name = ref_name
  end

  def branch?
    @ref_name.start_with?("refs/heads")
  end

  def tag?
    @ref_name.start_with?("refs/tags")
  end

  def unqualified_name
    return @ref_name.delete_prefix("refs/heads/") if branch?
    @ref_name.delete_prefix("refs/tags/") if tag?
  end

  batch_method(:rule_configs, T::Array[RepositoryRuleConfiguration]) do |rule_evaluators|
    trace_time("ref_rule_state.batch_rule_configs", span_attributes: { "gh.branch_protection_rule.ref_rule_state.ref_count" => rule_evaluators.size }) do
      rule_evaluators = T.cast(rule_evaluators, T::Array[BranchRuleEvaluator])
      rules_by_evaluator = Hash.new { |h, k| h[k] = [] }
      evaluators_by_repo = rule_evaluators.group_by(&:repository)

      evaluators_by_repo.each do |repo, evaluators|
        RuleEngine::Evaluator::RULE_PROVIDERS.each do |provider|
          next unless provider.is_a?(RuleEngine::RuleProviders::GitRuleProvider)
          rules = provider.rule_for_branch_evaluators(repo, evaluators.map(&:ref_name))
          rules.each do |rule|
            evaluators.each do |evaluator|
              if rule.matching_ref_names&.include?(evaluator.ref_name)
                rules_by_evaluator[evaluator] << rule
              end
            end
          end
        end
      end

      rules_by_evaluator
    end
  end

  sig { returns(T.nilable(ProtectedBranch)) }
  memoize def protected_branch
    rule_configs.find { |config| config.source.is_a?(ProtectedBranch) }&.source
  end
  alias_method :original_protected_branch, :protected_branch

  # Returns the ref rulesets that apply to this ref.
  # include_evalaute - If true, include rulesets that are in evaluate mode
  #
  # Returns array of RepositoryRuleset
  sig { params(include_evaluate: T::Boolean).returns(T::Array[RepositoryRuleset]) }
  def ref_rulesets(include_evaluate: false)
    rule_configs.filter_map do |config|
      config.repository_ruleset
    end.uniq.filter { |ruleset| include_evaluate || !ruleset.evaluate? }.filter { |ruleset| ruleset.targets_branch? || ruleset.targets_tag? }
  end

  sig { params(type: String, include_evaluate: T::Boolean).returns(T::Array[RepositoryRuleConfiguration]) }
  def configs_by_type(type, include_evaluate: false)
    rule_configs.select do |config|
      config.rule_type == type && (include_evaluate || !config.evaluate_mode?)
    end
  end

  sig { params(type: String, actor: T.untyped).returns(T::Array[RepositoryRuleConfiguration]) }
  def enforced_rules_by_type(type, actor)
    rule_configs.select do |config|
      config.rule_type == type && config.enabled? && !config.can_skip?(actor, targetable) && !config.can_bypass?(actor, targetable)
    end
  end

  def reload
    remove_instance_variable(:@protected_branch) if defined?(@protected_branch)
    clear_preloaded_batch_method_value(:rule_configs)
    rule_configs
  end

  def matches?(branch_name)
    return false if tag?

    if original_protected_branch.present?
      original_protected_branch&.matches?(branch_name)
    else
      # When a new required-workflow-status-check is created on a branch which does not have any other branch-protection rules.
      File.fnmatch?(unqualified_name, branch_name, File::FNM_PATHNAME)
    end
  end

  # === Methods defined here rely on multiple policies ===
  # TODO: Consider if these are necessary

  # Public: Can actor commit to this branch?
  #
  # actor - User, Bot or PublicKey
  #
  # Returns Boolean
  def commit_authorized?(actor)
    commit_authorized_status(actor) != :blocked
  end

  # Public: Can actor commit to this branch?
  #
  # actor - User, Bot or PublicKey
  #
  # Returns :blocked, :can_bypass, or :allowed
  sig { params(actor: T.untyped).returns(Symbol) }
  def commit_authorized_status(actor)
    return :blocked unless authorized?(actor)

    creating = !repository.refs.exist?(@ref_name)

    needs_bypass = T.let(false, T::Boolean)
    rule_configs.reject(&:evaluate_mode?).each do |config|
      rule_impl = config.evaluator
      next unless rule_impl.is_a?(RuleEngine::RefUpdateRule)
      next if creating && rule_impl.ignore_update_types(config).include?(:creation)

      if rule_impl.blocks_new_direct_commits?(config)
        next if config.can_skip?(actor, targetable)
        unless config.can_bypass?(actor, targetable)
          return :blocked
        end
        needs_bypass = true
      end
    end
    needs_bypass ? :can_bypass : :allowed
  end

  # This method is used solely by the GQL "viewer_can_merge_as_admin" field on PullRequest
  # It should probably be deprecated and replaced with something that actually performs rule evaluation and checks bypass
  def can_merge_as_admin?(actor:)
    return !merge_queue_enforced_for?(actor: actor) if merge_queue_enabled?

    admin_role = Role.admin_role
    GitHub::PrefillAssociations.prefill_associations(ref_rulesets, :bypass_actors)
    ruleset_admin_bypass = ref_rulesets.all? { |rs| rs.bypass_actors.any? { |bypass| bypass.actor_type == "RepositoryRole" && bypass.actor_id == admin_role.id } }
    protected_branch_bypass = original_protected_branch.nil? || !original_protected_branch&.admin_enforced?

    protected_branch_bypass && ruleset_admin_bypass && repository.async_adminable_by?(actor).sync
  end

  def blocks_deletes_for?(actor)
    block_deletions_enforced_for?(actor: actor) || lock_branch_enforced_for?(actor: actor)
  end

  def required_review_thread_resolution_enabled?
    configs_by_type("required_review_thread_resolution").any? || configs_by_type("pull_request").any? { |c| c.param("required_review_thread_resolution") }
  end

  ALL_MERGE_METHODS_ALLOWED = T.let({ merge: :allowed, squash: :allowed, rebase: :allowed }.freeze, T::Hash[Symbol, Symbol])

  # Returns hash of { merge methods => rule status }
  # Merge methods: merge, squash, rebase
  # Rule status: allowed, blocked, allowed_with_bypass
  sig { params(actor: T.nilable(User)).returns(T::Hash[Symbol, Symbol]) }
  def supported_merge_methods(actor: nil)
    merge_method_statuses = ALL_MERGE_METHODS_ALLOWED.dup

    if required_linear_history_enabled?
      merge_method_statuses[:merge] = (actor.nil? || required_linear_history_enforced_for?(actor:, is_pull_request: true)) ? :blocked : :allowed_with_bypass
    end

    configs_by_type("pull_request").each do |config|
      next if config.can_skip?(actor, targetable)

      denied_merge_methods = [:merge, :squash, :rebase] - config.param("allowed_merge_methods").map(&:to_sym)
      can_bypass = config.can_bypass?(actor, targetable)

      denied_merge_methods.each do |merge_method|
        next if merge_method_statuses[merge_method] == :blocked

        merge_method_statuses[merge_method] = can_bypass ? :allowed_with_bypass : :blocked
      end
    end

    merge_method_statuses
  end

  # Public: Default merge method for this protected branch
  #
  # Returns merge, rebase, or squash.
  def default_merge_method_for(actor)
    @merge_method_memo ||= {}
    @merge_method_memo[actor] ||= begin
      merge_method_statuses = supported_merge_methods(actor:)
      repo_merge_method_statuses = { merge: repository.merge_commit_allowed?, squash: repository.squash_merge_allowed?, rebase: repository.rebase_merge_allowed? }
      merge_method_statuses.keys.each do |merge_method|
        merge_method_statuses[merge_method] = :blocked unless repo_merge_method_statuses[merge_method]
      end

      default_method = repository.default_merge_method_for(actor)

      # sort prioritizing "allowed" and then the default_method set by the user
      merge_method_statuses.reject { |_, status| status == :blocked }
        .sort_by { |merge_method, status| [status == :allowed ? 0 : 1, merge_method == default_method ? 0 : 1] }
        .first&.first || :merge # fallback to :merge if everything is blocked
    end
  end

  sig { returns(RuleEngine::Conditions::Targets::Ref) }
  memoize def targetable
    RuleEngine::Conditions::Targets::Ref.new(repository:, ref_name: @ref_name)
  end
end
