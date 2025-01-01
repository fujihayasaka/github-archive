# typed: strict
# frozen_string_literal: true

module MergeQueues
  # Load all relevant data from the database required to perform operations on the Merge Queue.
  class Factory
    include GitHub::Memoizer
    include PullRequests::External::Domain::StatusChecks::Provider
    include Scientist

    sig { params(repository: Repository, merge_queue: MergeQueue, entries: T.nilable(T::Array[MergeQueueEntry])).void }
    def initialize(repository, merge_queue, entries: nil)
      @repository = repository
      @merge_queue = merge_queue
    end

    # Active configuration for this Merge Queue.
    sig { returns(IConfiguration) }
    memoize def configuration
      MergeQueues.configuration_for(@merge_queue)
    end

    # Sorted array of Merge Queue Entries based on the order they should be evaluated.
    sig { returns(T::Array[MergeQueueEntry]) }
    memoize def merge_queue_entry_models
      @merge_queue.entries.to_a.tap do |entries|
        GitHub::PrefillAssociations.prefill_associations( # domain-isolation-query-violation:ignore:packages/issues (SELECT)
          entries,
          [:queue, :repository, pull_request: :issue],
          available_records: [@repository, @merge_queue],
        )
      end
    end

    # Check/Status API models filtered to those that support retrying.
    sig { returns(T::Array[CombinedStatus::CheckRunAdapter]) }
    memoize def check_models
      check_models_by_sha.values.flatten(1).filter_map do |check|
        if check.is_a?(PullRequests::External::Domain::StatusChecks::IStatusCheck)
          check.as_check_run
        elsif check.is_a?(CombinedStatus::CheckRunAdapter)
          check
        else
          nil
        end
      end
    end

    # Initialize an EntryList that describes the state of the queue.
    sig { returns(EntryList) }
    memoize def to_entry_list
      entries = merge_queue_entry_models.map do |merge_queue_entry|
        state_class = begin
          merge_queue_entry.entry_state
        rescue ArgumentError, NameError => exception
          Failbot.report(exception)
          Entry::State::Queued
        end

        state = if state_class == Entry::State::AwaitingChecks
          checks_requested_at = merge_queue_entry.checks_requested_at
          # TODO: Handle bad data in the DB
          state_class.new(
            checks_requested_at:,
          )
        elsif state_class == Entry::State::Unmergeable
          reason = Entry::RemovalReason.from_i(merge_queue_entry.dequeue_reason)
          state_class.new(reason:)
        else
          # NOTE: Unfortunately Sorbet's type system isn't sophisticated enough
          #  to nicely handle this case.
          #  See: https://github.com/sorbet/sorbet/issues/5416
          T.cast(T.unsafe(state_class).new, Entry::State)
        end

        # We're not using the `Waiting` state yet, so for now we should treat
        # it the same as `Queued`.
        # TODO: Remove this when adding proper support for `waiting`
        state = Entry::State::Queued.new if state.is_a?(Entry::State::Waiting)

        head_sha = merge_queue_entry.head_sha
        requested_checks = build_requested_checks(merge_queue_entry, state:)

        Entry.new(
          state:,
          head_sha:,
          base_sha: merge_queue_entry.base_sha,
          head_ref: merge_queue_entry.head_ref,
          merge_queue_entry_id: merge_queue_entry.id,
          pull_request_number: T.must(merge_queue_entry.pull_request).number,
          pull_request_id: T.must(merge_queue_entry.pull_request).id,
          solo: merge_queue_entry.solo?,
          attempts: merge_queue_entry.attempts,
          created_at: merge_queue_entry.created_at.to_time,
          locked: merge_queue_entry.locked?,
          requested_checks:,
          enqueued_head_sha: merge_queue_entry.enqueued_head_sha,
        )
      end

      EntryList.new(entries)
    end

    sig { returns(T::Boolean) }
    def require_checks?
      if @repository.feature_enabled?(:merge_queue_status_checks_domain)
        new_require_checks?
      elsif @repository.feature_enabled?(:merge_queue_require_checks_experiment)
        science("merge_queue_require_checks_experiment") do |experiment|
          experiment.use { old_require_checks? }
          experiment.try { new_require_checks? }
        end
      else
        old_require_checks?
      end
    end

    private

    sig { returns(T::Boolean) }
    def old_require_checks? = required_checks.any?

    sig { returns(T::Boolean) }
    def new_require_checks?
      target_branch_has_required_checks? || target_branch_has_required_workflows?
    end

    sig { returns(T::Boolean) }
    def target_branch_has_required_checks?
      branch_policy_evaluator.required_status_checks_enabled? &&
        branch_policy_evaluator.required_status_checks.any?
    end

    sig { returns(T::Boolean) }
    def target_branch_has_required_workflows?
      branch_policy_evaluator.workflows_rule_enabled? &&
        branch_policy_evaluator.required_workflows.any?
    end

    # List of CheckRun "display_names" supplied to the CheckRun APIs.
    # TODO: Delete me when promoting the `merge_queue_status_checks_domain` FF
    sig { returns(T::Set[String]) }
    memoize def required_check_contexts
      required_checks.map(&:name).to_set
    end

    # Collection of Checks configured to be required in the branch rules.
    # TODO: Delete me when promoting the `merge_queue_status_checks_domain` FF
    sig { returns(T::Array[Entry::RequiredCheck]) }
    memoize def required_checks
      load_required_workflows + load_required_status_checks
    end

    # TODO: Delete me when promoting the `merge_queue_status_checks_domain` FF
    sig { returns(T::Array[Entry::RequiredCheck]) }
    def load_required_workflows
      workflows = branch_policy_evaluator.required_workflows

      return [] if workflows.empty?

      queries = workflows.map do |workflow|
        imposer_repository_id, path = workflow.values_at("repository_id", "path")
        @repository.workflows.where(path:, imposer_repository_id:)
      end

      queries.reduce(:or).find_each.map do |workflow|
        config = workflows.find { |w| w["repository_id"] == workflow.imposer_repository_id && w["path"] == workflow.path }
        Entry::RequiredCheck.new(
          name: workflow.name || workflow.path,
          integration_id: config&.dig("integration_id")&.to_i,
        )
      end
    end

    # TODO: Delete me when promoting the `merge_queue_status_checks_domain` FF
    sig { returns(T::Array[Entry::RequiredCheck]) }
    def load_required_status_checks
      branch_policy_evaluator.required_status_checks.map do |check_configuration|
        Entry::RequiredCheck.new(
          name: check_configuration.context,
          integration_id: check_configuration.integration_id
        )
      end
    end

    # Collection of objects that describe the current CI state for the given Entry.
    sig { params(merge_queue_entry: MergeQueueEntry, state: Entry::State).returns(T::Array[Entry::RequestedCheck]) }
    def build_requested_checks(merge_queue_entry, state:)
      return [] if state.is_a?(Entry::State::Queued)

      head_sha = merge_queue_entry.head_sha
      return [] if head_sha.nil?

      requested_at = T.let(merge_queue_entry.checks_requested_at || Time.current, ActiveSupport::TimeWithZone).to_time
      requested_checks = status_check_models_for(head_sha).map do |check|

        check_state = if StatusCheckRollup.state_is_failure([check.state])
          Entry::RequestedCheck::State::Failed
        elsif StatusCheckRollup.state_is_success([check.state])
          Entry::RequestedCheck::State::Success
        else
          Entry::RequestedCheck::State::Pending
        end

        # If the check was reported by the wrong integration, treat it as still
        # pending so that the correct integration has time to report.
        if @repository.feature_enabled?(:merge_queue_handle_invalid_integration_later) && check.is_a?(PullRequests::External::Domain::StatusChecks::IStatusCheck) && check.rule_evaluation_result == PullRequests::External::Domain::StatusChecks::RuleEvaluationResult::InvalidIntegration
          check_state = Entry::RequestedCheck::State::Pending
        end

        Entry::RequestedCheck.new(
          name: check.context,
          attempts: merge_queue_entry.attempts,
          max_attempts: configuration.max_attempts,
          supports_retry: retryable_check?(check),
          timeout_after: configuration.check_response_timeout,
          requested_at:,
          state: check_state,
        )
      end

      # TODO: Delete whole block when promoting the `merge_queue_skip_filling_expected_check_gaps` FF
      # If for some reason we didn't get data from `current_statuses_with_expected`, generate those.
      (required_check_contexts - requested_checks.map(&:name)).each do |name|
        GitHub.dogstats.increment("merge_queue.incomplete_check_data")
        GitHub.logger.info(
          "Merge Queue: incomplete checks data",
          "code.namespace": "MergeQueues::Factory",
          "gh.repo.id": @repository.id,
          "gh.status_check.name": name,
        )

        if !@repository.feature_enabled?(:merge_queue_handle_invalid_integration_later) || !@repository.feature_enabled?(:merge_queue_skip_filling_expected_check_gaps)
          requested_checks << Entry::RequestedCheck.new(
            name:,
            requested_at:,
            state: Entry::RequestedCheck::State::Pending,
            supports_retry: false,
            attempts: merge_queue_entry.attempts,
            max_attempts: configuration.max_attempts,
            timeout_after: configuration.check_response_timeout,
          )
        end
      end

      requested_checks
    end

    # The API for interacting with Branch Rules.
    sig { returns(BranchRuleEvaluator) }
    memoize def branch_policy_evaluator
      # Enabling merge queue causes some rule configurations to exist, so
      # we can safely assume that a persisted merge queue will have a branch
      # rule evaluator.
      T.must(@merge_queue.branch_rule_evaluator)
    end

    # Mapping of head_sha to CheckModel records. All of the records returned are required in the current branch rules configuration.
    sig { returns(T::Hash[String, T::Array[CheckModel]]) }
    memoize def check_models_by_sha
      built_entries = merge_queue_entry_models.select { _1.head_sha.present? }

      return {} if built_entries.empty?

      if @repository.feature_enabled?(:merge_queue_status_checks_domain)
        new_check_models_by_sha(built_entries)
      else
        old_check_models_by_sha(built_entries)
      end
    end

    # TODO: Delete me when promoting the `merge_queue_status_checks_domain` FF
    sig { params(built_entries: T::Array[MergeQueueEntry]).returns(T::Hash[String, T::Array[CheckModel]]) }
    def old_check_models_by_sha(built_entries)
      shas = built_entries.map(&:head_sha).compact
      combined_statuses = CombinedStatus.combined_statuses_for_shas(@repository, shas)

      combined_statuses.map do |sha, combined_status|
        filtered_checks = combined_status.status_checks
          .filter { required_check_contexts.include?(_1.context) }
          .filter { valid_integration_id?(_1) }

        all_checks = branch_policy_evaluator.current_statuses_with_expected(filtered_checks) +
          branch_policy_evaluator.required_workflow_statuses(sha:, include_optional: false)

        [sha, all_checks]
      end.to_h
    end

    sig do
      params(built_entries: T::Array[MergeQueueEntry])
        .returns(T::Hash[String, T::Array[PullRequests::External::Domain::StatusChecks::IStatusCheck]])
    end
    def new_check_models_by_sha(built_entries)
      result = status_checks_domain
        .for_merge_queue_entries(built_entries)
        .transform_keys { |merge_queue_entry| merge_queue_entry.head_sha }
        .transform_values { |checks| checks.filter(&:required?) }

      if @repository.feature_enabled?(:merge_queue_handle_invalid_integration_later)
        result
      else
        result.transform_values do |checks|
          checks.reject do |check|
            if check.rule_evaluation_result == PullRequests::External::Domain::StatusChecks::RuleEvaluationResult::InvalidIntegration
              GitHub.dogstats.increment("merge_queue.dropped_check_with_invalid_integration")
              GitHub.logger.info(
                "Merge Queue: check from invalid integration",
                "code.namespace": "MergeQueues::Factory",
                "gh.repo.id": @repository.id,
                "gh.status_check.name": check.context,
              )
              true
            else
              false
            end
          end
        end
      end
    end

    # Find the check models for the given SHA.
    sig { params(sha: String).returns(T::Array[CheckModel]) }
    def status_check_models_for(sha)
      check_models_by_sha[sha] || []
    end

    # Determine if the API used by the consumer supports retrying.
    # TODO: Inline me when promoting the `merge_queue_status_checks_domain` FF
    sig { params(model: CheckModel).returns(T::Boolean) }
    def retryable_check?(model)
      case model
      when CombinedStatus::CheckRunAdapter
        true
      when RequiredStatusCheck, Status, InMemoryRequiredStatusCheck,
        RuleEngine::Rules::WorkflowRule::RequiredWorkflowStatusCheckDuckType
        false
      when PullRequests::External::Domain::StatusChecks::IStatusCheck
        !model.as_check_run.nil?
      else
        T.absurd(model)
      end
    end

    # Determine if the user has configured specific integration IDs for a
    # check, and ensure that when loading statuses.
    # TODO: Delete me when promoting the `merge_queue_status_checks_domain` FF
    sig { params(check: T.any(CombinedStatus::CheckRunAdapter, Status)).returns(T::Boolean) }
    def valid_integration_id?(check)
      required_integration_id = required_checks.find { _1.name == check.context }&.integration_id
      return true if required_integration_id.nil?

      creator = check.creator
      return false unless creator.is_a?(Bot)
      creator.integration&.id == required_integration_id
    end
  end
end
