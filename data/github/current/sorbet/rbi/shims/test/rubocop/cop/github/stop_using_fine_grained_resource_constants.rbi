# typed: true

module RuboCop
  module Cop
    module GitHub
      class StopUsingFineGrainedResourceConstants < Base
        sig { params(node: RuboCop::AST::Node).returns(T::Boolean) }
        def using_subject_types_constant?(node)
        end
      end
    end
  end
end
