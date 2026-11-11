# typed: true

module RuboCop
  module Cop
    module GitHub
      class GraphqlOnlyOneNodeImplementation < Base
        sig { params(node: RuboCop::AST::Node).returns(T::Boolean) }
        def global_id_field_call?(node); end

        sig { params(node: RuboCop::AST::Node).returns(T::Boolean) }
        def implements_node_interface?(node); end

        sig { params(node: RuboCop::AST::Node).returns(T::Boolean) }
        def implements_node_call?(node); end
      end
    end
  end
end
