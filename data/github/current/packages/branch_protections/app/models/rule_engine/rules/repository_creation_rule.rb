# typed: strict
# frozen_string_literal: true

module RuleEngine
  module Rules
    class RepositoryCreationRule < RepositoryOperationRule
      sig { void }
      def initialize
        super(rule_name: "repository_create",
              display_name: "Restrict creations",
              description: "Only allow users on the allow list to create repositories.",
              operation_keys: [:create],
              feature_flag: :member_privilege_rulesets)
      end
    end
  end
end
