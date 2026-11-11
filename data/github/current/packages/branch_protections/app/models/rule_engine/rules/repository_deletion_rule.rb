# typed: strict
# frozen_string_literal: true

module RuleEngine
  module Rules
    class RepositoryDeletionRule < RepositoryOperationRule
      sig { void }
      def initialize
        super(rule_name: "repository_delete",
              display_name: "Restrict deletions",
              description: "Only allow users on the allow list to delete repositories.",
              operation_keys: [:delete],
              feature_flag: :member_privilege_rulesets)
      end
    end
  end
end
