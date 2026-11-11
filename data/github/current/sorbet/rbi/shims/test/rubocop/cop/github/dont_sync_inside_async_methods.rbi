# typed: true

module RuboCop
  module Cop
    module GitHub
      class DontSyncInsideAsyncMethods < Base
        sig { params(node: RuboCop::AST::SendNode, blk: T.proc.params(arg0: RuboCop::AST::SendNode).void).void }
        def sync_call(node, &blk)
        end
      end
    end
  end
end
