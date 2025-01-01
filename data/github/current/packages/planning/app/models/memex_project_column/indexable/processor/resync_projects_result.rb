# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Indexable::Processor
  class ResyncProjectsResult < ProcessedResult
    extend T::Sig

    sig { returns(Base::GenericHash) }
    def outcome
      return { failure_reason: @failure_reason } if @failure_reason

      {}
    end

    sig { returns(T.nilable(T.noreturn)) }
    private def validate_input!
      if FailureReason.invalid?(@failure_reason)
        raise ArgumentError.new("Invalid failure_reason")
      end
    end
  end
end
