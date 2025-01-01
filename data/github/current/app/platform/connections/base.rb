# typed: false
# frozen_string_literal: true

module Platform
  module Connections
    class Base < Platform::Objects::Base
      extend Forwardable
      def_delegators :@object, :cursor_from_node, :parent

      include GitHub::Relay::GlobalIdentification

      def self.async_viewer_can_see?(*)
        true # filter edges/nodes instead
      end

      def self.async_api_can_access?(*)
        true # filter edges/nodes instead
      end

      # As long as neither `async_viewer_can_see?` nor `async_api_can_access?` are overridden,
      # skip full authorization and filter edges/nodes instead.
      def self.authorized?(_, context)
        base_owner = Platform::Connections::Base.singleton_class
        skip_full_authorize = context[:viewer]&.feature_enabled?(:graphql_skip_reauthorize_scoped_items) &&
          method(:async_viewer_can_see?).owner == base_owner &&
          method(:async_api_can_access?).owner == base_owner

        if skip_full_authorize
          true # filter edges/nodes instead
        else
          super
        end
      end

      class << self
        attr_reader :edge_class
      end

      # Configure this connection to return `edges` and `nodes` based on `edge_type_class`.
      #
      # This method will use the inputs to create:
      # - `edges` field
      # - `nodes` field
      # - description
      #
      # It's called when you subclass this base connection, trying to use the
      # class name to set defaults. You can call it again in the class definition
      # to override the default (or provide a value, if the default lookup failed).
      def self.edge_type(edge_type_class, edge_class: GraphQL::Pagination::Connection::Edge, node_type: nil)
        @edge_class = edge_class

        field :edges, [edge_type_class, null: true],
          null: true,
          description: "A list of edges.",
          edge_class: edge_class,
          scope: true

        if node_type.nil?
          if edge_type_class.is_a?(Class)
            node_type = edge_type_class.node_type
          else
            raise ArgumentError, "Can't get node type from edge type: #{edge_type_class}" # rubocop:disable GitHub/UsePlatformErrors
          end
        end

        if node_type.respond_to?(:of_type)
          node_type = node_type.of_type
        end

        @node_type = node_type
        field :nodes, [node_type, null: true],
          null: true,
          description: "A list of nodes.",
          scope: true

        description("The connection type for #{node_type.graphql_name}.")

        if node_type.respond_to?(:feature_flag) && node_type.feature_flag
          self.feature_flag(node_type.feature_flag)
          edge_type_class.feature_flag(node_type.feature_flag)
        end

        if node_type.respond_to?(:mobile_only) && node_type.mobile_only
          self.mobile_only(node_type.mobile_only)
          edge_type_class.mobile_only(node_type.mobile_only)
        end

        if node_type.respond_to?(:required_capabilities) && node_type.required_capabilities.kind_of?(Array)
          self.required_capabilities(node_type.required_capabilities)
          edge_type_class.required_capabilities(node_type.required_capabilities)
        end

        if node_type.respond_to?(:visibility) &&
            node_type.visibility.present? &&
            edge_type_class.default_visibility?

          node_type.environment_visibilities.each do |env, visibilities|
            self.visibility(visibilities, environments: [env])
            edge_type_class.visibility(visibilities, environments: [env])
          end
        end

        # Abhor anonymous classes that have to actually be handled in app code.
        # A class without a name might as well be invisible to sorbet.
        if edge_type_class.is_a?(Class) && !edge_type_class.name
          ::Platform::Edges::Generated.const_set(node_type.graphql_name, edge_type_class)
        end
      end

      def self.node_type
        if defined?(@node_type)
          @node_type
        else
          nodes_field = self.get_field("nodes")
          @node_type = nodes_field&.type&.unwrap
        end
      end

      def self.scope_items(items, context)
        # this needs to be cloned because of the equal check in the gem
        # graphql/schema/field/scope_extension.rb:16
        return items.clone if !reauthorize_scoped_objects && context[:viewer]&.feature_enabled?(:graphql_skip_reauthorize_scoped_items)
        items
      end

      # as we delegate auth to the node, we should delegate scoped reauth config as well
      def self.reauthorize_scoped_objects
        if node_type < Objects::Base && node_type.respond_to?(:reauthorize_scoped_objects)
          return node_type.reauthorize_scoped_objects
        end
        # default is to reauth scoped objects
        true
      end

      # Defer this call to avoid calling into Serviceowners during boot
      def self.service_mapping(serviceowners: nil)
        super || if !defined?(@default_service_mapping)
                   @default_service_mapping = node_type&.service_mapping(serviceowners: serviceowners)
                 end
      end

      def self.inherited(child_class)
        super
        # The parent `node` and child `nodes` will be scoped
        child_class.scopeless_tokens_as_minimum
        # The class is named just like the object type that the connection wraps,
        # but that will be a naming conflict, so append `Connection` to the class name
        # for graphql purposes.
        node_class_name = child_class.name
        if node_class_name.nil?
          # Anonymous classes don't have a name, assume `edge_type`
          # will be called later.
          return
        end

        type_name = node_class_name.split("::").last
        child_class.graphql_name("#{type_name}Connection")

        if Platform::Edges.const_defined?(type_name, false)
          # Look for a custom edge whose name matches this connection's name
          wrapped_edge_class = Platform::Edges.const_get(type_name, false)
          wrapped_node_class = wrapped_edge_class.fields["node"].type
        elsif Platform::Objects.const_defined?(type_name, false)
          # If there isn't one, look for an object whose name matches this name.
          wrapped_node_class = Platform::Objects.const_get(type_name, false)
          wrapped_edge_class = wrapped_node_class.edge_type
        end

        # If a default could be found using constant lookups, generate the fields for it.
        if wrapped_edge_class
          if wrapped_edge_class.is_a?(Class) && wrapped_edge_class < Platform::Edges::Base
            # If the edge class is an object type, use it directly
            edge_class = if Platform::Models.const_defined?("#{type_name}Edge", false)
              Platform::Models.const_get("#{type_name}Edge", false)
            else
              GraphQL::Pagination::Connection::Edge
            end
            child_class.edge_type(wrapped_edge_class, edge_class: edge_class, node_type: wrapped_node_class)
          else
            raise TypeError, "Missed edge type lookup, didn't find a type definition: #{type_name.inspect} => #{wrapped_edge_class.inspect}"  # rubocop:disable GitHub/UsePlatformErrors
          end
        end
      end

      field :page_info, GraphQL::Types::Relay::PageInfo, null: false, description: "Information to aid in pagination."

      # By default this calls through to the ConnectionWrapper's edge nodes method,
      # but sometimes you need to override it to support the `nodes` field
      def nodes
        @object.edge_nodes
      end

      def edges
        context.schema.after_lazy(object.edge_nodes) do |nodes|
          # Support local connection overrides which may have their own edge class.
          # (The goal is to migrate all connections here soon, see https://github.com/rmosolgo/graphql-ruby/pull/2143)
          edge_class = object.respond_to?(:edge_class) ? object.edge_class : self.class.edge_class
          nodes.map { |n| edge_class.new(n, object) }
        end
      end

      # Use this method to add the default total_count field to your connection.
      # For historical reasons, some connections don't have this field, so we
      # can't add it to the base class ... yet ... ?
      def self.total_count_field(description: nil)
        field :total_count, Integer, null: false,
          description: description || "Identifies the total count of items in the connection."
      end

      # A default implementation that tries to infer an efficient total
      # from the current object. Don't hesitate to override it if you can
      # provide a better implementation in your own connection.
      def total_count
        object.total_count
      end
    end
  end
end
