# typed: true

module RuboCop
  module Cop
    module GitHub
      module FeatureManagement
        class NoFlipperFeatureFlagManipulationMigration < Base
          sig { params(node: RuboCop::AST::Node).returns(T::Boolean) }
          def direct_flipper_call?(node); end

          sig { params(node: RuboCop::AST::Node).returns(T::Boolean) }
          def flipper_accessor_call?(node); end
        end
      end
    end
  end
end
