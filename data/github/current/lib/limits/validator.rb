# typed: true
# frozen_string_literal: true

class Limits::Validator
  # Raised when a limit value being set is invalid.
  class LimitValueError < StandardError; end

  # Validate a provided limit value.
  #
  # value - String/Integer representing the proposed limit value.
  #
  # Returns Integer.
  # Raises Limits::Validator::LimitValueError.
  def self.validate_limit_value!(value)
    message = "Limit values must be integers that are 0 or greater."

    begin
      result = Integer(value)
    rescue TypeError, ArgumentError
      raise LimitValueError.new(message)
    end

    raise LimitValueError.new(message) if result < 0
    result
  end

  # Validate a soft and hard limit combination.
  #
  # soft_limit - String/Integer representing a soft limit value.
  # hard_limit - String/Integer representing a hard limit value.
  #
  # Returns Array<Integer>: Soft limit value and hard limit value as Integers.
  # Raises Limits::Validator::LimitValueError.
  def self.validate_soft_and_hard_limits!(soft_limit:, hard_limit:)
    soft_limit_value = validate_limit_value!(soft_limit)
    hard_limit_value = validate_limit_value!(hard_limit)
    if soft_limit_value >= hard_limit_value
      raise LimitValueError.new("Soft limit values must be less than their corresponding hard limit values.")
    end

    [soft_limit_value, hard_limit_value]
  end
end
