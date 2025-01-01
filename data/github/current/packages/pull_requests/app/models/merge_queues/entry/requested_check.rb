# typed: strict
# frozen_string_literal: true

module MergeQueues
  # All of the data around a specific check required to satisfy Branch Protection rules.
  class Entry::RequestedCheck < T::Struct
    class State < T::Enum
      enums do
        Pending = new(:pending)
        Failed = new(:failed)
        Success = new(:success)
      end
    end

    const :name, String
    # TODO: We can potentialy move `requested_at` to a collection of RequestCheckAttempt objects that track the state
    # of each attempt. This will allow us to be more accurate with our timeout logic.
    prop :attempts, Integer, default: 1
    const :max_attempts, Integer
    prop :state, State, default: State::Pending
    const :supports_retry, T::Boolean, default: false
    prop :requested_at, Time
    const :timeout_after, ActiveSupport::Duration

    sig { returns(T::Boolean) }
    def dead?
      failed_or_timed_out? && !retryable?
    end

    sig { returns(T::Boolean) }
    def failed?
      state == State::Failed
    end

    sig { returns(T::Boolean) }
    def timed_out?
      state == State::Pending && timeout_after.after(requested_at) < Time.current
    end

    sig { returns(T::Boolean) }
    def failed_or_timed_out?
      failed? || timed_out?
    end

    sig { returns(T::Boolean) }
    def success?
      state == State::Success
    end

    sig { returns(T::Boolean) }
    def pending?
      state == State::Pending
    end

    # Determine if this check is eligible to be retried.
    sig { returns(T::Boolean) }
    def retryable?
      if failed? || timed_out?
        supports_retry && attempts_remaining?
      else
        false
      end
    end

    sig { returns(T::Boolean) }
    def attempts_remaining?
      attempts < max_attempts
    end

    # T::Struct does not implement `==` so we need to do it ourselves.
    sig { params(other: T.untyped).returns(T::Boolean) }
    def ==(other)
      if other.is_a?(Entry::RequestedCheck)
        name == other.name &&
        attempts == other.attempts &&
        max_attempts == other.max_attempts &&
        state == other.state &&
        supports_retry == other.supports_retry &&
        requested_at == other.requested_at &&
        timeout_after == other.timeout_after
      else
        false
      end
    end
  end
end
