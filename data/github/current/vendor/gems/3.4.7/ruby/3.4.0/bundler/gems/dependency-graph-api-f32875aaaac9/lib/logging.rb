require "github/telemetry/logs"

module DependencyGraph
  module Logger
    # Monkey-patches the underlying SemanticLogger (which is itself wrapped by some GitHub Telemetry functions)
    # to add a method that we use to report exception context to Failbot
    module SemanticLoggerBasePatch
      # This will wrap the underlying (from github-telemetry-ruby) logger's with_named_tags method
      # and push the same tags to the current Failbot context.
      #
      # Exercise discretion about sending PII or data that is too customer sensitive here,
      # as Failbot logs will go to Sentry.
      # See https://thehub.github.com/support/worktent/sensitive-data/delete-data/#what-is-sensitive-data
      #
      # context - A hash of key/values to prepend to each log in a block
      # blk     - The block that our context wraps
      def log_and_failbot_context(context, &blk)
        Failbot.push(context) do
          with_named_tags(context, &blk)
        end
      end
    end
  end

  # Module-level logger object that allows code to call DependencyGraph.logger.{...}
  def self.logger
    @logger ||= GitHub::Telemetry::Logs.logger
  end
end

SemanticLogger::Base.prepend(DependencyGraph::Logger::SemanticLoggerBasePatch)
