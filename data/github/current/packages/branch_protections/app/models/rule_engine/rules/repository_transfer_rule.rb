# typed: true
# frozen_string_literal: true

module RuleEngine
  module Rules
    class RepositoryTransferRule < RepositoryOperationRule

      def initialize
        super(
          rule_name: "repository_transfer",
          display_name: "Restrict transfers",
          description: "Only allow users on the allow list to transfer repositories out of the organization",
          operation_keys: [:transfer],
          feature_flag: :member_privilege_rulesets
        )
      end
    end
  end
end
