# typed: strict
# frozen_string_literal: true

module MergeQueues
  class Merger
    extend T::Sig
    extend T::Generic

    sig { params(command: ICommand).void }
    def initialize(command:)
      @command = command
    end

    sig do
      params(
        group: T.any(Group[Entry], Group[MergeQueueEntry]),
        merge_method: IConfiguration::MergeMethod,
        merge_action: T.nilable(Symbol),
        actor: T.nilable(User),
      ).returns(ICommand::MergeResult)
    end
    def merge!(group, merge_method:, merge_action: nil, actor: nil)
      expected_base_sha = T.must_because(group.base_entry!.base_sha) { "mergeable entries must have a base_sha" }

      merge_result = with_retry { @command.merge!(group.head_entry!, actor:, expected_base_sha:) }

      case merge_result
      when ICommand::Result::MergeSuccess
        result = with_retry do
          GitHub.logger.with_named_tags(
            "gh.group.base_sha": expected_base_sha,
            "gh.group.head_sha": group.head_entry!.head_sha,
            "gh.group.entries.count": group.entries.count,
          ) do
            @command.finalize_rule_suite_records!(group.entries, merge_method:)
          end
        end

        case result
        when ICommand::Result::Error
          # Failed to save at least one RuleSuite record; log this error.
          Failbot.report(result.as_exception)
        end

        result = with_retry do
          @command.update_merged_pull_requests!(
            group.entries,
            merge_result:,
            merge_method:,
            merge_action:,
          )
        end

        case result
        when ICommand::Result::Error
          # We have successfully merged, but failed to update DB state.
          # Retrying now could lead to duplicate commits.
          Failbot.report(result.as_exception)
        end

        dequeue!(group.entries, reason: Entry::RemovalReason::Merged)

        result = with_retry { @command.record_merge_stats!(group.entries, merge_result:) }

        case result
        when ICommand::Result::Error
          # Recording stats is not critical; don't end the MQ run for this error
          Failbot.report(result.as_exception)
        end
      when ICommand::Result::AlreadyMergedError
        dequeue!(group.entries, reason: Entry::RemovalReason::AlreadyMerged)
      when ICommand::Result::BranchProtectionError
        result = with_retry { @command.record_merge_group_failure!(group.entries, merge_result:, merge_method:) }

        case result
        when ICommand::Result::Error
          # Failed to persist the RuleSuite record from @command.merge! failure. Log this error.
          Failbot.report(result.as_exception)
        end
      when ICommand::Result::Error
        # No-op: let the caller handle the error
      else
        T.absurd(merge_result)
      end

      merge_result
    end

    private

    # Remove a collection of Entries from the Merge Queue, or raise
    # This reimplements logic from DecisionEngine#dequeue, any changes here should mirror over to that method.
    #
    # pull_request.dequeue webhook is delivered in the `post_merge` background job.
    sig do
      params(
        entries: T::Array[T.any(Entry, MergeQueueEntry)],
        reason: Entry::RemovalReason,
      ).void
    end
    def dequeue!(entries, reason:)
      result = with_retry { @command.remove!(entries, reason:) }

      case result
      when ICommand::Result::Success
        # No-op
      when ICommand::Result::Error
        raise result.as_exception
      else
        T.absurd(result)
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
