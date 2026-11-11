# typed: strict
# frozen_string_literal: true

module RuleEngine
  module Errors
    # Error raised when the number of ref updates in a push exceeds the limit
    class RefLimitReached < StandardError
      THRESHOLD = 1000
    end
  end
end
