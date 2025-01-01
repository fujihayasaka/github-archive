# typed: strict
# frozen_string_literal: true

module RuleEngine
  module Rules
    class RepositoryOperationRule < BulkRunnableRule

      sig { returns(T::Array[Symbol]) }
      attr_reader :operation_keys

      # Example rule for deleting repos
      # RepositoryOperationRule.new(:restrict_repo_delete, "Restrict repository deletion", "Restrict the ability for users to delete repositories", :delete)

      sig { params(rule_name: String, display_name: String, description: String, operation_keys: T::Array[Symbol], feature_flag: T.nilable(Symbol)).void }
      def initialize(rule_name:, display_name:, description:, operation_keys:, feature_flag: nil)
        super(rule_name:, display_name:, description:, feature_flag:)
        @operation_keys = operation_keys
      end

      sig { override.returns(T::Array[Symbol]) }
      def supported_source_types
        [:organization, :business]
      end

      sig { override.returns(T::Array[Symbol]) }
      def supported_target_types
        [:member_privilege]
      end

      sig { params(source: T.nilable(Types::RuleSource)).returns(T::Boolean) }
      def is_user_configurable?(source = nil)
        true
      end

      sig do
        override.params(
          event: RuleEngine::RuleEvent,
          rule_configs_by_action: T::Hash[RuleEvent::EventAction, T::Array[RepositoryRuleConfiguration]]
        )
        .returns(T::Array[RuleEngine::RuleRun])
      end
      def run_evaluation(event, rule_configs_by_action)
        rule_configs_by_action.flat_map do |action, rule_configs|
          next unless action.is_a?(Events::RepositoryOperationEvent::Operation)
          next unless operation_keys.include?(action.operation_key)

          rule_configs.map do |rule_config|
            RuleRun.failure(event_action: action, rule_config:, message: "Can't do that") # TODO: Add a real message
          end
        end.compact
      end
    end
  end
end
