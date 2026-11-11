# typed: true

module RuboCop
  module Cop
    module GitHub
      module FeatureManagement
        class NoVexiActorFeatureFlagEnabledOrRaiseUsage < Base
          def vexi_actor_feature_flag_enabled_or_raise_call?(node); end
          def vexi_actor_safe_nav_feature_flag_enabled_or_raise_call?(node); end
        end
      end
    end
  end
end
