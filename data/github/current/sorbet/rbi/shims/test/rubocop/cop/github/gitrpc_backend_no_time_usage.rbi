# typed: true

module RuboCop
  module Cop
    module GitHub
      class GitRPCBackendNoTimeUsage
        def time_now?(node)
        end

        def time_current?(node)
        end
      end
    end
  end
end
