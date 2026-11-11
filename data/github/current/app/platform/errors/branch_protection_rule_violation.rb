# typed: true
# frozen_string_literal: true

module Platform
  module Errors
    class BranchProtectionRuleViolation < Errors::Execution
      def initialize(message)
        super("BRANCH_PROTECTION_RULE_VIOLATION", message)
      end
    end
  end
end
