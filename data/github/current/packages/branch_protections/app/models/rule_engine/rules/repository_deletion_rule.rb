# typed: strict
# frozen_string_literal: true

module RuleEngine
  module Rules
    class RepositoryDeletionRule < RepositoryOperationRule
      sig { void }
      def initialize
        super(rule_name: "restrict_repo_delete",
              display_name: "Block repository deletion",
              description: "Only allow users on the Allowed list to delete repositories.",
              operation_keys: [:delete],
              feature_flag: :member_privilege_rulesets)
      end
    end
  end
end
