# typed: strict
# frozen_string_literal: true

module Discussion::StateReasonable
  extend ActiveSupport::Concern
  extend T::Sig
  extend T::Helpers

  requires_ancestor { ActiveRecord::Base }

  # All state reasons that can exist.
  class StateReason < T::Enum
    extend T::Sig

    enums do
      Resolved  = new
      Outdated  = new
      Duplicate = new
      Reopened  = new
    end

    sig { returns(String) }
    def description
      case self
      when Resolved
        "The discussion has been resolved"
      when Outdated
        "The discussion is no longer relevant"
      when Duplicate
        "The discussion is a duplicate of another"
      when Reopened
        "The discussion was reopened"
      else T.absurd(self)
      end
    end
  end

  # State reasons that can be used to close a discussion.
  # This should always be a subset of `StateReason` enums.
  class CloseReason < T::Enum
    extend T::Sig

    enums do
      Resolved  = new
      Outdated  = new
      Duplicate = new
    end

    sig { returns(String) }
    def description
      self.to_state_reason.description
    end

    private

    sig { returns(StateReason) }
    def to_state_reason
      case self
      when Resolved
        StateReason::Resolved
      when Outdated
        StateReason::Outdated
      when Duplicate
        StateReason::Duplicate
      else T.absurd(self)
      end
    end
  end

  included do
    T.bind(self, T.class_of(ActiveRecord::Base))

    enum :state_reason, {
      StateReason::Resolved.serialize  => 0,
      StateReason::Outdated.serialize  => 1,
      StateReason::Duplicate.serialize => 2,
      StateReason::Reopened.serialize  => 3,
    }, prefix: true

    validates :state_reason, presence: true, if: :closed?
  end
end
