# typed: true

module RuboCop
  module Cop
    module GitHub
      class StrictFixtures < Base
        sig { params(node: RuboCop::AST::Node).returns(T::Boolean) }
        def strict_fixtures_false?(node)
        end

        sig { params(node: RuboCop::AST::Node).returns(T::Boolean) }
        def fixture_block?(node)
        end
      end
    end
  end
end
