# typed: true

module RuboCop
  module Cop
    module GitHub
      module FeatureManagement
        class NoFlipperEnabledUsage < Base
          def flipper_direct_call?(node); end
          def flipper_accessor_call?(node); end
          def github_flipper_direct_call?(node); end
          def github_flipper_accessor_call?(node); end
          def github_flipper_feature_call?(node); end
        end
      end
    end
  end
end
