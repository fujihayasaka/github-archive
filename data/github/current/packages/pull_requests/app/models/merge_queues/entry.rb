# typed: strict
# frozen_string_literal: true

module MergeQueues
  # Encapsulation of all required MergeQueueEntry data to execute the Merge Queue.
  class Entry < T::Struct
    include MergeQueues::Group::Groupable

    # This property will be determined by various factors such as branch protections, etc. Inside of the MergeQueue
    # evaluation we only care about a single field describing state. We will need to deal with that translation while
    # loading from the database and other sources.
    prop :state, State

    # The entry is locked, i.e. this queue uses a deploy-then-merge workflow
    # and this entry is part of a group that is currently being deployed.
    prop :locked, T::Boolean, default: false

    # Database ID of the MergeQueueEntry.
    prop :merge_queue_entry_id, Integer
    prop :pull_request_number, Integer
    prop :pull_request_id, Integer
    prop :attempts, Integer, default: 0

    # The pull_request.head_sha at time of enqueue.
    prop :enqueued_head_sha, T.nilable(String)

    # The git object identifier that the ref was created from.
    prop :base_sha, T.nilable(String)

    # The git object identifier that includes all of the changes from the Pull Request.
    prop :head_sha, T.nilable(String)

    # The name of the temporary ref created that is given to CI providers.
    prop :head_ref, T.nilable(String)
    prop :created_at, Time

    # Flag determining if we should perform a merge operation with just this Entry.
    prop :solo, T::Boolean, default: false

    # The set of requested check contexts that are awaiting a response from the CI provider.
    prop :requested_checks, T::Array[Entry::RequestedCheck]

    sig { returns(T::Boolean) }
    def unmergeable?
      state.is_a? State::Unmergeable
    end

    sig { returns(T::Boolean) }
    def waiting?
      state.is_a? State::Waiting
    end

    sig { override.returns(T::Boolean) }
    def solo?
      solo
    end

    sig { override.returns(T::Boolean) }
    def locked?
      locked
    end

    sig { override.returns(T::Boolean) }
    def mergeable?
      state.is_a? State::Mergeable
    end

    sig { returns(T::Boolean) }
    def awaiting_checks?
      state.is_a? State::AwaitingChecks
    end

    sig { override.returns(T::Boolean) }
    def queued?
      state.is_a? State::Queued
    end

    sig { returns(T::Boolean) }
    def active_build?
      case current_state = state
      when Entry::State::AwaitingChecks,
          Entry::State::Mergeable,
          Entry::State::Unmergeable
        true
      when Entry::State::Queued,
          Entry::State::Waiting
        false
      else
        T.absurd(current_state)
      end
    end

    sig { returns(T::Boolean) }
    def merge_conflict?
      case current_state = state
      when State::Unmergeable
        current_state.reason == RemovalReason::MergeConflict
      else
        false
      end
    end

    sig { returns(T::Boolean) }
    def failing_checks?
      requested_checks.any? { |check| check.failed? && !check.retryable? }
    end

    sig { returns(T::Boolean) }
    def timed_out_checks?
      case current_state = state
      when State::Unmergeable
        current_state.reason == RemovalReason::ChecksTimedOut
      when State::AwaitingChecks
        requested_checks.any? { |check| check.timed_out? && !check.retryable? }
      else
        false
      end
    end

    sig { returns(T::Boolean) }
    def retryable_checks?
      failing_checks = requested_checks.filter(&:failed_or_timed_out?)
      return false if failing_checks.empty?
      failing_checks.all?(&:retryable?)
    end

    sig { returns(T::Boolean) }
    def passing_checks?
      requested_checks.any? && requested_checks.all?(&:success?)
    end

    sig { returns(T::Set[String]) }
    def retryable_check_contexts
      requested_checks.filter(&:retryable?).map(&:name).to_set
    end

    sig { returns(T::Boolean) }
    def pending_checks?
      requested_checks.any? { |check| check.pending? && !check.timed_out? }
    end

    sig { returns(T.nilable(ActiveSupport::TimeWithZone)) }
    def checks_requested_at
      case current_state = state
      when State::AwaitingChecks
        current_state.checks_requested_at
      end
    end

    sig { returns(T.nilable(RemovalReason)) }
    def removal_reason
      case current_state = state
      when Entry::State::Unmergeable
        current_state.reason
      end
    end

    sig { returns(String) }
    def to_logging_s
      "##{pull_request_number}: #{to_state_s}"
    end

    sig { returns(String) }
    def to_state_s
      case current_state = state
      when State::AwaitingChecks
        total_checks = requested_checks.count
        unsettled_checks = requested_checks.count { |entry| entry.pending? && !entry.timed_out? }
        settled_checks = total_checks - unsettled_checks
        "#{current_state.name} (#{settled_checks}/#{total_checks})"
      when State::Unmergeable
        "#{current_state.name} (#{current_state.reason.serialize})"
      else
        current_state.name
      end
    end
  end
end
