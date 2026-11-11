# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module Node
      include Platform::Interfaces::Base
      description "An object with an ID."
      field(:id, ID, null: false, description: "ID of the object.")

      # When an Object type implements Node, automatically add federation
      # @key(fields: "id") and @shareable directives so the type is
      # resolvable as an entity in Apollo Federation, and provide a default
      # resolve_reference that loads the object from its node ID.
      def self.included(child_class)
        super
        return unless child_class.is_a?(Class) && child_class < GraphQL::Schema::Object

        # ApolloFederation methods are dynamically mixed in via ApolloFederation::Object,
        # which Sorbet can't see on the base GraphQL::Schema::Object type.
        federation_aware = T.unsafe(child_class)
        unless federation_aware.own_federation_directives.any? { |d| d[:name] == "key" && d[:arguments]&.any? { |a| a[:name] == "fields" && a[:values] == "id" } }
          federation_aware.key fields: :id
        end
        unless federation_aware.own_federation_directives.any? { |d| d[:name] == "shareable" }
          federation_aware.shareable
        end

        # Add a default resolve_reference that resolves via the node ID, unless
        # the type already defines its own. Types with a custom resolve_reference
        # should call Node.resolve_reference_by_node_id as a fallback when their
        # primary key field is not present in the representation.
        unless child_class.singleton_class.method_defined?(:resolve_reference, false)
          child_class.define_singleton_method(:resolve_reference) do |reference, context|
            Node.resolve_reference_by_node_id(child_class, reference, context)
          end
        end
      end

      # Resolve a federation entity reference using the node ID field.
      # Parses the global relay ID and loads the object via the type's
      # existing load_from_global_id / load_from_next_global_id methods
      # (the same path used by the node(id:) query).
      #
      # Types with a custom resolve_reference should call this method as a
      # fallback when their primary key field is not in the representation:
      #
      #   def self.resolve_reference(reference, context)
      #     if reference[:full_database_id]
      #       # existing custom resolution ...
      #     else
      #       Node.resolve_reference_by_node_id(self, reference, context)
      #     end
      #   end
      #
      def self.resolve_reference_by_node_id(type_class, reference, _context)
        node_id = reference.is_a?(Hash) && reference[:id]
        return Promise.resolve(nil) unless node_id

        parsed = Platform::Helpers::GlobalId.parse(node_id)
        if parsed.is_a?(Platform::Helpers::GlobalId::Next)
          type_class.load_from_next_global_id(parsed)
        else
          type_class.load_from_global_id(parsed.id)
        end
      rescue
        Promise.resolve(nil)
      end
    end
  end
end
