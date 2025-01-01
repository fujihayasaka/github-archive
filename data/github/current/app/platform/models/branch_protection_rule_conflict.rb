# typed: true
# frozen_string_literal: true

module Platform
  module Models
    class BranchProtectionRuleConflict
      def initialize(branch_protection_rule, ref, conflicting_branch_protection_rule)
        @branch_protection_rule = branch_protection_rule
        @ref = ref
        @conflicting_branch_protection_rule = conflicting_branch_protection_rule
      end

      attr_reader :branch_protection_rule, :ref, :conflicting_branch_protection_rule
    end
  end
end
