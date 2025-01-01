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
    memoize def retryable_check_models
      check_models_by_sha.values.flatten(1)
        .filter { |check| retryable_check?(check) }
        .filter_map(&:as_check_run)
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
      target_branch_has_required_checks? || target_branch_has_required_workflows?
    end

    private

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

    # Collection of objects that describe the current CI state for the given Entry.
    sig { params(merge_queue_entry: MergeQueueEntry, state: Entry::State).returns(T::Array[Entry::RequestedCheck]) }
    def build_requested_checks(merge_queue_entry, state:)
      return [] if state.is_a?(Entry::State::Queued)

      head_sha = merge_queue_entry.head_sha
      return [] if head_sha.nil?

      requested_at = T.let(merge_queue_entry.checks_requested_at || Time.current, ActiveSupport::TimeWithZone).to_time
      status_check_models_for(head_sha).map do |check|

        check_state = if StatusCheckRollup.state_is_failure([check.state])
          Entry::RequestedCheck::State::Failed
        elsif StatusCheckRollup.state_is_success([check.state])
          Entry::RequestedCheck::State::Success
        else
          Entry::RequestedCheck::State::Pending
        end

        # If the check was reported by the wrong integration, treat it as still
        # pending so that the correct integration has time to report.
        if check.rule_evaluation_result == PullRequests::External::Domain::StatusChecks::RuleEvaluationResult::InvalidIntegration
          check_state = Entry::RequestedCheck::State::Pending
        end

        supports_retry = if @repository.feature_flag_enabled_or_raise?(:merge_queue_disable_retries) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          false
        else
          retryable_check?(check)
        end

        Entry::RequestedCheck.new(
          name: check.context,
          attempts: merge_queue_entry.attempts,
          max_attempts: configuration.max_attempts,
          supports_retry:,
          timeout_after: configuration.check_response_timeout,
          requested_at:,
          state: check_state,
        )
      end
    end

    # The API for interacting with Branch Rules.
    sig { returns(BranchRuleEvaluator) }
    memoize def branch_policy_evaluator
      # Enabling merge queue causes some rule configurations to exist, so
      # we can safely assume that a persisted merge queue will have a branch
      # rule evaluator.
      T.must(@merge_queue.branch_rule_evaluator)
    end

    # Mapping of head_sha to PullRequests::External::Domain::StatusChecks::IStatusCheck records. All of the records returned are required in the current branch rules configuration.
    sig { returns(T::Hash[String, T::Array[PullRequests::External::Domain::StatusChecks::IStatusCheck]]) }
    memoize def check_models_by_sha
      built_entries = merge_queue_entry_models.select { _1.head_sha.present? }

      return {} if built_entries.empty?

      status_checks_domain
        .for_merge_queue_entries(built_entries)
        .transform_keys { |merge_queue_entry| merge_queue_entry.head_sha }
        .transform_values { |checks| checks.filter(&:required?) }
    end

    # Find the check models for the given SHA.
    sig { params(sha: String).returns(T::Array[PullRequests::External::Domain::StatusChecks::IStatusCheck]) }
    def status_check_models_for(sha)
      check_models_by_sha[sha] || []
    end

    # Determine if the API used by the consumer supports retrying.
    sig { params(model: PullRequests::External::Domain::StatusChecks::IStatusCheck).returns(T::Boolean) }
    def retryable_check?(model)
      if @repository.feature_flag_enabled?(:merge_queue_retryable_checks_check_rerunnable, default: false)
        check_suite = model.check_suite
        !check_suite.nil? && check_suite.check_runs_rerunnable?
      else
        !model.as_check_run.nil?
      end
    end
  end
end
