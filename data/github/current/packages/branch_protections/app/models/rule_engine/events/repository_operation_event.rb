# typed: strict
# frozen_string_literal: true

module RuleEngine
  module Events
    class RepositoryOperationEvent < RepositoryEvent
      extend T::Sig

      sig { params(repository: Repository, actor: Types::Actor, operations: T::Hash[Symbol, T.untyped], dry_run: T::Boolean).void }
      def initialize(repository, actor, operations, dry_run: false)
        super(repository, actor)
        @operations = T.let(operations.map { |k, v| Operation.new(k, v) }, T::Array[Operation])
        @dry_run = dry_run
      end

      sig { override.returns(T::Array[Operation]) }
      def event_actions
        @operations
      end

      sig { override.params(rule_suites: T::Array[RuleSuite]).returns(T::Array[RuleSuite]) }
      def finalize_rule_suites(rule_suites)
        rule_suites
      end

      class Operation
        extend T::Sig

        # Example operation
        SUPPORTED_KEYS = T.let([:create, :rename, :delete, :transfer, :change_visibility], T::Array[Symbol])

        sig { returns(Symbol) }
        attr_reader :operation_key
        sig { returns(T.nilable(String)) }
        attr_reader :operation_value

        sig { params(operation_key: Symbol, operation_value: T.nilable(String)).void }
        def initialize(operation_key, operation_value = nil)
          raise ArgumentError.new("Unsupported repository operation #{operation_key}") unless SUPPORTED_KEYS.include?(operation_key)
          @operation_key = operation_key
          @operation_value = operation_value
        end
      end
    end
  end
end
