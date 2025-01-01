# typed: true

module RuboCop
  module Cop
    module GitHub
      module FeatureManagement
        class NoFlipperNonStandardUsage < Base
          def flipper_direct_call?(node); end
          def flipper_accessor_call?(node); end
          def github_flipper_direct_call?(node); end
          def github_flipper_accessor_call?(node); end
          def github_flipper_feature_call?(node); end
          def github_flipper_feature_call_no_args?(node); end
          def flipper_block_pass?(*args); end
          def github_flipper_features_receiver?(*args); end
          def flipper_features_receiver?(*args); end
        end
      end
    end
  end
end
