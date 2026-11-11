# typed: true

module RuboCop
  module Cop
    module GitHub
      class AvoidMultisiteIncompatibleCacheUsage < Base
        def cache_mutation?(node)
        end

        def cache_send?(node)
        end

        def cache_lock_const?(node)
        end
      end
    end
  end
end
