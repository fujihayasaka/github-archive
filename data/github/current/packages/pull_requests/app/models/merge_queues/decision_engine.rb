# typed: strict
# frozen_string_literal: true

module MergeQueues
  # The core engine of Merge Queue. This contains all the logic for what decisions to make, but not how to perform those
  # decisions. Those are delegated to the IService.
  class DecisionEngine
    include GitHub::Memoizer

    # Signals to the caller.
    class Result < T::Enum
      enums do
        # Requesting an immediate re-execution of the Decision Engine as we need to start from the beginning.
        Restart = new(:restart)
        # There are Entries still in the Decision Engine and it's awaiting other dependencies.
        Waiting = new(:waiting)
        # Signal to caller that the Decision Engine has nothing left to do.
        Done = new(:done)
        # Signal to the callers the Merge Queue should be disabled.
        Disabled = new(:disabled)
      end
    end
    sig do
      params(
        entries: EntryList,
        command: ICommand,
        branch_sha: String,
        configuration: IConfiguration,
        require_checks: T::Boolean,
      ).void
    end
    def initialize(entries:, command:, branch_sha:, configuration:, require_checks:)
      @entries = entries
      @command = command
      @branch_sha = branch_sha
      @configuration = configuration
      @require_checks = require_checks
    end

    # The primary execution flow of the DecisionEngine.
    sig { returns(Result) }
    def call
      GitHub.logger.with_named_tags("code.function": "call", "code.namespace": "MergeQueues::DecisionEngine") do
        reset_descendants = T.let(false, T::Boolean)
        base_sha = @entries.locked_head_sha || @branch_sha

        # Safety net for unlikely queue ordering issues with stacked PRs. Since
        # this is a headless process, we must account for every scenario.
        @entries.stack_ids.each do |stack_id|
          case result = @entries.validate_stack(stack_id)
          when EntryList::StackValidity::OK
            # No-op: stack is in a valid state
          when EntryList::StackValidity::NotFound
            # This should be impossible: we're working through a list of stack
            # IDs taken from the queue entries, but the validation code just
            # told us there are no entries that match this stack ID.
            GitHub.logger.info(
              "Merge queue entries for stack not found",
              "gh.pull_request_stacks.id" => stack_id,
            )
          when EntryList::StackValidity::UnmergedParent
            GitHub.logger.info(
              "Merge queue entries for stack evicted",
              "gh.pull_request_stacks.id" => stack_id,
              "gh.merge_queue.reason" => "UnmergedParent",
            )
            dequeue(result.entries, reason: Entry::RemovalReason::StackParentUnmerged)
          when EntryList::StackValidity::NotContiguous
            GitHub.logger.info(
              "Merge queue entries for stack evicted",
              "gh.pull_request_stacks.id" => stack_id,
              "gh.merge_queue.reason" => "NotContiguous",
            )
            dequeue(result.entries, reason: Entry::RemovalReason::StackOutOfOrder)
          else
            T.absurd(result)
          end
        end

        # Loop through all unlocked entries and determine their validity.
        @entries.unlocked.each_with_index do |entry, position|
          # Fast-forward: When the first entry's base_sha matches the target branch tip, mark it for a fast forward attempt
          # using the Pull Request's existing head_sha/head_ref, bypassing merge commit creation and CI webhook dispatch.
          if position.zero? && can_fast_forward?(entry:, base_sha:)
            update_entries([entry]) do |e|
              e.state = Entry::State::Mergeable.new
              e.base_sha = base_sha
              e.head_sha = entry.enqueued_head_sha
              e.head_ref = entry.enqueued_head_ref
              e.fast_forward_attempted = true
            end
          end

          # Stack-invalidated entries are awaiting ejection — skip all evaluation.
          if entry.invalidated_stack?
            next
          end

          # Once a entry is invalid, all descendants are invalid and require a new base_ref.
          if base_sha != entry.base_sha && !entry.merge_conflict?
            reset_descendants = true
          end

          # TODO: I think we can early return and just send #up_to_and_including(entry) to #reset!
          # TODO: This should clear any locks on `reset!` Entry items. The current version implicitly does
          # this when recreating MergeGroups.
          if reset_descendants && entry.active_build?
            reset!([entry])
          end

          # Failures that result in a missing head SHA (merge conflicts, etc.)
          # are skipped over. They may become mergeable later, or be ejected
          # when the reach the head of the queue.
          if entry.unmergeable? && entry.head_sha.blank?
            next
          end

          # Cascade unmergeable state to stack descendants.
          if entry.stacked? && entry.unmergeable?
            cascade_stack_invalidation!(entry)
          end

          # Parse the state of CI and make the correct updates.
          case state = entry.state
          when Entry::State::AwaitingChecks, Entry::State::Unmergeable, Entry::State::Mergeable
            if entry.passing_checks? || !require_checks?
              update_state!(entry, Entry::State::Mergeable.new)
            elsif entry.failing_checks?
              update_state!(entry, Entry::State::Unmergeable.new(
                reason: Entry::RemovalReason::FailedChecks
              ))
            elsif entry.timed_out_checks?
              update_state!(entry, Entry::State::Unmergeable.new(
                reason: Entry::RemovalReason::ChecksTimedOut
              ))
            elsif entry.pending_checks?
              update_state!(entry, Entry::State::AwaitingChecks.new(
                checks_requested_at: Time.current
              ))
            end
          end

          if new_base_sha = entry.head_sha
            base_sha = new_base_sha
          end
        end

        # We will always attempt to merge the best entry unless the configuration is set to API driven merging.
        unless @configuration.actor_controlled_merging
          group = @entries.next_group(@configuration)

          case group_state = group.state
          when Group::State::MinimumSizeNotMet
            GitHub.logger.info(
              "Merge skipped",
              "gh.merge_queue.reason": "Group minimum size not met",
            )
          when Group::State::Empty
            GitHub.logger.info(
              "Merge skipped",
              "gh.merge_queue.reason": "No mergeable entry",
            )
          when Group::State::Mergeable
            merge!(group)
            return Result::Restart
          else
            T.absurd(group_state)
          end
        end

        # Remove removable entries (including stack descendants when applicable).
        entries_to_remove = removable_entries
        if entries_to_remove.any?
          entries_to_remove.each { |entry| eject!(entry) }

          # Ensure we evaluate the chain of base shas and invalidate as needed.
          return Result::Restart
        end

        return Result::Done if @entries.empty?

        # Now that we've made all the destructive changes to the queue, update the positions.
        recalculate_positions!

        # Loop over the remaining entries and attempt to build or retry them.
        @entries.unlocked.each do |entry|
          # We want to keep failing entries in the queue until they reach the top to remove them.
          if entry.retryable_checks?
            retry_checks!(entry)
          elsif entry.queued? && available_space_to_build?
            build!(entry)

            case state = entry.state
            when Entry::State::Unmergeable
              if state.unrecoverable_git_failure?
                # We will never have a successful ref update.
                dequeue([entry], reason: state.reason)
              end

              # Always restart to allow the top level block to validate the chain of base_shas to prevent unnecessary
              # builds that will get canceled on the next iteration.
              return Result::Restart
            end
          end
        end

        return Result::Waiting
      end
    end

    protected

    sig { params(entry: Entry).void }
    def eject!(entry)
      result = dequeue([entry], reason: entry.removal_reason || Entry::RemovalReason::Unknown)

      case result
      when ICommand::Result::Error
        # We have failed to remove an entry from the queue.
        # This should be fine: on retry we will make the same decisions.
        raise result.as_exception
      end
    end

    sig { params(group: Group[Entry]).void }
    def merge!(group)
      head_entry = group.entries.first
      web_hook_reason = WebHook::Destroyed::Reason::Merged
      destroyed_web_hooks = group.entries.map do |entry|
        WebHook::Destroyed.for(entry:, reason: web_hook_reason)
      end

      merge_result = Merger.new(command: @command).merge!(
        group,
        merge_method: @configuration.merge_method,
      )

      case merge_result
      when ICommand::Result::MergeSuccess
        # Track the new HEAD of the target branch.
        @branch_sha = merge_result.new_oid
        web_hook_reason = WebHook::Destroyed::Reason::Merged
      when ICommand::Result::AlreadyMergedError
        web_hook_reason = WebHook::Destroyed::Reason::Dequeued
      when ICommand::Result::BranchProtectionError
        # If a fast-forward merge is rejected by branch protection rules, reset the entry to retry
        # with the standard merge queue flow (creating a temporary ref and running CI checks).
        if fast_forward_enabled? && head_entry&.fast_forward?
          reset!([head_entry])
        else
          Failbot.report(merge_result.exception)
          dequeue(group.entries, reason: Entry::RemovalReason::BranchProtections)
        end

        return
      when ICommand::Result::Error
        # We have failed to merge.
        # Should be safe to bail, and re-run.
        raise merge_result.as_exception
      else
        T.absurd(merge_result)
      end

      group.entries.each { @entries.delete(_1) }

      # After merging stacked entries, mark the next entry in the same stack
      # as having its parent merged so the stack remains valid.
      group.entries.each do |merged_entry|
        if next_entry = @entries.next_entry_in_same_stack(merged_entry)
          T.must(next_entry.stack_info).parent_merged = true
        end
      end

      destroyed_web_hooks.each do |hook|
        hook.reason = web_hook_reason
        with_retry { @command.dispatch_webhook!(hook) }
      end
    end

    # Persist changes for the given Entry to the database.
    sig { params(entry: Entry, state: Entry::State).void }
    def update_state!(entry, state)
      return if entry.state.class == state.class

      result = update_entries([entry]) do |e|
        e.state = state
      end

      case result
      when ICommand::Result::Error
        # We have failed to mark an entry that is failing CI as unmergeable.
        # It should be safe to retry from here.
        raise result.as_exception
      end
    end

    sig { params(entries: T::Array[Entry]).void }
    def reset!(entries)
      entries_with_refs = if fast_forward_enabled?
        entries.select(&:temporary_ref?)
      else
        entries.select { _1.head_sha.present? }
      end

      # Capture WebHook payloads _before_ we wipe out the information needed
      # to create them.
      destroyed_web_hooks = entries_with_refs.map do |entry|
        WebHook::Destroyed.for(entry:, reason: WebHook::Destroyed::Reason::Invalidated)
      end

      # Clean up any refs that may have been created as reverting back to Queued signals a break in the git graph.
      @command.delete_refs!(entries_with_refs)

      # Don't reset queued things back to queued again.
      result = update_entries(entries.reject(&:queued?)) do |e|
        e.state = Entry::State::Queued.new
        e.head_sha = nil
        e.base_sha = nil
        e.attempts = 0
      end

      case result
      when ICommand::Result::Error
        # We have failed to reset an entry that is after someting that was
        # removed from the queue.
        # It shoudl be safe to retry from here.
        raise result.as_exception
      end

      destroyed_web_hooks.each do |hook|
        with_retry { @command.dispatch_webhook!(hook) }
      end
    end

    # Attempt to create a git ref and dispatch checks for the given Entry.
    sig { params(entry: Entry).void }
    def build!(entry)
      base_sha = @entries.buildable_ancestor_of(entry)&.head_sha || @branch_sha
      create_ref_result = with_retry { @command.create_ref!(entry, base_sha:, method: @configuration.merge_method) }

      case create_ref_result
      when ICommand::Result::MergeConflictError,
           ICommand::Result::RebaseConflictError,
           ICommand::Result::InvalidMergeCommitError,
           ICommand::Result::AlreadyMergedError,
           ICommand::Result::GitTreeError,
           ICommand::Result::BranchProtectionError
        # We've failed to create a ref for a known reason.
        next_state = case create_ref_result
        when ICommand::Result::MergeConflictError, ICommand::Result::RebaseConflictError
          Entry::State::Unmergeable.merge_conflict
        when ICommand::Result::AlreadyMergedError
          Entry::State::Unmergeable.already_merged
        when ICommand::Result::GitTreeError
          Entry::State::Unmergeable.git_tree_invalid
        when ICommand::Result::InvalidMergeCommitError
          Entry::State::Unmergeable.invalid_merge_commit
        when ICommand::Result::BranchProtectionError
          Failbot.report(create_ref_result.exception)
          Entry::State::Unmergeable.branch_protections
        else
          T.absurd(create_ref_result)
        end

        result = update_entries([entry]) do |e|
          # Ensure we track the base sha we failed to build against. This ensures we can confidently retry the ref
          # creation in the next run if the base sha changes.
          e.base_sha = base_sha
          e.state = next_state
        end

        case result
        when ICommand::Result::Error
          raise result.as_exception
        end

        # Currently we can only store Merge conflict data, not Rebase conflict data.
        if create_ref_result.is_a?(ICommand::Result::MergeConflictError)
          result = with_retry { @command.store_merge_conflict!(entry, conflict: create_ref_result) }

          case result
          when ICommand::Result::Error
            raise result.as_exception
          end
        end

        if entry.stacked?
          cascade_stack_invalidation!(entry)
        end

        return
      when ICommand::Result::Error
        # We have failed to create a ref, merge commit, etc for an unknown reason.
        # Since this is the first operation in the `build!` method, it will
        # be safe to retry in the next run.
        raise create_ref_result.as_exception
      end

      # We've successfully created the ref. Dispatch the checks.
      state = if require_checks?
        request_check_result = with_retry { @command.request_checks!(entry, create_ref_result:) }

        case request_check_result
        when ICommand::Result::Error
          # We have failed to request checks for our new ref.
          # It is safe to retry from here because the `#create_ref!` method
          # is idempotent.
          raise request_check_result.as_exception
        end

        Entry::State::AwaitingChecks.new(
          checks_requested_at: Time.current,
        )
      else
        # If no checks are required, it's mergeable as other branch protections from the Pull Request are valid.
        Entry::State::Mergeable.new
      end

      update_result = update_entries([entry]) do |e|
        e.state = state
        e.head_ref = create_ref_result.head_ref
        e.base_sha = create_ref_result.base_sha
        e.head_sha = create_ref_result.head_sha
        e.attempts = 1

        case state
        when Entry::State::AwaitingChecks
          # Reset requested checks, because we might be re-building an
          # entry that previously had a `head_sha` with associated checks.
          e.requested_checks = []
        end
      end

      case update_result
      when ICommand::Result::Error
        # We have successfully built a ref, merge commit, etc.
        # but failed to update the database.
        # Retrying from here may result in "ref already exists" type errors,
        # or possibly duplicate CI builds.
        raise update_result.as_exception
      end

      case state
      when Entry::State::AwaitingChecks
        webhook = begin
          WebHook::ChecksRequested.for(entry:)
        rescue WebHook::MissingDataError => exception
          # This will be raised if the entry does not have an associated
          # merge commit, etc. This should be impossible given we're in the AwaitingChecks state.
          Failbot.report(exception)

          # Transition this to an unmergeable state as the checks will never run given an invalid webhook payload.
          update_entries([entry]) do |e|
            e.state = Entry::State::Unmergeable.new(reason: Entry::RemovalReason::InvalidMergeCommit)
            e.head_ref = nil
            e.head_sha = nil
            e.base_sha = nil
          end

          return
        end

        case webhook_result = with_retry { @command.dispatch_webhook!(webhook) }
        when ICommand::Result::Error
          # If this fails we can't do anything about it.
          Failbot.report(webhook_result.as_exception)
        end
      end
    end

    # Attempt to retry the checks for a given Entry.
    sig { params(entry: Entry).void }
    def retry_checks!(entry)
      result = with_retry { @command.retry_checks!(entry) }

      case result
      when ICommand::Result::Error
        # We have failed to kick of a CI retry.
        # It should be safe to retry from here.
        raise result.as_exception
      end

      now = Time.current

      # TODO: We need to track the request time stamp on a per check basis. If we don't, we may end up with invalid
      # timeouts detected.
      result = update_entries([entry]) do |e|
        e.requested_checks.each do |check|
          if check.retryable?
            check.state = Entry::RequestedCheck::State::Pending
            check.attempts += 1
            check.requested_at = now
          end
        end

        e.attempts += 1
      end

      case result
      when ICommand::Result::Error
        # We have kicked off a CI retry, but failed to update the DB.
        # It should still be safe to retry from here: worst case we
        # end up running CI twice for this commit.
        raise result.as_exception
      end
    end

    sig { void }
    def recalculate_positions!
      # We don't need to do this if there's nothing to evaluate.
      return if @entries.empty?

      result = with_retry { @command.recalculate_positions!(@entries) }

      case result
      when ICommand::Result::Error
        # We have failed to kick of a CI retry.
        # It should be safe to retry from here.
        raise result.as_exception
      end
    end

    private

    sig { returns(T::Boolean) }
    def require_checks? = @require_checks

    sig { returns(T::Boolean) }
    def fast_forward_enabled?
      @configuration.fast_forward_pull_requests && @command.feature_enabled?(:merge_queue_fast_forward)
    end

    # When a stacked entry becomes unmergeable, cascade that failure to all
    # descendant entries in the same stack (higher stack_position).
    sig { params(entry: Entry).void }
    def cascade_stack_invalidation!(entry)
      return unless entry.unmergeable?
      return unless stack_id = entry.stack_id

      descendants = @entries.stack_descendants_of(entry).reject(&:unmergeable?)

      if descendants.any?
        update_entries(descendants) do |descendant|
          descendant.state = Entry::State::Unmergeable.stack_invalidated
        end
      end
    end

    # Determine if the entry is eligible for a fast-forward merge attempt.
    sig { params(entry: Entry, base_sha: String).returns(T::Boolean) }
    def can_fast_forward?(entry:, base_sha:)
      return false unless fast_forward_enabled?
      return false unless entry.queued?
      return false unless base_sha == entry.enqueued_base_sha
      return false unless entry.fast_forward_not_attempted?

      enqueued_head_sha = entry.enqueued_head_sha
      return false unless enqueued_head_sha

      @command.fast_forwardable?(entry:, head_sha: enqueued_head_sha, base_sha:)
    end

    # Remove a collection of Entries from the Merge Queue.
    # This is partially reimplemented in Merger#dequeue!, any changes here should mirror over to that method.
    sig { params(entries: T::Array[Entry], reason: Entry::RemovalReason).returns(ICommand::GenericResult) }
    def dequeue(entries, reason:)
      webhooks = T.let([], T::Array[WebHook])

      entries.select { _1.head_sha.present? }
        .each { |entry| webhooks << WebHook::Destroyed.for(entry:, reason:) }

      result = with_retry { @command.remove!(entries, reason:) }

      case result
      when ICommand::Result::Success
        entries.each do |entry|
          @entries.delete(entry)
          webhooks << WebHook::Dequeued.for(entry:, reason:)
        end

        webhooks.each do |hook|
          with_retry { @command.dispatch_webhook!(hook) }
        end
      end

      result
    end

    # Persist the changes for a given collection of Entries.
    sig do
      params(
        entries: T::Array[Entry],
        block: T.proc.params(arg0: Entry).void
      ).returns(ICommand::GenericResult)
    end
    def update_entries(entries, &block)
      entries.each(&block)
      with_retry { @command.update!(entries) }
    end

    # Determine if the number of active checks is more than the user allowed value.
    sig { returns(T::Boolean) }
    def available_space_to_build?
      @entries.count(&:awaiting_checks?) < max_concurrency
    end

    # Returns the effective max concurrency, clamped to a minimum of 1 when the
    # feature flag is enabled. This prevents a zero-concurrency configuration
    # from starving the queue of builds.
    sig { returns(Integer) }
    memoize def max_concurrency
      if @command.feature_enabled?(:merge_queue_clamp_max_concurrency)
        [@configuration.max_concurrency, 1].max
      else
        @configuration.max_concurrency
      end
    end

    # Determine which entries should be removed from the queue.
    # When the head entry is part of a stack, all same-stack entries are included.
    sig { returns(T::Array[Entry]) }
    def removable_entries
      return [] unless first_entry = @entries.first
      return [] if first_entry.locked?
      return [] unless first_entry.unmergeable?

      # Solo entries will never be a part of a group.
      if first_entry.solo?
        return @entries.with_stack(first_entry)
      end

      # Only allow failed checks to stay at the top of the queue to be evaluated by the grouping strategy.
      case reason = first_entry.removal_reason
      when nil, Entry::RemovalReason::FailedChecks, Entry::RemovalReason::ChecksTimedOut
        # Only failing checks are allowed. Continue on.
        nil
      when Entry::RemovalReason::Unknown, Entry::RemovalReason::Manual,
           Entry::RemovalReason::MergeConflict, Entry::RemovalReason::AlreadyMerged,
           Entry::RemovalReason::QueueCleared, Entry::RemovalReason::RollBack,
           Entry::RemovalReason::BranchProtections, Entry::RemovalReason::GitTreeInvalid,
           Entry::RemovalReason::InvalidMergeCommit, Entry::RemovalReason::Merged,
           Entry::RemovalReason::StackInvalidated, Entry::RemovalReason::StackParentUnmerged,
           Entry::RemovalReason::StackOutOfOrder
        return @entries.with_stack(first_entry)
      else
        T.absurd(reason)
      end

      case grouping_strategy = @configuration.grouping_strategy
      when IConfiguration::GroupingStrategy::AllGreen
        # All entries must be passing to be mergeable
        @entries.with_stack(first_entry)
      when IConfiguration::GroupingStrategy::HeadGreen
        # Because a potentially green head could appear, we will wait until everything is failing
        remaining_entries = @entries.after(first_entry).lazy.take_while { !_1.solo? }.take(@configuration.max_merge_entries_size - 1).to_a

        if remaining_entries.empty? || remaining_entries.all?(&:unmergeable?)
          @entries.with_stack(first_entry)
        else
          []
        end
      else
        T.absurd(grouping_strategy)
      end
    end

    # Call the block up until max_attempts number of times. Retrying only occurs when the Error object returned
    # permits retrying.
    sig do
      type_parameters(:T).params(
        max_attempts: Integer,
        block: T.proc.returns(T.all(ICommand::Result, T.type_parameter(:T)))
      ).returns(T.type_parameter(:T))
    end
    def with_retry(max_attempts = 3, &block)
      ICommand::Result.with_retry(max_attempts, &block)
    end
  end
end
