# frozen_string_literal: true

require 'apollo-federation/entities_field'
require 'apollo-federation/service_field'
require 'apollo-federation/entity'
require 'apollo-federation/federated_document_from_schema_definition.rb'

module ApolloFederation
  module Schema
    IMPORTED_DIRECTIVES = ['inaccessible', 'tag'].freeze

    def self.included(klass)
      klass.extend(CommonMethods)
    end

    module CommonMethods
      DEFAULT_LINK_NAMESPACE = 'federation'

      def federation(version: '1.0', link: {}, import: nil, exclude_service_query: false)
        @federation_version = version
        @link = { as: DEFAULT_LINK_NAMESPACE }.merge(link)
        @imported_directives = import
        @exclude_service_query = exclude_service_query
      end

      def federation_version
        @federation_version || find_inherited_value(:federation_version, '1.0')
      end

      def federation_2?
        Gem::Version.new(federation_version.to_s) >= Gem::Version.new('2.0.0')
      end

      def federation_sdl(context: nil)
        document_from_schema = FederatedDocumentFromSchemaDefinition.new(self, context: context)

        output = GraphQL::Language::Printer.new.print(document_from_schema.document)
        output.prepend(federation_2_prefix) if federation_2?
        output
      end

      def link_namespace
        @link ? @link[:as] : find_inherited_value(:link_namespace)
      end

      def imported_directives
        @imported_directives || find_inherited_value(:imported_directives) || IMPORTED_DIRECTIVES
      end

      def exclude_service_query?
        defined?(@exclude_service_query) ? @exclude_service_query : find_inherited_value(:exclude_service_query?, false)
      end

      def query(new_query_object = nil)
        return super if new_query_object.nil? && @query_object

        @orig_query_object = new_query_object
        federation_query_object = federation_query(original_query)
        federation_query_object.define_entities_field(schema_entities)

        super(federation_query_object)

        federation_query_object
      end

      private

      def original_query
        @orig_query_object || find_inherited_value(:original_query)
      end

      def federation_2_prefix
        federation_namespace = ", as: \"#{link_namespace}\"" if link_namespace != DEFAULT_LINK_NAMESPACE

        <<~SCHEMA
          extend schema
            @link(url: "https://specs.apollo.dev/federation/v2.3"#{federation_namespace}, import: [#{(imported_directives.map { |directive| "\"@#{directive}\"" }).join(', ')}])

        SCHEMA
      end

      def schema_entities
        # Create a temporary schema that inherits from this one to extract the types
        types_schema = Class.new(self)
        # Add the original query objects to the types. We have to use orphan_types here to avoid
        # infinite recursion
        types_schema.orphan_types(original_query)

        # Walk through all of the types and determine which ones are entities (any type with a
        # "key" directive)
        types_schema.send(:non_introspection_types).values.flatten.select do |type|
          # TODO: Interfaces can have a key...
          type.include?(ApolloFederation::Object) &&
            type.federation_directives&.any? { |directive| directive[:name] == 'key' }
        end
      end

      def federation_query(query_obj)
        if query_obj.nil?
          # If no query class is provided, create a new one
          base = GraphQL::Schema::Object
          query_class = Class.new(base) do
            graphql_name 'Query'
          end
        elsif Gem::Version.new(GraphQL::VERSION) >= Gem::Version.new('1.10.0')
          # For newer GraphQL versions, use the query object directly
          query_class = query_obj
        else
          # For older GraphQL versions, extract the type class from metadata
          query_class = query_obj.metadata[:type_class]
        end
        query_class.include(EntitiesField)
        unless exclude_service_query?
          query_class.include(ServiceField)
          query_class.define_service_field
        end
        query_class
      end
    end
  end
end
