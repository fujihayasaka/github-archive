# typed: strict
# frozen_string_literal: true

module RuleEngine
  module IRuleset
    extend T::Helpers
    include Timing

    requires_ancestor { Object }

    abstract!

    sig { abstract.returns(T.nilable(Integer)) }
    def id; end

    sig { abstract.returns(String) }
    def name; end

    sig { abstract.returns(T.untyped) }
    def source; end

    sig { abstract.returns(String) }
    def source_type; end

    sig { abstract.params(viewing_source: T.untyped).returns(String) }
    def display_source_type(viewing_source: nil); end

    sig { abstract.returns(Integer) }
    def source_id; end

    sig { abstract.returns(String) }
    def target; end

    sig { abstract.returns(String) }
    def enforcement; end

    sig { abstract.returns(T::Enumerable[RuleEngine::IRuleConfig]) }
    def rule_configurations; end

    sig { abstract.returns(T::Enumerable[RuleEngine::IRuleCondition]) }
    def conditions; end

    sig { abstract.returns(T::Enumerable[T.untyped]) }
    def bypass_actors; end

    sig { abstract.returns(T::Enumerable[T.untyped]) }
    def histories; end

    sig { abstract.returns(RuleEngine::RuleProviders::RulesetRuleProvider) }
    def rule_provider; end

    sig { abstract.returns(T::Boolean) }
    def enabled?; end

    sig { abstract.returns(T::Boolean) }
    def evaluate?; end

    sig { abstract.returns(T::Boolean) }
    def disabled?; end

    sig { abstract.returns(RulesetDefinitions::RulesetDefinition) }
    def definition; end

    sig { abstract.params(rule_type: String, parameters: T::Hash[String, T.untyped]).returns(T::Hash[String, T.untyped]) }
    def apply_default_parameters(rule_type, parameters); end

    sig do
      abstract.params(
        targetable: Targeting::Targetable,
        target_object: RuleEngine::Conditions::ConditionTarget::TargetObject
      ).returns(T::Boolean)
    end
    def satisfies_conditions?(targetable, target_object); end

    sig do
      abstract.params(targetable: Targeting::Targetable)
      .returns(T::Boolean)
    end
    def should_evaluate?(targetable); end

    sig do
      abstract.type_parameters(:T)
        .params(targetables: T::Enumerable[T.all(Targeting::Targetable, T.type_parameter(:T))])
        .returns(T::Array[T.all(Targeting::Targetable, T.type_parameter(:T))])
    end
    def bulk_filter_targetable(targetables); end

    sig { abstract.returns(T::Array[RuleEngine::Conditions::ConditionTarget::TargetObject]) }
    def missing_condition_targets; end

    sig { abstract.params(allow_upsell: T::Boolean).returns(T::Array[String]) }
    def available_rule_types(allow_upsell: false); end

    sig { abstract.returns(DomainAccessorBase[T.untyped]) }
    def domain; end

    class ConditionValidationError < StandardError
      sig { returns(T.untyped) }
      attr_reader :errors

      sig { returns(T.untyped) }
      attr_reader :parameter_instance

      sig { params(parameter_instance: T.untyped, errors: T.untyped).void }
      def initialize(parameter_instance, errors)
        @parameter_instance = parameter_instance
        @errors = errors
      end

      sig { returns(T::Array[String]) }
      def parse_error_messages
        pattern_errors, other_errors = errors.partition { |error| error[:error_code] == :invalid && error[:sub_errors]&.any? { |sub_error| sub_error[:error_code] == :invalid_pattern } }
        failed_patterns = pattern_errors.flat_map do |error|
          error[:sub_errors].filter_map do |sub_error|
            next unless sub_error[:error_code] == :invalid_pattern
            sub_error[:value]
          end
        end
        messages = other_errors.flat_map { |error| error[:message] }.compact
        messages << "Invalid target patterns: \'#{failed_patterns.uniq.join("\', \'")}\'" if failed_patterns.present?
        messages
      end
    end

    class RuleValidationError < StandardError
      sig { returns(T.untyped) }
      attr_reader :errors

      sig { params(errors: T.untyped).void }
      def initialize(errors)
        @errors = T.let(errors, T.untyped)
      end
    end

    class BypassActorsLimitError < StandardError
      MESSAGE = "The ruleset bypass actor limit has been reached."

      sig { returns(String) }
      def message
        MESSAGE
      end
    end

    class InvalidTarget < StandardError
      sig { returns(String) }
      attr_reader :message

      sig { params(target: T.untyped).void }
      def initialize(target)
        @message = T.let("'#{target}' is not a valid target", String)
      end
    end

    class InvalidSource < StandardError
      sig { returns(String) }
      attr_reader :message

      sig { params(source: T.untyped).void }
      def initialize(source)
        @message = T.let("'#{source}' is not a valid source", String)
      end
    end

    # A general error class we can use to rescue ruleset specific errors
    class Error < StandardError
      sig { returns(String) }
      attr_reader :message

      sig { params(message: String).void }
      def initialize(message)
        @message = T.let(message, String)
      end
    end

    # Class-level interface for ruleset classes.
    # Any class including IRuleset must implement these class methods to work
    # with RuleSettingsDependency's polymorphic dispatch.
    module ClassMethods
      extend T::Helpers

      abstract!

      sig { abstract.returns(T::Hash[T.any(String, Symbol), Integer]) }
      def targets; end

      sig { abstract.returns(T::Hash[T.any(String, Symbol), Integer]) }
      def enforcements; end
    end

    mixes_in_class_methods(ClassMethods)
  end
end
