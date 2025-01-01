# typed: true

module RuboCop
  module Cop
    module GitHub
      module FeatureManagement
        class NoFlipperFeatureUsage < Base
          def flipper_feature_call?(node); end
        end
      end
    end
  end
end
