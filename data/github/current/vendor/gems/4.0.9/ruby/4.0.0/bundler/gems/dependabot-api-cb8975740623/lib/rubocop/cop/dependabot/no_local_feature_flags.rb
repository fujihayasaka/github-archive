# frozen_string_literal: true

module RuboCop
  module Cop
    module Dependabot
      # Prevents usage of local Flipper-based feature flags.
      #
      # Local feature flags stored in the dependabot-api Flipper database are
      # deprecated. Use monolith feature flags instead via `monolith_feature_enabled?`.
      #
      # See https://github.com/github/dependabot-updates/blob/main/docs/feature-flags.md
      #
      # @example
      #   # bad
      #   repo.config_feature_enabled?(:my_feature)
      #   repo.org_level_flag_enabled?(:my_feature)
      #   repo.repo_level_flag_enabled?(:my_feature)
      #   repo.enable_feature(:my_feature)
      #   repo.disable_feature(:my_feature)
      #   Dependabot.flipper[:my_feature].enable
      #
      #   # good
      #   repo.monolith_feature_enabled?(:dependabot_my_feature)
      #   account.monolith_feature_enabled?(:dependabot_my_feature)
      #   Dependabot::Application.monolith_feature_enabled?(
      #     feature: :dependabot_my_feature,
      #     actor: repo
      #   )
      class NoLocalFeatureFlags < Base
        MSG = "Local Flipper feature flags are deprecated. " \
              "Use `monolith_feature_enabled?` instead. " \
              "See https://github.com/github/dependabot-updates/blob/main/docs/feature-flags.md"

        FLIPPER_MSG = "Direct `Dependabot.flipper` access is deprecated. " \
                      "Use `monolith_feature_enabled?` instead. " \
                      "See https://github.com/github/dependabot-updates/blob/main/docs/feature-flags.md"

        # Match calls to deprecated feature flag methods
        # e.g. repo.config_feature_enabled?(:foo)
        def_node_matcher :deprecated_feature_flag_call?, <<~PATTERN
          (send _ {:config_feature_enabled? :org_level_flag_enabled? :repo_level_flag_enabled? :enable_feature :disable_feature} ...)
        PATTERN

        # Match direct access to Dependabot.flipper
        # e.g. Dependabot.flipper[:foo]
        def_node_matcher :flipper_access?, <<~PATTERN
          (send (const nil? :Dependabot) :flipper)
        PATTERN

        def on_send(node)
          if deprecated_feature_flag_call?(node)
            add_offense(node, message: MSG)
          elsif flipper_access?(node)
            add_offense(node, message: FLIPPER_MSG)
          end
        end
      end
    end
  end
end
