# typed: true

module RuboCop
  module Cop
    module GitHub
      class GraphqlFieldsUseMethod < Base
        sig { params(node: RuboCop::AST::DefNode).returns(T::Boolean) }
        def method_call_on_object?(node); end
      end
    end
  end
end
