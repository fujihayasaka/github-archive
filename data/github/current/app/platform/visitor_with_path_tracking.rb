# typed: true
# frozen_string_literal: true
module Platform
  class VisitorWithPathTracking < GraphQL::Language::Visitor
    NODE_TYPES = [
      GraphQL::Language::Nodes::ObjectTypeDefinition,
      GraphQL::Language::Nodes::InterfaceTypeDefinition,
      GraphQL::Language::Nodes::FieldDefinition,
      GraphQL::Language::Nodes::InputValueDefinition,
      GraphQL::Language::Nodes::UnionTypeDefinition,
      GraphQL::Language::Nodes::ScalarTypeDefinition,
      GraphQL::Language::Nodes::EnumTypeDefinition,
      GraphQL::Language::Nodes::EnumValueDefinition,
      GraphQL::Language::Nodes::InputObjectTypeDefinition,
    ]
    DIRECTIVE_TYPES = [
      GraphQL::Language::Nodes::DirectiveDefinition,
      GraphQL::Language::Nodes::Directive
    ]

    def initialize(document)
      super(document)

      @current_path = []
      @visitors_callbacks = Hash.new

      @push_node = -> (node, _parent) { @current_path << node.name }
      @push_node_directive = -> (node, _parent) { @current_path << "@#{node.name}" }
      @pop_node = -> (_node, _parent) { @current_path.pop }


      NODE_TYPES.each do |node_type|
        @visitors_callbacks[node_type] = {
          enter: [@push_node],
          leave: [@pop_node]
        }
      end

      DIRECTIVE_TYPES.each do |directive_type|
        @visitors_callbacks[directive_type] = {
          enter: [@push_node_directive],
          leave: [@pop_node]
        }
      end
    end

    def set_visit_callbacks(node_class, callback:)
      if @visitors_callbacks[node_class].nil?
        @visitors_callbacks[node_class] = { enter: [callback], leave: [@pop_node] }
      else
        @visitors_callbacks[node_class][:enter] << callback
      end
    end

    # create callabcks for all visitors_callbacks
    NODE_TYPES.concat(DIRECTIVE_TYPES).each do |node_type|
      method_name = node_type.to_s.demodulize.underscore
      module_eval <<-RUBY, __FILE__, __LINE__
        def on_#{method_name}(node, parent)
          enter_node(node, parent)
          data = super(node, parent)
          leave_node(node, parent)
          data
        end
      RUBY
    end

    def enter_node(node, parent)
      if @visitors_callbacks[node.class].present?
        @visitors_callbacks[node.class][:enter].each { |callback| callback.call(node, parent) }
      end
    end

    def leave_node(node, parent)
      if @visitors_callbacks[node.class].present?
        @visitors_callbacks[node.class][:leave].each { |callback| callback.call(node, parent) }
      end
    end

    def current_path
      @current_path.join(".")
    end
  end
end
