# typed: true

module RuboCop
  module Cop
    module GitHub
      class UseScopelessPromises < Base
        sig { params(node: RuboCop::AST::SendNode).returns(T::Boolean) }
        def graphql_batch_promise?(node); end
      end
    end
  end
end
