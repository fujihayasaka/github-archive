# typed: true

module RuboCop
  module Cop
    module GitHub
      module FeatureManagement
        class NoFeatureFlagManipulation < Base
          def direct_flipper_call?(node); end
          def flipper_accessor_call?(node); end
          def feature_flipper_call?(node); end
        end
      end
    end
  end
end
