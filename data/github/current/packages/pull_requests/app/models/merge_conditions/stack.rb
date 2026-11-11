# typed: strict
# frozen_string_literal: true

module MergeConditions
  class Stack < BaseMergeCondition
    Payload = PullRequests::PageData::MergeBox::MergeRequirementsPayload

    sig { params(pull_request: PullRequest, user: User, merge_method: T.nilable(Symbol), skip_checks: T::Boolean).void }
    def initialize(pull_request, user, merge_method, skip_checks: false)
      super

      @entry = T.let(nil, T.nilable(PullRequests::StackEntry))
      @entries = T.let([], T::Array[PullRequests::StackEntry])
      @entry_failed_subconditions = T.let(
        {},
        T::Hash[Integer, T::Array[Payload::FailingSubConditionPayload]]
      )
    end

    sig { override.returns(String) }
    def display_name = "Stacked PR conditions"

    sig { override.returns(String) }
    def description = "Stacked pull requests must be up-to-date to merge"

    sig { override.returns(T.nilable(String)) }
    def message = evaluation_result.errors.first

    sig { override.returns(Payload::StackMergeConditionPayload) }
    def condition_payload
      Payload::StackMergeConditionPayload.new(
        type: merge_condition_type,
        displayName: display_name,
        description: description,
        message: message,
        result:  Payload::MergeConditionResult.deserialize(result.to_s.upcase),

        # Stack-specific properties
        isStacked: @entry.present?,
        entries: entries_payload,
      )
    end

    sig { returns(T::Array[Payload::StackEntryPayload]) }
    private def entries_payload
      return [] if @entry.nil?
      @entries.reverse.map do |entry|
        pull = T.must(entry.pull_request)

        position = if entry.position < @entry.position
          Payload::StackEntryPosition::Before
        elsif entry.position == @entry.position
          Payload::StackEntryPosition::Current
        else
          Payload::StackEntryPosition::After
        end

        Payload::StackEntryPayload.new(
          pull: PullRequests::PageData::Stack::Payload::StackedPullRequestData.new(
            number: pull.number,
            title: pull.title,
            state: PullRequest::Icon::State.for_pull_request(pull).to_s.upcase,
            url: T.must(pull.permalink(include_host: false)),
            headOid: pull.head_sha,
            isUnstackable: pull.is_unstackable?,
          ),
          failedSubConditions: @entry_failed_subconditions[entry.id],
          position:,
        )
      end
    end

    sig { override.returns(Promise[T.untyped]) }
    def async_condition
      return Promise.resolve(nil) unless FeatureFlag.vexi.enabled?(
        :pull_request_stacks,
        [pull_request.repository, user].compact,
        default: false,
      )

      pull_request.async_stack_entry.then do |stack_entry|
        @entry = stack_entry

        # Pull request is not part of a stack.
        next if stack_entry.nil?

        async_find_stack_entries(stack_entry).then do |_stack, entries|
          @entries = entries

          stack_entry_and_parents = entries.select { _1.position <= stack_entry.position }

          check_positions_valid(stack_entry_and_parents)

          unmerged_entries = stack_entry_and_parents.reject { _1.pull_request&.merged? }

          check_stack_state(unmerged_entries)
          check_no_conflicts(unmerged_entries)

          if unmerged_entries.size > 2
            # Ensure the history is linear.
            check_branch_refs(unmerged_entries)
            check_commit_ancestry(unmerged_entries)
          end
        end
      end
    end

    private

    sig { params(entries: T::Array[PullRequests::StackEntry]).void }
    def check_branch_refs(entries)
      entries.each_cons(2) do |previous_entry, entry|
        entry = T.must(entry)
        pull = T.must(entry.pull_request)
        previous_entry = T.must(previous_entry)
        previous_pull = T.must(previous_entry.pull_request)

        if pull.base_ref != previous_pull.head_ref
          type = "Broken stack"
          message = "PR ##{pull.number}'s base branch is not PR ##{previous_pull.number}'s head branch."

          evaluation_result.errors << "#{type}: #{message}"

          (@entry_failed_subconditions[entry.id] ||= []) << Payload::FailingSubConditionPayload.new(
            displayName: type,
            message:,
          )
        end
      end
    end

    sig { params(entries: T::Array[PullRequests::StackEntry]).void }
    def check_commit_ancestry(entries)
      # Build consecutive pairs for ancestry checking.
      entry_pairs = entries.each_cons(2).filter_map do |(previous_entry, entry)|
        [previous_entry, entry] if previous_entry && entry
      end

      commit_pairs = entry_pairs.filter_map do |(previous_entry, entry)|
        next unless pull_head_sha = T.let(entry.pull_request&.head_sha, T.nilable(String))
        next unless previous_pull_head_sha = T.let(previous_entry.pull_request&.head_sha, T.nilable(String))

        [pull_head_sha, previous_pull_head_sha]
      end

      ancestry_results = fetch_ancestry_results(commit_pairs)

      entry_pairs.zip(commit_pairs).each do |(previous_entry, entry), commit_pair|
        previous_pull = T.must(previous_entry.pull_request)
        pull = T.must(entry.pull_request)

        case is_descendant = ancestry_results[T.must(commit_pair)]
        when true
          next
        when false
          type = "Stack needs to be rebased"
          message = "PR ##{pull.number}'s branch is not a linear descendant of PR ##{previous_pull.number}'s branch."
        when Exception, nil
          type = "Unable to verify stack"
          message = "Could not verify that PR ##{pull.number}'s branch is a descendant of " \
                    "PR ##{previous_pull.number}'s branch. Please try again."
        else
          T.absurd(is_descendant)
        end

        evaluation_result.errors << "#{type}: #{message}"

        (@entry_failed_subconditions[entry.id] ||= []) << Payload::FailingSubConditionPayload.new(
          displayName: type,
          message:,
        )
      end
    end

    sig { params(commit_pairs: T::Array[[String, String]]).returns(T::Hash[[String, String], T.any(T::Boolean, Exception)]) }
    def fetch_ancestry_results(commit_pairs)
      return {} if commit_pairs.empty?

      repository = T.must(pull_request.repository)
      repository.rpc.descendant_of(commit_pairs)
    rescue => exception # rubocop:disable Style/RescueStandardError
      Failbot.report(exception)
      commit_pairs.to_h { |pair| [pair, exception] }
    end

    # Validates that position values start at 1 and are contiguous.
    sig { params(entries: T::Array[PullRequests::StackEntry]).void }
    def check_positions_valid(entries)
      positions = entries.map(&:position).sort
      return if positions.empty?

      expected_positions = (1..positions.size).to_a
      return if positions == expected_positions

      type = "Invalid stack positions"
      message = "Stack has unexpected position values."
      evaluation_result.errors << "#{type}: #{message}"
    end

    # Validates the sequential state machine of unmerged stack entries:
    # - First 0+ PRs may be enqueued (in merge queue)
    # - Remaining PRs must be open and not enqueued
    # - No PR may be closed
    # - Every entry must have an associated pull request
    sig { params(entries: T::Array[PullRequests::StackEntry]).void }
    def check_stack_state(entries)
      entries.drop_while { _1.pull_request&.in_merge_queue? }.each do |entry|
        pull = entry.pull_request

        if pull.nil?
          add_state_error(entry, pull, nil, "Pull request record is missing")
        elsif pull.in_merge_queue?
          add_state_error(entry, pull, :enqueued, "Enqueued PRs cannot appear after unenqueued PRs")
        elsif pull.closed?
          add_state_error(entry, pull, :closed, "Closed PRs are not allowed in a stack")
        end
      end
    end

    sig { params(entry: PullRequests::StackEntry, pull: T.nilable(PullRequest), state: T.nilable(Symbol), reason: String).void }
    def add_state_error(entry, pull, state, reason)
      type = "Invalid stack state"
      label = pull ? "PR ##{pull.number} is #{state}" : "Stack entry ##{entry.position} has no pull request"
      message = "#{label}. #{reason}."
      evaluation_result.errors << "#{type}: #{message}"

      (@entry_failed_subconditions[entry.id] ||= []) << Payload::FailingSubConditionPayload.new(
        displayName: type,
        message:,
      )
    end

    # Validates that no unmerged PRs in the stack have conflicts.
    sig { params(entries: T::Array[PullRequests::StackEntry]).void }
    def check_no_conflicts(entries)
      entries.each do |entry|
        next unless pull = entry.pull_request

        if pull.conflict.present?
          type = "Merge conflict"
          message = "PR ##{pull.number} has a merge conflict that must be resolved."
          evaluation_result.errors << "#{type}: #{message}"

          (@entry_failed_subconditions[entry.id] ||= []) << Payload::FailingSubConditionPayload.new(
            displayName: type,
            message:,
          )
        end
      end
    end

    sig { params(entry: PullRequests::StackEntry).returns(Promise[[PullRequests::Stack, T::Array[PullRequests::StackEntry]]]) }
    def async_find_stack_entries(entry)
      entry.async_stack.then do |stack|
        stack = T.must(stack)

        stack.async_entries.then do |entries|
          Promise.all(entries.map(&:async_pull_request)).then { [stack, entries] }
        end
      end
    end
  end
end
