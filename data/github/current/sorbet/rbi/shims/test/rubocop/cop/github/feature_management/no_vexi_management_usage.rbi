# typed: true

module RuboCop
  module Cop
    module GitHub
      module FeatureManagement
        class NoVexiManagementUsage < Base
          def vexi_management_call?(node); end
        end
      end
    end
  end
end
