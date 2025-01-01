# typed: true

module RuboCop
  module Cop
    module GitHub
      module FeatureManagement
        class NoFlipperEnabledUsageMigration < Base
          def flipper_direct_call?(node); end
          def flipper_accessor_call?(node); end
          def github_flipper_direct_call?(node); end
          def github_flipper_accessor_call?(node); end
        end
      end
    end
  end
end
