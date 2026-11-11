# typed: true
# frozen_string_literal: true

module Audit
  module Multi
    # Log audit events to multiple places.
    class Logger
      attr_reader :loggers

      def initialize(*loggers)
        @loggers = loggers.select { |logger| logger && logger.respond_to?(:perform) }
      end

      # Internal: Logs to the loggers
      #
      # payload - The Hash of data.
      #
      def perform(data)
        @loggers.collect do |logger|
          # Any logger could modify the payload and for that reason we want to
          # send a copy of the original value each time we ask a logger to
          # process it.
          if logger.instance_of?(::Audit::Elastic::Logger) && !GitHub.enterprise?
            next
          end
          logger.perform(data.dup)
        end
      end
    end
  end
end
