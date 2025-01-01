# typed: true

module RuboCop
  module Cop
    module GitHub
      class UsePlatformErrors < Base
        sig { params(node: RuboCop::AST::SendNode).returns(T::Boolean) }
        def platform_namespace_error?(node); end

        sig { params(node: RuboCop::AST::SendNode).returns(T::Boolean) }
        def platform_error?(node); end
      end
    end
  end
end
