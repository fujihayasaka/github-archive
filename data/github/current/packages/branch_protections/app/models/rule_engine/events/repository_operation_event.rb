# typed: strict
# frozen_string_literal: true

module RuleEngine
  module Events
    class RepositoryOperationEvent < RepositoryEvent

      sig { override.returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      attr_reader :repo_create_custom_properties

      sig do
        params(
          repository: Repository,
          actor: Types::Actor,
          operations: T::Hash[Symbol, T.untyped],
          persist_results: T::Boolean,
          repo_create_custom_properties: T.nilable(T::Hash[Symbol, T.untyped])
        ).void
      end
      def initialize(repository, actor, operations, persist_results: false, repo_create_custom_properties: nil)
        super(repository, actor)
        @operations = T.let(operations.map { |k, v| EventActionRepositoryOperation.new(repository:, operation: k, operation_value: v) }, T::Array[EventActionRepositoryOperation])
        @persist_results = persist_results
        @repo_create_custom_properties = repo_create_custom_properties
      end

      sig { override.returns(T::Array[EventActionRepositoryOperation]) }
      def event_actions
        @operations
      end

      sig { override.params(rule_suites: T::Array[RuleSuite]).returns(T::Array[RuleSuite]) }
      def finalize_rule_suites(rule_suites)
        rule_suites
      end

      sig { override.params(rule_suites: T::Array[RuleSuite]).void }
      def record_results(rule_suites)
        return unless @persist_results

        ActiveRecord::Base.connected_to(role: :writing) do
          rule_suites.filter(&:should_persist?).each do |rule_suite|
            next unless rule_suite.repository&.repo_policy_bypass_enabled?
            rule_suite.log_evaluation
            rule_suite.save!
          end
        end

        GitHub.context.push(repository_operation_event_rule_suites: rule_suites.map(&:id))
      end
    end
  end
end
