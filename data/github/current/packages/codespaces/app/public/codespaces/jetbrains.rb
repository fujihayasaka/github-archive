# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Codespaces
  class Jetbrains
    # Codespaces feature flags that are proxied to VSCS
    FEATURE_FLAGS = %w[
      codespaces_jetbrains_basis
      codespaces_jetbrains_skuHeapScaling
      codespaces_jetbrains_cache_ide
      codespaces_jetbrains_developer
      codespaces_jetbrains_eap
    ]

    def self.feature_flags(user)
      flags = FEATURE_FLAGS.collect do |flag|
        [flag.remove("codespaces_jetbrains").camelize(:lower), FeatureFlag.vexi.enabled_or_raise?(flag, user)] # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
      end

      Hash[flags]
    end
  end
end
