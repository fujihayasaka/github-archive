# typed: true

module RuboCop
  module Cop
    module GitHub
      module FeatureManagement
        class NoFlipperGateUsage < Base
          def flipper_gate_call?(node); end
        end
      end
    end
  end
end
