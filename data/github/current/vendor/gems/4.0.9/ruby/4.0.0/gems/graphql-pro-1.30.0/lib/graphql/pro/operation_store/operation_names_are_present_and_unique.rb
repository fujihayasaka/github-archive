# frozen_string_literal: true
module GraphQL
  module Pro
    class OperationStore
      module OperationNamesArePresentAndUnique
        if defined?(GraphQL::StaticValidation::Error::ErrorHelper) # < 3.0
          include GraphQL::StaticValidation::Error::ErrorHelper
          ERROR_METHOD = :error
        elsif defined?(GraphQL::StaticValidation::Message::MessageHelper) # < 1.9
          include GraphQL::StaticValidation::Message::MessageHelper
          ERROR_METHOD = :message
        else
          ERROR_METHOD = nil
        end

        def initialize(document, context)
          @op_names = Hash.new { |h, k| h[k] = [] }
          super
        end

        def on_operation_definition(node, _parent)
          @op_names[node.name] << node
          super
        end

        def on_document(node, _parent)
          super
          @op_names.each do |name, nodes|
            nodes_count = nodes.length

            if name == nil
              ops = if nodes_count == 1
                "is 1 unnamed operation"
              else
                "are #{nodes_count} unnamed operations"
              end
              add_operation_store_name_error("Operation names are required, but there #{ops}", node)
            elsif nodes_count > 1
              add_operation_store_name_error(%|Operation names must be unique, but #{nodes_count} operations are named "#{name}"|, nodes)
            end
          end
        end

        def add_operation_store_name_error(message, node_or_nodes)
          case ERROR_METHOD
          when :error, :message
            @context.errors << public_send(ERROR_METHOD, message, node_or_nodes, context: @context)
          when nil
            add_error(
              GraphQL::StaticValidation::Error.new(message, nodes: node_or_nodes)
            )
          else
            raise "Invariant: unexpected ERROR_METHOD: #{ERROR_METHOD.inspect}"
          end
        end
      end
    end
  end
end
