# typed: true

module RuboCop
  module Cop
    module GitHub
      module FeatureManagement
        class NoVexiNonStandardUsage < Base
          def vexi_non_standard_call?(node); end
        end
      end
    end
  end
end
