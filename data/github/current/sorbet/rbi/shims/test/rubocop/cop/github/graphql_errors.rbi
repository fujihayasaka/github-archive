# typed: true

module RuboCop
  module Cop
    module GitHub
      class GraphqlErrors < Base
        sig { params(node: RuboCop::AST::SendNode).returns(T::Boolean) }
        def context_ivar_add_errors?(node); end

        sig { params(node: RuboCop::AST::SendNode).returns(T::Boolean) }
        def context_attr_add_errors?(node); end
      end
    end
  end
end
