# typed: true
# frozen_string_literal: true

module Platform
  module Instrumentation
    class VariableInliner
      def initialize(variable_value, argument_type)
        @variable_value = variable_value
        @argument_type = argument_type
      end

      def to_ast
        value_to_ast(variable_value, argument_type)
      end

      def value_to_ast(value, type)
        type = type.of_type if type&.non_null?

        if value.nil?
          return GraphQL::Language::Nodes::NullValue.new(name: "null")
        end

        case type&.kind&.name
        when "INPUT_OBJECT"
          value = sanitze_input_object(value)

          arguments = value.map do |key, val|
            sub_type = type.arguments[key.to_s]&.type

            GraphQL::Language::Nodes::Argument.new(
              name: key.to_s,
              value: value_to_ast(val, sub_type),
            )
          end
          GraphQL::Language::Nodes::InputObject.new(
            arguments: arguments,
          )
        when "LIST"
          if !value.is_a?(Array)
            value = [value]
          end

          value.map { |v| value_to_ast(v, type.of_type) }
        when "ENUM"
          GraphQL::Language::Nodes::Enum.new(name: value)
        else
          value
        end
      end

      private

      def sanitze_input_object(value)
        if value.is_a?(ActionController::Parameters)
          value.to_unsafe_h
        else
          value.to_h
        end
      end

      attr_reader :variable_value, :argument_type
    end
  end
end
