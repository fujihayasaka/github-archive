# typed: strict
# frozen_string_literal: true

module SettingsCore
  module IConditionExpression
    extend T::Helpers
    include Kernel

    abstract!

    sig { abstract.returns(T.nilable(String)) }
    def targetable_attribute; end

    sig { abstract.returns(String) }
    def operation; end

    sig { abstract.returns(T.nilable(String)) }
    def value; end

    sig { abstract.returns(T::Array[IConditionExpression]) }
    def child_condition_expressions; end

    sig { abstract.returns(T.nilable(IConditionExpression)) }
    def root_condition_expression; end

    sig { abstract.returns(T.nilable(Integer)) }
    def id; end

    class Operation < T::Enum
      enums do
        AND = new("and")
        OR = new("or")
        ANY = new("any")
        EQ = new("eq")
        NE = new("ne")
        IN = new("in")
        NIN = new("nin")
      end

      sig { returns(T::Boolean) }
      def child_operation?
        [AND, OR].include?(self)
      end
    end

    sig { params(targetable: Targeting::Targetable).returns(EvaluateResult) }
    def evaluate(targetable)
      operation = Operation.from_serialized(self.operation)
      if operation.child_operation?
        if operation == Operation::AND
          return EvaluateResult::MATCH if child_condition_expressions.all? { |exp| exp.evaluate(targetable) == EvaluateResult::MATCH }
          return EvaluateResult::NO_MATCH
        elsif operation == Operation::OR
          return EvaluateResult::MATCH if child_condition_expressions.any? { |exp| exp.evaluate(targetable) == EvaluateResult::MATCH }
          return EvaluateResult::NO_MATCH
        else
          raise ArgumentError, "Unknown operation: #{operation}"
        end
      end

      attribute = Targeting::Attribute.from_serialized(targetable_attribute)

      matching_values = targetable.get_all_attributes(attribute)
      if matching_values.empty?
        return EvaluateResult::MISSING_ATTRIBUTE
      end

      case operation
      when Operation::ANY
        EvaluateResult::MATCH
      when Operation::EQ
        value = T.must(self.value)
        return EvaluateResult::MATCH if matching_values.include?(value)
        EvaluateResult::NO_MATCH
      when Operation::NE
        value = T.must(self.value)
        return EvaluateResult::MATCH if matching_values.exclude?(value)
        EvaluateResult::NO_MATCH
      when Operation::IN
        value = self.value&.split(",")&.map(&:strip) || []
        return EvaluateResult::MATCH if (value & matching_values).any?
        EvaluateResult::NO_MATCH
      when Operation::NIN
        value = self.value&.split(",")&.map(&:strip) || []
        return EvaluateResult::MATCH unless (value & matching_values).any?
        EvaluateResult::NO_MATCH
      else
        raise ArgumentError, "Unknown operation: #{operation}"
      end
    end

    class EvaluateResult < T::Enum
      enums do
        MATCH = new("MATCH")
        NO_MATCH = new("NO_MATCH")
        MISSING_ATTRIBUTE = new("MISSING_ATTRIBUTE")
      end
    end
  end
end
