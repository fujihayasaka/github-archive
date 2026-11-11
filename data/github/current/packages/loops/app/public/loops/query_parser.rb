# rubocop:disable GitHub/DoNotCallParseQuery
# typed: strict
# frozen_string_literal: true

# A service class that handles parsing and validation of GraphQL queries
module Loops
  class QueryParser
    include FeatureFlagHelper

    class ParseError < StandardError; end
    class OperationNotAllowedError < StandardError; end

    sig { params(payload: T.nilable(String)).void }
    def initialize(payload)
      @payload = payload
      @fragments = T.let({}, T::Hash[T.untyped, T.untyped])
    end

    sig { params(build_reauth_query: T.nilable(T::Boolean)).returns(T.nilable(String)) }
    def parse(build_reauth_query:)
      return if @payload.nil?

      ast = parse_query(@payload)
      return unless ast

      ensure_no_mutations(ast)

      return unless build_reauth_query

      transformed_ast = transform_to_id_only(ast)
      transformed_ast&.to_query_string
    end

    private

    sig { params(ast: GraphQL::Language::Nodes::Document).void }
    def ensure_no_mutations(ast)
      ast.definitions.each do |definition|
        if definition.is_a?(GraphQL::Language::Nodes::OperationDefinition)
          case definition.operation_type
          when "mutation"
            raise OperationNotAllowedError, "Mutations are not allowed in this context"
          when "subscription"
            raise OperationNotAllowedError, "Subscriptions are not allowed in this context"
          end
        end
      end
    end

    sig { params(query_string: String).returns(T.nilable(GraphQL::Language::Nodes::Document)) }
    def parse_query(query_string)
      GraphQL.parse(query_string)
    rescue GraphQL::ParseError => e
      raise ParseError, "Invalid GraphQL syntax: #{e.message}"
    end

    sig { params(ast: GraphQL::Language::Nodes::Document).returns(T.nilable(GraphQL::Language::Nodes::Document)) }
    def transform_to_id_only(ast)
      # PASS 1: Collect and transform fragment definitions
      collect_fragments(ast)

      # PASS 2: Process operations with fragment resolution
      new_definitions = ast.definitions.filter_map do |definition|
        case definition
        when GraphQL::Language::Nodes::OperationDefinition
          transform_operation(definition)
        when GraphQL::Language::Nodes::FragmentDefinition
          nil # Skip - already processed in pass 1
        end
      end.compact

      GraphQL::Language::Nodes::Document.new(definitions: new_definitions)
    end

    sig { params(ast: GraphQL::Language::Nodes::Document).void }
    def collect_fragments(ast)
      ast.definitions.each do |definition|
        next unless definition.is_a?(GraphQL::Language::Nodes::FragmentDefinition)

        transformed_selections = transform_selections(definition.selections)
        has_scalar_fields = definition.selections.any? do |selection|
          selection.is_a?(GraphQL::Language::Nodes::Field) && (selection.selections.nil? || selection.selections.empty?)
        end

        if has_scalar_fields
          object_fields = transformed_selections.select do |selection|
            selection.is_a?(GraphQL::Language::Nodes::Field) && selection.selections && selection.selections.any?
          end

          entity_fields = create_entity_fields
          @fragments[definition.name] = entity_fields + object_fields
        else
          @fragments[definition.name] = transformed_selections
        end
      end
    end

    sig { params(operation: GraphQL::Language::Nodes::OperationDefinition).returns(GraphQL::Language::Nodes::OperationDefinition) }
    def transform_operation(operation)
      is_mutation_root = operation.operation_type == "mutation"
      if is_mutation_root
        raise OperationNotAllowedError, "Mutations are not allowed in this context"
      end

      new_selections = transform_selections(operation.selections, operation.operation_type)

      GraphQL::Language::Nodes::OperationDefinition.new(
        operation_type: operation.operation_type,
        name: operation.name,
        variables: operation.variables,
        directives: operation.directives,
        selections: new_selections
      )
    end

    sig { params(selections: T::Array[GraphQL::Language::Nodes::AbstractNode], operation_type: T.nilable(String)).returns(T::Array[GraphQL::Language::Nodes::AbstractNode]) }
    def transform_selections(selections, operation_type = nil)
      selections.flat_map do |selection|
        case selection
        when GraphQL::Language::Nodes::Field
          transform_field(selection, operation_type)
        when GraphQL::Language::Nodes::InlineFragment
          transform_inline_fragment(selection)
        when GraphQL::Language::Nodes::FragmentSpread
          transform_fragment_spread(selection)
        end
      end.compact
    end

    sig { params(field: GraphQL::Language::Nodes::Field, operation_type: T.nilable(String)).returns(T::Array[GraphQL::Language::Nodes::AbstractNode]) }
    def transform_field(field, operation_type = nil)
      # If this field has selections (i.e., it's an object field), transform them
      if field.selections&.any?
        # Transform nested selections
        nested_selections = field.selections.flat_map do |selection|
          case selection
          when GraphQL::Language::Nodes::Field
            # Transform all fields, whether they have selections or not
            transform_field(selection, operation_type)
          when GraphQL::Language::Nodes::InlineFragment
            transform_inline_fragment(selection)
          when GraphQL::Language::Nodes::FragmentSpread
            transform_fragment_spread(selection)
          end
        end.compact

        # For structural fields, preserve all their selections as-is (don't add id)
        # For collection fields, don't add id to the collection itself
        # For entity fields, add id and __typename
        all_selections = if should_add_id_field?(field)
          entity_fields = create_entity_fields
          entity_fields + nested_selections
        else
          nested_selections
        end

        # Deduplicate entity fields - only keep one of each at the beginning
        id_fields = all_selections.select { |sel| sel.is_a?(GraphQL::Language::Nodes::Field) && sel.name == "id" }
        typename_fields = all_selections.select { |sel| sel.is_a?(GraphQL::Language::Nodes::Field) && sel.name == "__typename" }
        other_fields = all_selections.reject { |sel| sel.is_a?(GraphQL::Language::Nodes::Field) && (sel.name == "id" || sel.name == "__typename") }

        all_selections = []
        all_selections << id_fields.first if id_fields.any?
        all_selections << typename_fields.first if typename_fields.any?
        all_selections += other_fields

        # If we end up with no selections, only include this field if it's a structural field
        if all_selections.empty?
          return [] unless is_structural_field?(field)
        end

        [GraphQL::Language::Nodes::Field.new(
          name: field.name,
          arguments: field.arguments,
          directives: field.directives,
          selections: all_selections
        )]
      else
        # For scalar fields, the behavior depends on context:
        # - If we're in a structural field context, preserve the scalar field
        # - Otherwise, replace with 'id' field
        if is_structural_field?(field)
          # Preserve structural scalar fields as-is (like hasNextPage in pageInfo)
          [field]
        else
          # Replace entity scalar fields with id and __typename
          create_entity_fields
        end
      end
    end

    sig { params(field: GraphQL::Language::Nodes::Field).returns(T::Boolean) }
    def should_add_id_field?(field)
      # Don't add id to structural fields
      return false if is_structural_field?(field)

      # Don't add id to connection/collection fields
      return false if is_connection_field?(field)

      # Don't add id to fields that contain inline fragments (like nodes with ... on Type)
      return false if has_inline_fragments?(field)

      true
    end

    sig { params(field: GraphQL::Language::Nodes::Field).returns(T::Boolean) }
    def has_inline_fragments?(field)
      return false unless field.selections&.any?

      field.selections.any? { |selection| selection.is_a?(GraphQL::Language::Nodes::InlineFragment) }
    end

    sig { params(field: GraphQL::Language::Nodes::Field).returns(T::Boolean) }
    def is_structural_field?(field)
      # These are structural parts of GraphQL connections/queries, not entities
      # This includes both object fields (edges, node) and scalar fields (hasNextPage, totalCount)
      structural_fields = %w[
        edges pageInfo search node nodes
        hasNextPage hasPreviousPage startCursor endCursor
        totalCount count repositoryCount
      ]
      structural_fields.include?(field.name)
    end

    sig { params(field: GraphQL::Language::Nodes::Field).returns(T::Boolean) }
    def is_connection_field?(field)
      return true if has_pagination_arguments?(field)
      return true if has_relay_connection_structure?(field)
      false
    end

    sig { params(field: GraphQL::Language::Nodes::Field).returns(T::Boolean) }
    def has_pagination_arguments?(field)
      return false unless field.arguments&.any?

      # Relay pagination arguments
      relay_pagination_args = %w[first last before after]

      # Other common pagination patterns
      other_pagination_args = %w[limit offset page pageSize]

      pagination_args = relay_pagination_args + other_pagination_args

      field.arguments.any? { |arg| pagination_args.include?(arg.name) }
    end

    sig { params(field: GraphQL::Language::Nodes::Field).returns(T::Boolean) }
    def has_relay_connection_structure?(field)
      return false unless field.selections&.any?

      field.selections.any? do |selection|
        selection.is_a?(GraphQL::Language::Nodes::Field) && is_structural_field?(selection)
      end
    end

    sig { params(fragment_spread: GraphQL::Language::Nodes::FragmentSpread).returns(T::Array[GraphQL::Language::Nodes::AbstractNode]) }
    def transform_fragment_spread(fragment_spread)
      # Look up the pre-transformed fragment selections
      fragment_selections = @fragments[fragment_spread.name]

      return create_entity_fields if fragment_selections.nil?

      fragment_selections
    end

    sig { returns(T::Array[GraphQL::Language::Nodes::Field]) }
    def create_entity_fields
      [
        GraphQL::Language::Nodes::Field.new(name: "id"),
        GraphQL::Language::Nodes::Field.new(name: "__typename")
      ]
    end

    sig { params(fragment: GraphQL::Language::Nodes::InlineFragment).returns(T::Array[GraphQL::Language::Nodes::AbstractNode]) }
    def transform_inline_fragment(fragment)
      # Recursively transform the fragment's selections
      nested_selections = transform_selections(fragment.selections)

      # Add id and __typename fields for the entity represented by this inline fragment
      entity_fields = create_entity_fields
      all_selections = entity_fields + nested_selections

      # Deduplicate entity fields - only keep one of each at the beginning
      id_fields = all_selections.select { |sel| sel.is_a?(GraphQL::Language::Nodes::Field) && sel.name == "id" }
      typename_fields = all_selections.select { |sel| sel.is_a?(GraphQL::Language::Nodes::Field) && sel.name == "__typename" }
      other_fields = all_selections.reject { |sel| sel.is_a?(GraphQL::Language::Nodes::Field) && (sel.name == "id" || sel.name == "__typename") }

      all_selections = []
      all_selections << id_fields.first if id_fields.any?
      all_selections << typename_fields.first if typename_fields.any?
      all_selections += other_fields

      [GraphQL::Language::Nodes::InlineFragment.new(
        type: fragment.type,
        directives: fragment.directives,
        selections: all_selections
      )]
    end
  end
end
