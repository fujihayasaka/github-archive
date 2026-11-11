# typed: true
# frozen_string_literal: true

class MergeConditions::EvaluationResult
  attr_reader :errors

  PASSED = :passed
  FAILED = :failed

  def initialize
    @errors = []
  end

  sig { returns(Symbol) }
  def result
    errors.any? ? FAILED : PASSED
  end
end
