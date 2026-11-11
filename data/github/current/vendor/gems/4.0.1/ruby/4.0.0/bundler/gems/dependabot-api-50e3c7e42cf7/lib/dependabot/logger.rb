# frozen_string_literal: true

require "scrolls"

# Hi! This file was copied from github/github in order to implement
# Splunk-compatible logging for dependabot-api (there's a similar file in
# dependency-graph-api). Maybe one day this will be extracted into a Gem, but
# for now, it will sit here and get the job done.
# - @hmarr (November 7, 2019)

module Dependabot
  class Logger
    # Public: Log data and/or wrap a block with start/finish
    #
    # data - A hash of key/values to log
    # blk  - A block to be wrapped by log lines
    #
    def self.log(data, &blk)
      Scrolls.log(data, &blk)
    end

    # Public: Set a context in a block for logs
    #
    # data - A hash of key/values to prepend to each log in a block
    # blk  - The block that our context wraps
    #
    def self.log_context(data, &blk)
      Scrolls.context(data, &blk)
    end

    # Public: Log an exception
    #
    # err  - An exception to pass to the logger
    # data - A hash of key/values to log
    #
    def self.log_exception(err, data)
      Scrolls.log_exception(err, data)
    end

    # Internal: Default logging data for each log message
    #
    # Returns Hash
    def self.default_log_data
      { "app" => "dependabot-api", "env" => Rails.env }
    end

    # Public: An empty HashWithIndifferentAccess to be used for accumulating
    # application log data.
    def self.empty
      HashWithIndifferentAccess.new
    end

    # Internal: Do everything needed to use Dependabot::Logger.log
    # ie global context
    def self.setup
      options = {
        global_context: default_log_data,
        exceptions: "single",
      }

      Scrolls.init(options)
    end

    # Internal: Disable logging to syslog and STDOUT.
    def self.disable
      Scrolls.stream = StringIO.new
    end

    # Public: Compatibility methods for various loggers.
    #
    # Convience wrapper methods so we can use Dependabot::Logger in some
    # specific places (for example: env['rack.errors'], or Logger like
    # instances).
    #
    def self.puts(data, &blk)
      Scrolls.log(data, &blk)
    end

    def self.error(data, &blk)
      Scrolls.error(data, &blk)
    end

    def self.fatal(data, &blk)
      Scrolls.fatal(data, &blk)
    end

    def self.info(data, &blk)
      Scrolls.info(data, &blk)
    end

    def self.warn(data, &blk)
      Scrolls.warn(data, &blk)
    end

    def self.unknown(data, &blk)
      Scrolls.unknown(data, &blk)
    end
  end
end
