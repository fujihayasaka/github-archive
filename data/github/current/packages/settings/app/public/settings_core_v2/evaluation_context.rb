# typed: strict
# frozen_string_literal: true

module SettingsCoreV2
  class EvaluationContext
    extend T::Generic

    Value = type_member

    sig { returns(T.untyped) }
    attr_reader :resource

    sig { returns(String) }
    attr_reader :setting_name

    sig { returns(T.nilable(Value)) }
    attr_reader :current_value

    sig { returns(T.nilable(T::Array[Value])) }
    attr_accessor :current_allowed_values

    sig { returns(T::Hash[T.nilable(T::Class[T.untyped]), T::Array[Value]]) }
    attr_reader :child_allowed_values

    sig { returns(T::Array[EvaluationContext[Value]]) }
    attr_reader :parent_contexts

    sig { params(resource: T.untyped, setting_name: String, current_value: T.nilable(Value), current_allowed_values: T.nilable(T::Array[Value]), child_allowed_values: T::Hash[T.nilable(T::Class[T.untyped]), T::Array[Value]], parent_contexts: T::Array[EvaluationContext[Value]]).void }
    def initialize(resource, setting_name, current_value, current_allowed_values: nil, child_allowed_values: {}, parent_contexts: [])
      @resource = resource
      @setting_name = setting_name
      @current_value = current_value
      @current_allowed_values = current_allowed_values
      @parent_contexts = parent_contexts
      @child_allowed_values = child_allowed_values
    end

    sig { void }
    def clear_allowed_value_limitations
      @child_allowed_values = {}
    end

    sig { params(allowed_values: T::Array[Value], node_type: T.nilable(T::Class[T.untyped])).void }
    def set_allowed_values(allowed_values, node_type: nil)
      @child_allowed_values[node_type] = allowed_values
    end

    sig { params(value: Value).returns(T::Boolean) }
    def is_value_allowed?(value)
      @current_allowed_values.nil? || @current_allowed_values.include?(value)
    end

    sig { params(value: Value, check_allowed: T::Boolean).void }
    def set_current_value(value, check_allowed: true)
      if !check_allowed || is_value_allowed?(value)
        @current_value = value
      end
    end
  end
end
