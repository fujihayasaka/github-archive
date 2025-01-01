# typed: strict
# frozen_string_literal: true

module RuleEngine
  module Rules
    class RepositoryOperationRule < BulkRunnableRule

      sig { returns(T::Array[Symbol]) }
      attr_reader :operation_keys

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
        [:repository]
      end

      sig { params(source: T.nilable(Types::RuleSource)).returns(T::Boolean) }
      def is_user_configurable?(source = nil)
        true
      end

      # Default behavior is to reject all operations matching the operation_keys
      # Override to change this
      sig do
        overridable.params(
          event: RuleEngine::Events::RepositoryOperationEvent,
          rule_configs_by_action: T::Hash[EventActionRepositoryOperation, T::Array[RepositoryRuleConfiguration]]
        )
        .returns(T::Array[RuleEngine::RuleRun])
      end
      def evaluate_operations(event, rule_configs_by_action)
        rule_configs_by_action.flat_map do |action, rule_configs|
          rule_configs.map do |rule_config|
            RuleRun.failure(event_action: action, rule_config:, message: "You are not permitted to perform that operation on this repository.")
          end
        end
      end

      sig do
        override.params(
          event: RuleEngine::RuleEvent,
          rule_configs_by_action: T::Hash[RuleEvent::EventAction, T::Array[RepositoryRuleConfiguration]]
        )
        .returns(T::Array[RuleEngine::RuleRun])
      end
      def run_evaluation(event, rule_configs_by_action)
        return [] unless event.is_a?(Events::RepositoryOperationEvent)

        filtered_actions = rule_configs_by_action.filter_map do |action, rule_configs|
          next unless action.is_a?(EventActionRepositoryOperation)
          next unless operation_keys.include?(action.operation)

          [action, rule_configs]
        end.to_h

        evaluate_operations(event, filtered_actions)
      end
    end
  end
end
