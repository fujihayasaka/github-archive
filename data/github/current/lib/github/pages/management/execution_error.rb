# typed: true
# frozen_string_literal: true

module GitHub::Pages::Management
  # ExecutionError is the top-most error thrown when execution of any management script goes awry.
  class ExecutionError < RuntimeError
  end
end
