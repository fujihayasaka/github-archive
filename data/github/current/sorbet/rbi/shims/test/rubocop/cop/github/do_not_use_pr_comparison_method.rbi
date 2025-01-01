# typed: true

module RuboCop
  module Cop
    module GitHub
      class DoNotUsePrComparisonMethod < Base
        def pull_comparison_call?(node)
        end
      end
    end
  end
end
