# typed: true

module RuboCop
  module Cop
    module GitHub
      class TwirpEndpointsShouldHaveTests < Base
        sig { params(node: RuboCop::AST::Node).returns(T::Boolean) }
        def twirp_handler_class?(node); end

        sig { params(node: RuboCop::AST::Node).returns(T::Boolean) }
        def twirp_handler_direct_descendence?(node); end
      end
    end
  end
end
