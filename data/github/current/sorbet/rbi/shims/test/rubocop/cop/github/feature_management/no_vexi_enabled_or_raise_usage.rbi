# typed: true

module RuboCop
  module Cop
    module GitHub
      module FeatureManagement
        class NoVexiEnabledOrRaiseUsage < Base
          def vexi_enabled_or_raise_call?(node); end
        end
      end
    end
  end
end
