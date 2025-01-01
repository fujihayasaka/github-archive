# typed: true
# frozen_string_literal: true

module Platform
  module Edges
    class Base < Platform::Objects::Base
      description "An edge in a connection."

      # Since Edges are wrappers around some other object,
      # authorize them based on that other object.
      #
      # Authorize the wrapped object as if it was wrapped by
      # the node type (which it will be, after/if it passes this check).
      def self.authorized?(object, ctx)
        if node_type < Objects::Base
          node_object_type = node_type
        else
          # Disambiguate connections whose `.node_type` is a Union or Interface
          node_object_type = ctx.schema.resolve_type(self.node_type, object.node, ctx)
          # returns potentially [type, value]
          if node_object_type.is_a?(Array) && node_object_type.size == 2
            node_object_type = node_object_type[0]
          end
        end
        # Call the hook for that concrete class
        node_object_type.authorized?(object.node, ctx)
      end

      def self.inherited(child_class)
        super
        # If the class isn't an anonymous class, let's try to guess which
        # GraphQL type it comes from.
        if child_class.name
          # The class is named just like the object type that the edge wraps,
          # but that will be a naming conflict, so append `Edge` to the class name
          # for graphql purposes.
          wrapped_type_name = child_class.name.split("::").last
          child_class.graphql_name("#{wrapped_type_name}Edge")
          wrapped_type_class_name = "Platform::Objects::#{wrapped_type_name}"
          begin
            # call `const_get` to raise an error if the class doesn't exist
            child_class.field(
              :node,
              const_get(wrapped_type_class_name),
              null: true,
              description: "The item at the end of the edge.",
              scope: true
            )
          rescue NameError
            # Apparently the constant doesn't exist, assume that this is overridden in the edge class
          end
        end

        child_class.scopeless_tokens_as_minimum
      end

      # Override this method because sometimes edges are created with only their node type _name_,
      # so we have to lazily reference the type _class_ and get the `map_to_service` at the first time it's used
      def self.service_mapping(serviceowners: nil)
        T.bind(self, T.untyped)
        super || if !defined?(@default_service_mapping)
                   # This edge probably got its `node_type_name` from a string, now use it to find a map_to_service
                   @default_service_mapping = node_type&.service_mapping(serviceowners: serviceowners)
                 end
      end

      # Like `node_type_name`, but using a reference to the Class itself
      # (works with anonymous classes)
      def self.node_type(wrapped_type_class = nil)
        if wrapped_type_class
          if self.name.nil?
            graphql_name("#{wrapped_type_class.graphql_name}Edge")
          end
          field :node, wrapped_type_class, null: true, description: "The item at the end of the edge.", scope: true
          @node_type = wrapped_type_class
        else
          @node_type ||= begin
            node_field = self.fields["node"]
            if node_field.nil?
              nil # This is true for `Platform::Edges::Base`
            else
              node_field.type.unwrap
            end
          end
        end
      end

      field :cursor, String,
        null: false,
        description: "A cursor for use in pagination."

      def self.scope_items(items, context)
        return items.clone if !reauthorize_scoped_objects && (context[:viewer]&.feature_enabled?(:graphql_skip_reauthorize_scoped_items) || GitHub.flipper[:graphql_skip_reauthorize_scoped_items].enabled?)
        items
      end

      # as we delegate auth to the node, we should delegate scoped reauth config as well
      def self.reauthorize_scoped_objects
        if (node_type < Objects::Base || node_type < Unions::Base) && node_type.respond_to?(:reauthorize_scoped_objects)
          return node_type.reauthorize_scoped_objects
        end
        # default is to reauth scoped objects
        true
      end
    end
  end
end
