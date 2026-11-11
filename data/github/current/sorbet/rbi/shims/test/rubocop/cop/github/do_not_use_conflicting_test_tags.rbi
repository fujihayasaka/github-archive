# typed: true

module RuboCop
  module Cop
    module GitHub
      class DoNotUseConflictingTestTags < Base
        sig { params(node: RuboCop::AST::Node).returns(T::Boolean) }
        def test_or_context_block?(node)
        end

        sig { params(node: RuboCop::AST::Node).returns(T.nilable(Symbol)) }
        def environment_module_call?(node)
        end

        sig { params(node: RuboCop::AST::Node).returns(T.nilable(Symbol)) }
        def test_tag_method_call?(node)
        end
      end
    end
  end
end
