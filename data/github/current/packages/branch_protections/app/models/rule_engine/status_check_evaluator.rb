# typed: true
# frozen_string_literal: true

module RuleEngine
  class StatusCheckEvaluator
    extend T::Sig

    # Status checks can be either a Status or a CheckRun
    StatusCheckType = T.type_alias { T.any(Status, CombinedStatus::CheckRunAdapter) }
    StatusCheckExpandedType = T.type_alias { T.any(InMemoryRequiredStatusCheck, StatusCheckType) }

    # Public: Check the context rules for a single ref update
    #
    # repository   - The Repository, Gist, or Unsullied::Wiki whose refs
    #                are being updated
    # ref_update   - Git::Ref::Update instance
    # rule_configs - Hash of RequiredStatusCheck instances keyed by the RepositoryRuleConfiguration
    #
    # Returns hash of RepositoryRuleConfiguration -> StatusCheckRuleDecision
    sig do
      params(
        repository: Repository,
        ref_update: Git::Ref::Update,
        rule_configs: T::Array[RepositoryRuleConfiguration],
        has_merge_queue: T::Boolean,
        status_checks: T.nilable(Loader::Result),
      ).returns(T::Hash[RepositoryRuleConfiguration, StatusCheckRuleDecision])
    end
    def self.evaluate(repository:, ref_update:, rule_configs:, has_merge_queue: false, status_checks: nil)
      new(repository, ref_update, rule_configs, has_merge_queue).check(status_checks:)
    end

    sig { returns(Repository) }
    attr_reader :repository

    sig { returns(Git::Ref::Update) }
    attr_reader :ref_update

    sig { returns(T::Array[RepositoryRuleConfiguration]) }
    attr_reader :rule_configs

    sig { returns(T::Boolean) }
    attr_reader :has_merge_queue

    sig do
      params(
        repository: Repository,
        ref_update: Git::Ref::Update,
        rule_configs: T::Array[RepositoryRuleConfiguration],
        has_merge_queue: T::Boolean
      ).void
    end
    def initialize(repository, ref_update, rule_configs, has_merge_queue)
      @repository = repository
      @ref_update = ref_update
      @rule_configs = rule_configs
      @has_merge_queue = has_merge_queue
    end

    sig { params(status_checks: T.nilable(Loader::Result)).returns(T::Hash[RepositoryRuleConfiguration, StatusCheckRuleDecision]) }
    def check(status_checks: nil)
      # Preload all status checks in one call
      status_checks ||= default_loader.checks

      rule_configs.to_h do |config|
        [config, check_config(config, status_checks)]
      end
    end

    private

    sig { returns(Loader) }
    def default_loader
      contexts = rule_configs.flat_map do |config|
        InMemoryRequiredStatusCheck.normalize_status_checks(config, config.param("required_status_checks")).map(&:context)
      end
      Loader.new(
        repository:,
        commit_oids: commits_to_check.map(&:oid),
        contexts:,
      )
    end

    # Relevant commits to look at:
    # For strict and non-strict:
    # - the rule commit itself and commits that are tree-same to that commit
    # For non-strict (and merge queue enabled):
    # - all parent commits of the rule commit that are not the before commit
    sig { returns(T::Array[Commit]) }
    def commits_to_check
      commits_to_check = [rule_commit] + same_tree_rule_parent_commits

      unless rule_configs.all? { |config| config.param("strict_required_status_checks_policy") } && !has_merge_queue
        relevant_parent_commits = rule_parent_commits.reject do |commit|
          commit.oid == ref_update.before_oid
        end

        commits_to_check += relevant_parent_commits
      end

      commits_to_check
    end

    # Checks a single rule config against a set of status checks
    sig { params(config: RepositoryRuleConfiguration, all_status_checks: Loader::Result).returns(StatusCheckRuleDecision) }
    def check_config(config, all_status_checks)
      required = InMemoryRequiredStatusCheck.normalize_status_checks(config, config.param("required_status_checks"))

      results = required.map do |required_check|
        status_checks_for_context = all_status_checks.for_context(required_check.context)

        #
        # First check against the rule commit and commits that are tree-same to it
        #
        status_checks = status_checks_for_context.for_commits([rule_commit.oid])
        if status_checks.any?
          next result_for_check(required_check, status_checks, :rule_commit)
        elsif same_tree_rule_parent_commits.any?
          status_checks = status_checks_for_context.for_commits(same_tree_rule_parent_commits.map(&:oid))
          next result_for_check(required_check, status_checks, :rule_commit_tree_same)
        end

        # If we are using the strict rule, bail out now
        #
        # The exception is when the merge queue is enabled. In that case, we allow the rule to pass
        # since the merge queue will always ensure the branch is up-to-date before merging
        next StatusCheckResult.single(:missing, required_check, :strict) if config.param("strict_required_status_checks_policy") && !has_merge_queue

        # The loose rule only works for merge commits. If we are evaluating a direct push, bail out now
        next StatusCheckResult.single(:missing, required_check, :loose_no_merge) if !commit_trees_match? || !rule_commit.merge_commit?

        # Merge commits with no status checks typically occur when merging an
        # out-of-date PR via the Merge button, or when performing a merge on
        # the command line. The loose rule allows these merges to be pushed
        # if the pre-merge commits have passing status checks.

        # Ignore the base branch commit. This ensures that if the base branch is failing, PRs can
        # still be merged in
        relevant_parent_commits = rule_parent_commits.reject do |commit|
          commit.oid == ref_update.before_oid
        end
        relevant_parent_commits_by_sha = relevant_parent_commits.index_by(&:oid)

        # NOTE: We could use `group_by(&:tree_oid)` here, but we don't because
        # it involves looking up commits that we already have in memory.
        parent_commits_status_checks = status_checks_for_context.for_commits(relevant_parent_commits.map(&:oid)).group_by do |check|
          relevant_parent_commits_by_sha.fetch(check.commit_oid).tree_oid
        end

        # All parents (other than the base) must be passing
        # In cases where a merge commit has >2 parents, a status check failing on one parent
        # but not the others will result in the rule failing
        parent_results = relevant_parent_commits.map do |parent|
          parent_checks = parent_commits_status_checks[parent.tree_oid] || []
          result_for_check(required_check, parent_checks, :merge_parent)
        end

        if parent_results.size == 1
          T.must(parent_results.first)
        elsif parent_results.size > 1
          # If we did not find a merge parent that is the `before_oid` (usually the tip of the base branch)
          # this may indicate that the merge commit we are looking at is out of date, meaning the base
          # has moved but the PR's merge commit has not been updated.
          decision_type = relevant_parent_commits.size == rule_parent_commits.size ? :merge_multi_parent_out_of_date : :merge_multi_parent
          StatusCheckResult.new(parent_results.to_h { |r| [r.reason_check, r.code] }, decision_type)
        else
          # this shouldn't be possible
          StatusCheckResult.single(:missing, required_check, :unknown)
        end
      end
      # cast to remove nilable from the hash value (array length is always the same)
      results_map = T.cast(required.zip(results).to_h, T::Hash[InMemoryRequiredStatusCheck, StatusCheckResult])

      StatusCheckRuleDecision.new(rules_fulfilled: results.all?(&:success?), status_check_results: results_map)
    end

    sig do params(
      required_check: InMemoryRequiredStatusCheck,
      status_checks: T::Enumerable[StatusCheckType],
      decision_type: Symbol)
      .returns(StatusCheckResult)
    end
    def result_for_check(required_check, status_checks, decision_type)
      passing, failing = status_checks.partition do |status_check|
        StatusCheckConfig::SUCCESS_STATES.include?(status_check.state)
      end

      valid_passing, invalid_passing = if required_check.integration_id.present?
        passing.partition { |status_check| status_check.integration_id == required_check.integration_id }
      else
        [passing, []]
      end

      case
      when failing.any?
        StatusCheckResult.single(:unsuccessful, T.must(failing.first), decision_type)
      when valid_passing.any?
        StatusCheckResult.single(:success, T.must(valid_passing.first), decision_type)
      when invalid_passing.any?
        StatusCheckResult.single(:invalid_integration, T.must(invalid_passing.first), decision_type)
      else
        StatusCheckResult.single(:missing, required_check, decision_type)
      end
    end

    sig { returns(T::Boolean) }
    def commit_trees_match?
      rule_commit.tree_oid == ref_update.after_commit.tree_oid
    end

    # Private: Git::Branch::Updates come with a rule commit. This rule commit is the test merge
    # of a PR. We use this value when available to support other merge types (ex: squash) where the after
    # commit is different than where status checks were published.
    # For Git::Ref::Updates, we want to fall back to the after commit
    sig { returns(Commit) }
    def rule_commit
      if ref_update.respond_to?(:rule_commit)
        ref_update.try(:rule_commit)
      else
        ref_update.after_commit
      end
    end

    # Private: The rule commit's parent commits
    sig { returns(T::Array[Commit]) }
    def rule_parent_commits
      return @rule_parent_commits if defined? @rule_parent_commits

      @rule_parent_commits = repository.commits.find(rule_commit.parent_oids)
    end

    # Private: The rule commit's parent commits that point to the same tree
    # as the rule commit does.
    #
    # We exclude the before commit from this list so that it cannot interfere in case it
    # points to the same tree.
    sig { returns(T::Array[Commit]) }
    def same_tree_rule_parent_commits
      return @same_tree_rule_parent_commits if defined? @same_tree_rule_parent_commits

      @same_tree_rule_parent_commits = rule_parent_commits
          .select { |commit| commit.tree_oid == rule_commit.tree_oid }
          .reject { |commit| commit.oid == ref_update.before_oid }
    end

    class StatusCheckRuleDecision
      extend T::Sig

      CheckResultsType = T.type_alias { T::Hash[InMemoryRequiredStatusCheck, StatusCheckResult] }

      sig { returns(T::Boolean) }
      attr_reader :rules_fulfilled
      alias_method :rules_fulfilled?, :rules_fulfilled

      sig { returns(CheckResultsType) }
      attr_reader :status_check_results

      sig { params(rules_fulfilled: T::Boolean, status_check_results: CheckResultsType).void }
      def initialize(rules_fulfilled:, status_check_results:)
        @rules_fulfilled = rules_fulfilled
        @status_check_results = status_check_results
      end
    end

    class StatusCheckResult
      extend T::Sig

      CODES = [:missing, :unsuccessful, :invalid_integration, :success]

      sig { returns(T::Hash[StatusCheckExpandedType, Symbol]) }
      attr_reader :code_by_status_check

      sig { returns(Symbol) }
      attr_reader :decision_type

      sig { params(code: Symbol, reason_check: StatusCheckExpandedType, decision_type: Symbol).returns(StatusCheckResult) }
      def self.single(code, reason_check, decision_type)
        new({ reason_check => code }, decision_type)
      end

      sig { params(code_by_status_check: T::Hash[StatusCheckExpandedType, Symbol], decision_type: Symbol).void }
      def initialize(code_by_status_check, decision_type)
        @code_by_status_check = code_by_status_check
        @decision_type = decision_type
      end

      sig { returns(T::Boolean) }
      def success?
        code_by_status_check.all? { |_, code| code == :success }
      end

      sig { returns(T::Boolean) }
      def multi_commit_result?
        code_by_status_check.size > 1
      end

      sig { returns(Symbol) }
      def code
        T.must(code_by_status_check.sort_by { |_, code| CODES.index(code) }.first).last
      end

      sig { returns(StatusCheckExpandedType) }
      def reason_check
        T.must(code_by_status_check.sort_by { |_, code| CODES.index(code) }.first).first
      end
    end
  end
end
