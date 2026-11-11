# typed: true
# frozen_string_literal: true

module Platform
  module Instrumentation
    # Platform::Instrumentation::QueryPrinter is a custom GraphQL Ruby
    # printer used to print sanitized queries. It inlines provided variables
    # within the query for facilitate logging and analysis of queries.
    # The printer assumes the query is valid.
    #
    # Since the GraphQL Ruby AST for a GraphQL query doesnt contain any reference
    # on the type of fields or arguments, we have to track the current object, field
    # and input type while printing the query.
    class QueryPrinter < GraphQL::Language::Printer
      class InvalidQueryError < ArgumentError; end

      REDACTED = "<REDACTED>"

      def initialize(query)
        @query = query
        @current_type = nil
        @current_field = nil
        @current_input_type = nil
      end

      def scrubbed
        unless query.valid?
          errors = query.static_errors.map { |e| e.message }.join(", ")
          raise InvalidQueryError, "Printing requires a valid GraphQL query, but the query had errors: #{errors}" # rubocop:disable GitHub/UsePlatformErrors
        end

        print(query.document)
      end

      def print_node(node, indent: "")
        if node.is_a?(String) && !allowed_type_kind?(@current_input_type.unwrap)
          T.bind(self, T.untyped)
          print_string(GraphQL::Language.serialize(REDACTED))
        elsif @current_input_type&.kind&.list?
          if node.is_a?(GraphQL::Language::Nodes::VariableIdentifier)
            super
          else
            @current_input_type = @current_input_type.of_type
            if !node.is_a?(Array)
              node = [node]
            end
            T.bind(self, T.untyped)
            print_string("[")
            node.each_with_index do |n, i|
              print_node(n, indent: indent)
              print_string(", ") if i < node.size - 1
            end
            print_string("]")
          end
        elsif @current_input_type&.non_null?
          @current_input_type = @current_input_type.of_type
          print_node(node, indent: indent)
        else
          super
        end
      end

      def print_argument(argument)
        arg_def = if @current_input_type
          @current_input_type.arguments[argument.name]
        elsif @current_directive
          @current_directive.arguments[argument.name]
        else
          @current_field.arguments[argument.name]
        end

        old_input_type = @current_input_type
        @current_input_type = arg_def.type.non_null? ? arg_def.type.of_type : arg_def.type
        res = super
        @current_input_type = old_input_type
        res
      end

      def print_list_type(list_type)
        old_input_type = @current_input_type
        @current_input_type = old_input_type.of_type
        res = super
        @current_input_type = old_input_type
        res
      end

      def print_variable_identifier(variable_id)
        variable_value = query.provided_variables.with_indifferent_access[variable_id.name]
        print_node(VariableInliner.new(variable_value, @current_input_type).to_ast)
      end

      def print_field(field, indent: "")
        @current_field = query.schema.get_field(@current_type, field.name)
        old_type = @current_type
        @current_type = @current_field.type.unwrap
        res = super
        @current_type = old_type
        res
      end

      def print_inline_fragment(inline_fragment, indent: "")
        old_type = @current_type

        if inline_fragment.type
          @current_type = query.schema.get_type(inline_fragment.type.name)
        end

        res = super

        @current_type = old_type

        res
      end

      def print_fragment_definition(fragment_def, indent: "")
        old_type = @current_type
        @current_type = query.schema.get_type(fragment_def.type.name)

        res = super

        @current_type = old_type

        res
      end

      def print_directive(directive)
        @current_directive = query.schema.directives[directive.name]

        res = super

        @current_directive = nil
        res
      end

      # Print the operation definition but do not include the variable
      # definitions since we will inline them within the query
      def print_operation_definition(operation_definition, indent: "")
        old_type = @current_type
        @current_type = query.schema.public_send(operation_definition.operation_type)

        T.bind(self, T.untyped)
        print_string("#{indent}#{operation_definition.operation_type}")
        if operation_definition.name
          print_string(" #{operation_definition.name}")
        end

        print_directives(operation_definition.directives)
        print_selections(operation_definition.selections, indent: indent)
        @current_type = old_type
      end

      private

      def allowed_type_kind?(type)
        type.kind.enum? || type.graphql_name == "ID"
      end

      attr_reader :query
    end
  end
end
