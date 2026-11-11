# typed: strict
# frozen_string_literal: true

module SettingsCoreV2
  module IConditionExpression
    extend T::Helpers
    include Kernel

    abstract!

    sig { abstract.returns(T.nilable(String)) }
    def targetable_attribute; end

    sig { abstract.returns(String) }
    def operation; end

    sig { abstract.returns(T.nilable(T.any(String, T::Array[String]))) }
    def value; end

    sig { abstract.returns(T::Array[IConditionExpression]) }
    def child_condition_expressions; end

    sig { abstract.returns(T.nilable(IConditionExpression)) }
    def root_condition_expression; end

    sig { abstract.returns(T.nilable(Integer)) }
    def id; end

    sig { params(other: T.untyped).returns(T::Boolean) }
    def ==(other)
      return true if super
      return false unless other.is_a?(self.class)
      id == other.id &&
        targetable_attribute == other.targetable_attribute &&
        operation == other.operation &&
        value == other.value &&
        child_condition_expressions.to_a == other.child_condition_expressions.to_a
    end
    alias eql? ==

    sig { returns(Integer) }
    def hash
      [id, targetable_attribute, operation, value, child_condition_expressions.to_a].hash
    end

    # Splits a targetable attribute into its base attribute name and an optional
    # sub-type. Attributes may be formatted as
    # "repository.custom_properties[prop_name]", where the bracketed portion is
    # the sub-type (e.g. a custom property name). Returns [nil, nil] for a blank
    # attribute.
    sig { params(attribute: T.nilable(String)).returns([T.nilable(String), T.nilable(String)]) }
    def self.split_attribute(attribute)
      match = attribute.to_s.match(/([^\[]+)(?:\[(.+)\])?/)
      return [nil, nil] unless match
      [match[1], match[2]]
    end

    sig { params(resource: T.untyped, matchers: T::Array[ConditionMatcher], overrides: T.nilable(T::Array[AttributeOverride])).returns(T::Boolean) }
    def evaluate(resource, matchers, overrides: nil)
      operation = Operation.from_serialized(self.operation)

      if operation == IConditionExpression::Operation::ALL
        true
      elsif operation == IConditionExpression::Operation::AND && child_condition_expressions.any?
        child_condition_expressions.all? { |child| child.evaluate(resource, matchers, overrides:) }
      elsif operation == IConditionExpression::Operation::OR && child_condition_expressions.any?
        child_condition_expressions.any? { |child| child.evaluate(resource, matchers, overrides:) }
      else
        attribute_name, sub_type = IConditionExpression.split_attribute(targetable_attribute)

        matcher = matchers.find { |m| m.attribute == attribute_name }
        return false unless matcher

        override = overrides&.find { |ao| ao.resource == resource && ao.attribute == targetable_attribute }&.override
        actual_value = override.nil? ? matcher.effective_value(resource, sub_type) : override

        case operation
        when IConditionExpression::Operation::EQ
          actual_value == value
        when IConditionExpression::Operation::NE
          actual_value != value
        when IConditionExpression::Operation::IN
          Array(value).include?(actual_value)
        when IConditionExpression::Operation::NIN
          !Array(value).include?(actual_value)
        else
          false
        end
      end
    end

    sig { returns(T::Hash[String, T.untyped]) }
    def serialize
      result = {
        "id" => id,
        "targetableAttribute" => targetable_attribute,
        "operation" => operation,
        "value" => value,
      }

      if child_condition_expressions.any?
        result["childConditionExpressions"] = child_condition_expressions.map do |child|
          child.serialize
        end
      end

      result
    end

    class Operation < T::Enum
      enums do
        AND = new("and")
        OR = new("or")
        EQ = new("eq")
        NE = new("ne")
        IN = new("in")
        NIN = new("nin")
        ALL = new("all")
      end
    end
  end
end
