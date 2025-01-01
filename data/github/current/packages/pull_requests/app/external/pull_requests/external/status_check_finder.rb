# typed: strict
# frozen_string_literal: true

module PullRequests
  module External
    # This class is responsible for loading the canonical set of checks associated
    # with a PullRequest or MergeQueueEntry.
    #
    # The results are drawn from a variety of sources:
    #
    # 1. Statuses reported by customers' CI services, which are one of:
    #     - `Status`
    #     - `CombinedStatus::CheckRunAdapter` which wraps a `CheckRun` and
    #       provides an interface more similar to `Status`.
    # 2. Required checks that are pending, because there is no reported status
    #    for them yet. There are two types that represent these pending checks,
    #    depending on the type of rule they are required by:
    #     - `InMemoryRequiredStatusCheck` which represents a check required by a
    #       `RequiredStatusChecksRule`.
    #     - `RequiredStatusCheck` which represents a check required by a
    #       `ProtectedBranch`.
    #     - `RuleEngine::Rules::WorkflowRule::RequiredWorkflowStatusCheckDuckType`
    #       which represents a check required by a `WorkflowRule`.
    #
    # To smooth out the differences between all of these objects, we return a
    # single `Record` type which wraps the original object and provides a
    # consistent interface. The `Record` is also annotated with the result
    # metadata from the rule engine, which indicates if the check was required
    # and if it passed the rules. It is possible for a status check to be in
    # a successful state but still fail the rules because it was reported by
    # the wrong integration.
    #
    # Statuses and CheckRuns are attached to a specific commit. This class will
    # look for reported statuses on all relevant commits:
    #
    # - For a `PullRequest`, the merge commit computed by GitHub or the head
    #   commit pushed by the user.
    # - For a `MergeQueueEntry`, the merge commit computed by GitHub.
    #
    # When there are statuses reported against both commits with the same context
    # (i.e. the same name) we need to pick which one to use:
    #
    # - For required checks we invoke the `RuleEngine::StatusCheckEvaluator` to
    #   ensure that the results displayed in the PRs UI match what the rule
    #   engine is using to determine mergeability.
    # - For non-required checks we prefer statuses on the merge commit over
    #   statuses on the head commit.
    class StatusCheckFinder
      EntityType = T.type_alias do
        T.any(
          PullRequest,
          MergeQueueEntry,
        )
      end

      StatusCheckType = T.type_alias do
        T.any(
          Status,
          CombinedStatus::CheckRunAdapter,
          InMemoryRequiredStatusCheck,
          RequiredStatusCheck,
          RuleEngine::Rules::WorkflowRule::RequiredWorkflowStatusCheckDuckType,
        )
      end

      sig do
        # Using a generic type parameter allows us to pass a homogenous
        # argument (i.e. all PRs or all merge queue entries) and not lose that
        # specificity in the result:
        #   batch_load(T::Array[PullRequest) => T::Hash[PullRequest, ...]
        #   batch_load(T::Array[MergeQueueEntry) => T::Hash[MergeQueueEntry, ...]
        type_parameters(:EntityType)
          .params(
            entities: T::Enumerable[T.all(EntityType, T.type_parameter(:EntityType))],
            block: T.nilable(T.proc.params(arg0: RuleEngine::StatusCheckEvaluator::Loader::Result).void),
          )
          .returns(T::Hash[T.type_parameter(:EntityType), T::Array[Record]])
      end
      def self.batch_load(entities, &block)
        pulls = entities.select { _1.is_a?(PullRequest) }
        GitHub::PrefillAssociations.prefill_associations(pulls, [
          :repository,
          :base_user,
          :head_user,
        ])
        GitHub::PrefillAssociations.prefill_batch_method(pulls, :base_branch_rule_evaluator)

        entities
          .group_by { T.must(_1.repository) }
          .reduce(T.let({}, T::Hash[T.type_parameter(:EntityType), T::Array[Record]])) do |result, (repository, repo_entities)|
            check_finders_by_entity = repo_entities.map { |entity| [entity, new(entity)] }.to_h
            commit_oids = check_finders_by_entity.values.flat_map(&:relevant_commit_oids)
            loader = RuleEngine::StatusCheckEvaluator::Loader.new(commit_oids:, repository:)

            # Allow the caller to prefill associations on all checks
            yield loader.checks if block_given?

            repo_result = check_finders_by_entity.transform_values { _1.canonical_checks(loader:) }
            result.merge(repo_result)
          end
      end

      sig { params(entity: EntityType).void }
      def initialize(entity)
        @entity = entity
      end

      # Fetch the canonical checks associated with the PullRequest or
      # MergeQueueEntry passed to the initializer. We allow a Loader to be
      # injected here to support batching.
      sig do
        params(
          loader: T.nilable(RuleEngine::StatusCheckEvaluator::Loader),
          block: T.nilable(T.proc.params(arg0: RuleEngine::StatusCheckEvaluator::Loader::Result).void),
        ).returns(T::Array[Record])
      end
      def canonical_checks(loader: nil, &block)
        # If we have no commits to look at, return the expected required
        # statuses without doing any additional work.
        if relevant_commit_oids.empty?
          return expected_required_checks + expected_required_workflows
        end

        if loader
          missing_oids = relevant_commit_oids - loader.commit_oids
          if missing_oids.any?
            raise ArgumentError, "Loader not configured for commits #{missing_oids}"
          end
        else
          loader = RuleEngine::StatusCheckEvaluator::Loader.new(
            commit_oids: relevant_commit_oids,
            repository:,
          )
        end

        reported_checks = loader.checks.for_commits(relevant_commit_oids)

        # Allow the caller to preload associations on checks
        yield reported_checks if block_given?

        reported_and_expected_checks = checks_with_expected_from_rule_evaluation(reported_checks)
        add_required_workflow_statuses(reported_and_expected_checks)
      end

      sig { returns(T::Array[String]) }
      def relevant_commit_oids
        case @entity
        when PullRequest
          [@entity.head_sha, @entity.merge_commit_sha].compact
        when MergeQueueEntry
          [@entity.head_sha].compact
        else
          T.absurd(@entity)
        end
      end

      private

      sig { returns(Repository) }
      def repository = T.must(@entity.repository)

      sig { params(reported_checks: RuleEngine::StatusCheckEvaluator::Loader::Result).returns(T::Array[Record]) }
      def checks_with_expected_from_rule_evaluation(reported_checks)
        rule_configs = branch_rule_evaluator&.configs_by_type("required_status_checks") || []

        results_by_context = T.let({}, T::Hash[String, T::Array[Symbol]])
        results_by_lowercase_context = T.let({}, T::Hash[String, T::Array[Symbol]])
        expected_check_results = T.let([], T::Array[RuleEngine::StatusCheckEvaluator::StatusCheckResult])

        if rule_configs.any?
          # For PRs and MergeQueueEntries, which are always guaranteed to be
          # evaluating a simple two-way merge, the rule engine's disambiguation
          # works like this:
          #
          # 1. Prefer a status on the merge commit (:rule_commit).
          # 2. Accept a status on the head commit if it points to the same tree as
          #    the merge commit (:rule_commit_tree_same).
          # 3. Accept a status on the head commit if it does not point to the same
          #    tree as the merge commit but the rule is not in strict mode, or if
          #    this is for a MergeQueueEntry (:merge_parent).
          #
          # The rule engine is only concerned with requried checks, so these
          # results will not include any optional checks.
          status_check_evaluator = RuleEngine::StatusCheckEvaluator.new(
            repository,
            entity_ref_update,
            rule_configs,
            has_merge_queue,
          )

          status_check_evaluator.check(status_checks: reported_checks).each do |_, decision|
            decision.status_check_results.each do |_, result|
              if result.code == Domain::StatusChecks::RuleEvaluationResult::Missing.serialize
                expected_check_results << result
              else
                context = result.reason_check.context

                (results_by_context[context] ||= []) << result.code
                (results_by_lowercase_context[context.downcase] ||= []) << result.code
              end
            end
          end
        end

        # Multiple rulesets might require the same thing. Only return duplicates
        # for a given context if they specify different integration IDs.
        canonical_expected_checks = expected_check_results
          .map(&:reason_check)
          .uniq { [_1.context, _1.integration_id] }
          .map do |expected_check|
            Record.new(
              expected_check,
              rule_evaluation_result: Domain::StatusChecks::RuleEvaluationResult::Missing,
            )
          end

        canonical_reported_checks = reported_checks.map do |reported_check|
          case reported_check
          when Status
            # Status contexts are case insensitve when matching required checks
            rule_engine_result_codes = results_by_lowercase_context[reported_check.context.downcase]
          when CombinedStatus::CheckRunAdapter
            # CheckRun contexts are case sensitive when matching required checks
            rule_engine_result_codes = results_by_context[reported_check.context]
          else
            T.absurd(reported_check)
          end

          rule_evaluation_result = if rule_engine_result_codes
            # We might have multiple results for the same context
            # e.g. two rulesets require the same context, but only
            # one of them specifies an integration, we could get a
            # `:success` and a `:invalid_integration`, so we need to ask
            # the rule engine which status takes priority.
            code = RuleEngine::StatusCheckEvaluator::StatusCheckResult.combined_code(rule_engine_result_codes)
            Domain::StatusChecks::RuleEvaluationResult.deserialize(code)
          else
            # If we don't have a rule engine result, this can't be a required
            # check.
            Domain::StatusChecks::RuleEvaluationResult::NotRequired
          end

          Record.new(reported_check, rule_evaluation_result:)
        end

        canonical_reported_checks + canonical_expected_checks
      end

      sig { params(statuses: T::Array[Record]).returns(T::Array[Record]) }
      def add_required_workflow_statuses(statuses)
        return statuses unless rule_evaluator = branch_rule_evaluator
        return statuses unless rule_evaluator.workflows_rule_enabled?(include_optional: true)

        required_workflow_statuses = rule_evaluator
          .required_workflow_statuses(sha: relevant_commit_oids, include_optional: true)
          .map do |check|
            # TODO: This is duplicating logic from the
            # `RuleEngine::Rules::WorkflowRule#evaluate` method. There is a
            # risk that the implementations will diverge.
            # There is already some difference, because the
            # `#required_workflow_statuses` method returns
            # only the latest check suite for each required check, whereas the
            # `#evaluate` method checks the state of all matching check suites.
            check_suite = check.check_suite
            rule_evaluation_result = if !check.required
              Domain::StatusChecks::RuleEvaluationResult::NotRequired
            elsif check_suite.nil?
              Domain::StatusChecks::RuleEvaluationResult::Missing
            elsif check_suite.failed?
              Domain::StatusChecks::RuleEvaluationResult::Unsuccessful
            else
              Domain::StatusChecks::RuleEvaluationResult::Success
            end

            Record.new(check, rule_evaluation_result:)
          end

        return statuses if required_workflow_statuses.empty?

        required_workflow_status_check_suites = required_workflow_statuses.map(&:check_suite).compact.map(&:id).to_set
        filtered_statuses = statuses.reject do |status|
          required_workflow_status_check_suites.include?(status.check_suite_id)
        end

        filtered_statuses + required_workflow_statuses
      end

      sig { returns(T::Array[Record]) }
      def expected_required_checks
        required_checks = T.let(
          branch_rule_evaluator&.required_status_checks || [],
          T::Array[T.any(InMemoryRequiredStatusCheck, RequiredStatusCheck)]
        )

        required_checks.map do |required|
          Record.new(
            required,
            rule_evaluation_result: Domain::StatusChecks::RuleEvaluationResult::Missing,
          )
        end
      end

      sig { returns(T::Array[Record]) }
      def expected_required_workflows
        required_workflows = branch_rule_evaluator&.required_workflow_statuses(
          sha: [],
          include_optional: false,
        )

        return [] if required_workflows.nil?

        required_workflows.map do |required|
          Record.new(
            required,
            rule_evaluation_result: Domain::StatusChecks::RuleEvaluationResult::Missing,
          )
        end
      end

      sig { returns(Git::Branch::Update) }
      def entity_ref_update
        case @entity
        when PullRequest
          # Prefer a ref update to the PR's merge commit.
          ref_update_for_merge, _ = @entity.merge_state.ref_update_for_merge
          return ref_update_for_merge unless ref_update_for_merge.nil?

          # Fall back to a ref update to the PR's head commit.
          Git::Branch::Update.new(
            repository:,
            refname: "refs/heads/#{@entity.base_ref_name}",
            before_oid: @entity.current_base_sha || GitHub::NULL_OID,
            after_oid: @entity.head_sha,
          )
        when MergeQueueEntry
          Git::Branch::Update.new(
            repository:,
            refname: "refs/heads/#{T.must(@entity.queue).branch}",
            before_oid: @entity.base_sha || GitHub::NULL_OID,
            after_oid: @entity.head_sha || GitHub::NULL_OID,
          )
        else
          T.absurd(@entity)
        end
      end

      sig { returns(T::Boolean) }
      def has_merge_queue
        case @entity
        when PullRequest
          repository.merge_queue_enabled_for_branch?(@entity.base_ref_name)
        when MergeQueueEntry
          true
        else
          T.absurd(@entity)
        end
      end

      sig { returns(T.nilable(BranchRuleEvaluator)) }
      def branch_rule_evaluator
        case @entity
        when PullRequest
          @entity.base_branch_rule_evaluator
        when MergeQueueEntry
          T.must(@entity.queue).branch_rule_evaluator
        else
          T.absurd(@entity)
        end
      end
    end
  end
end
