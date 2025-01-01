# typed: true
# frozen_string_literal: true

module Platform
  module SchemaPrinter
    module UnderDevelopment
      class Directive < GraphQL::Schema::Directive
        graphql_name "underDevelopment"

        description "Marks an element of a GraphQL schema as currently under development."

        argument :since, String, required: true, description: "When has this element been marked as under development."

        locations(
          GraphQL::Schema::Directive::SCALAR,
          GraphQL::Schema::Directive::OBJECT,
          GraphQL::Schema::Directive::FIELD_DEFINITION,
          GraphQL::Schema::Directive::ARGUMENT_DEFINITION,
          GraphQL::Schema::Directive::INTERFACE,
          GraphQL::Schema::Directive::UNION,
          GraphQL::Schema::Directive::ENUM,
          GraphQL::Schema::Directive::ENUM_VALUE,
          GraphQL::Schema::Directive::INPUT_OBJECT,
          GraphQL::Schema::Directive::INPUT_FIELD_DEFINITION,
        )
      end

      def self.inject_since_arguments_in_schema_sdl(new_schema_sdl, previous_schema_sdl:)
        previous_schema_document = GraphQL.parse(previous_schema_sdl)
        previous_since_argument_values = self.extract_since_argument_values(previous_schema_document)

        new_schema_document = GraphQL.parse(new_schema_sdl)
        new_schema_document = self.inject_missing_since_argument_values_in_schema(new_schema_document, previous_since_argument_values, Date.today.to_s)

        new_schema_document.to_query_string
      end

      def self.extract_since_argument_values(schema_document)
        dates = {}

        visitor = Platform::VisitorWithPathTracking.new(schema_document)

        visitor.set_visit_callbacks(
          GraphQL::Language::Nodes::Directive,
          callback: -> (node, _parent) {
            if node.name == Directive.graphql_name && since_arg = node.arguments.find { |argument| argument.name == "since" }
              dates[visitor.current_path] = since_arg.value
            end
          }
        )

        visitor.visit

        dates
      end

      class InjectMissingSinceArgumentValuesVisitor < Platform::VisitorWithPathTracking
        def initialize(document, since_values:, new_since_value:)
          @existing_since_values = since_values
          @new_since_value = new_since_value
          super(document)
        end

        def on_directive_with_modifications(node, parent)
          T.bind(self, T.untyped)
          if node.name != "underDevelopment"
            super
          elsif node.arguments.any? { |argument| argument.name == "since" }
            super
          else
            directive_path = self.current_path + ".@underDevelopment"
            since_value = @existing_since_values[directive_path] || @new_since_value
            since_arg = GraphQL::Language::Nodes::Argument.new(name: "since", value: since_value)
            new_node = node.merge(arguments: node.arguments + [since_arg])
            apply_modifications(node, parent, [new_node, parent])
          end
        end
      end

      def self.inject_missing_since_argument_values_in_schema(schema_document, existing_since_argument_values, new_since_argument_value)
        visitor = InjectMissingSinceArgumentValuesVisitor.new(schema_document,
          since_values: existing_since_argument_values,
          new_since_value: new_since_argument_value,
        )
        visitor.visit
        visitor.result
      end
    end
  end
end
