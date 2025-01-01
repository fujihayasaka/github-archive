# typed: true

module RuboCop
  module Cop
    module GitHub
      class GraphqlOnlyNewNodeImplementationForNewObject < Base
        sig { params(node: RuboCop::AST::SendNode).returns(T::Boolean) }
        def global_id_field_call?(node); end

        sig { params(node: RuboCop::AST::SendNode).returns(T::Boolean) }
        def implements_node_interface?(node); end
      end
    end
  end
end
