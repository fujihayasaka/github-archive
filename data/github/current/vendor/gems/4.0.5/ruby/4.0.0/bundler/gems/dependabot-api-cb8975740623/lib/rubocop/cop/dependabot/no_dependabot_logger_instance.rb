# frozen_string_literal: true

module RuboCop
  module Cop
    module Dependabot
      # Prevents usage of `Dependabot.logger` (the dependabot-core logger
      # instance) in application code. Use `Dependabot::Logger` (the app's
      # Scrolls-based structured logger) instead.
      #
      # `Dependabot.logger` is the Rails logger assigned in the initializer
      # for use by dependabot-core internals. Application code should use
      # `Dependabot::Logger` which provides structured key-value logging
      # via Scrolls.
      #
      # @example
      #   # bad
      #   Dependabot.logger.info(msg: "something happened")
      #
      #   # good
      #   Dependabot::Logger.info(msg: "something happened")
      class NoDependabotLoggerInstance < Base
        extend AutoCorrector

        MSG = "Use `Dependabot::Logger` (structured Scrolls logger) instead of " \
              "`Dependabot.logger` (dependabot-core Rails logger)."

        # Match `Dependabot.logger` and `::Dependabot.logger`
        # e.g. Dependabot.logger.info(...) or ::Dependabot.logger.info(...)
        def_node_matcher :dependabot_logger_call?, <<~PATTERN
          (send (const {nil? cbase} :Dependabot) :logger)
        PATTERN

        def on_send(node)
          return unless dependabot_logger_call?(node)

          add_offense(node) do |corrector|
            corrector.replace(node, "Dependabot::Logger")
          end
        end
      end
    end
  end
end
