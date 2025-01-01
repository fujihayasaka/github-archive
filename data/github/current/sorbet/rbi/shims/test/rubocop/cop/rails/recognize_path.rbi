# typed: true

module RuboCop
  module Cop
    module Rails
      class RecognizePath < Base
        sig { params(node: RuboCop::AST::Node).returns(T::Boolean) }
        def recognize_path_call?(node)
        end
      end
    end
  end
end
