# typed: true
# frozen_string_literal: true

require "github/config/stats"
require "scrolls"
require "github/logging/otel_logger"

module GitHub
  class Logger < ActiveSupport::Logger

    DEVELOPMENT_LOG_FILE = "log/development.log"
    PERSONAL_LOG_FILE = "log/personal.log"
    METHOD_DEPRECATED = ".%s is deprecated and will be removed from GitHub::Logger"

    # Null logger so we don't keep a giant StringIO
    # when logging is disabled that keeps growing
    # in memory.
    class NullStream
      def write(line)
      end
    end

    # LogSubscriber has more constants available, these are just the ones
    # we're using for formatting here
    RED = ActiveSupport::LogSubscriber::RED
    YELLOW = ActiveSupport::LogSubscriber::YELLOW
    MODES = ActiveSupport::LogSubscriber::MODES

    # Public: Log data and/or wrap a block with start/finish
    #
    # data - A hash of key/values to log
    # blk  - A block to be wrapped by log lines
    #
    def self.log(data, &blk)
      return log_with_block(data, &blk) if blk

      GitHub.dogstats.distribution_time("github.github_logger.log_duration", tags: ["method:log", "backend:#{_internal_get_logger.class.name}", "with_block:false"]) do
        _internal_get_logger.log(data)
      end
    end

    def self.log_with_block(data, &blk)
      return unless blk

      block_duration = T.let(0.0, Numeric)

      wrapped_block = proc do
        block_start = T.cast(GitHub::Dogstats.monotonic_time, Numeric)
        blk.call
      ensure
        block_duration = T.cast(GitHub::Dogstats.monotonic_time, Numeric) - T.must(block_start)
      end

      start = GitHub::Dogstats.monotonic_time
      _internal_get_logger.log(data, &wrapped_block)

    ensure
      elapsed = GitHub::Dogstats.monotonic_time - T.must(start) - T.must(block_duration)
      elapsed_ms = (elapsed * 1000).round
      GitHub.dogstats.distribution("github.github_logger.log_duration", elapsed_ms, tags: ["method:log", "backend:#{_internal_get_logger.class.name}", "with_block:true"])
    end

    # Public: Set a context in a block for logs
    #
    # The context here is thread safe inside Scrolls and
    # only applies to the current running thread.
    #
    # data - A hash of key/values to prepend to each log in a block
    # blk  - The block that our context wraps
    #
    def self.log_context(data, &blk)
      _internal_get_logger.with_context(data, &blk)
    end

    # Public: Set a context for logs and wrap a block with start/finish.
    # Same as calling:
    #   logger.log_context(data) do
    #     logger.log(data) do
    #       logic
    #     end
    #   end
    #
    # data - A hash of key/values to prepend to each log in a block
    #
    def self.log_with_context(data)
      log_context(data) { log(data) { yield } }
    end

    # Public: Log an exception
    #
    # data - A hash of key/values to log
    # e    - An exception to pass to the logger
    #
    def self.log_exception(data, e)
      GitHub.dogstats.distribution_time("github.github_logger.log_duration", tags: ["method:log_exception", "backend:#{_internal_get_logger.class.name}", "with_block:false"]) do
        _internal_get_logger.log_exception(e, data)
      end
    end

    # Internal: Default logging data for each log message
    #
    # Returns Hash
    def self.default_log_data
      result = { "app" => "github", "env" => GitHub::AppEnvironment.env }
      if GitHub.enterprise?
        result["enterprise"] = true
      end
      result
    end

    # Public: An empty HashWithIndifferentAccess to be used for accumulating
    # application log data.
    def self.empty
      HashWithIndifferentAccess.new
    end

    # Internal: Create a new Scrolls logger instance with the given destination
    #
    # Only the destination is configured, the rest uses the default options
    # set during `setup`.
    # Options
    #  :log_path => The custom log file path where logs will be written to. Used
    #               with GitHub::Config::Logging::Destination::FILE destination
    #  :global_context => Used by ghe-migrator to override global context in logging. This ensures
    #                     guid and command are present when sending logs to ghe-migrator.log
    #
    # Returns a new Scrolls logger instance
    def self.setup_logger(destination = GitHub::Config::Logging.destination, options: {})
      logger_options = @default_options.dup
      logger_options[:global_context] = options[:global_context] if options[:global_context].present?
      case destination
      when GitHub::Config::Logging::Destination::SYSLOG
        logger_options[:stream] = "syslog"
        logger_options[:facility] = "local7"
        # syslog ingress will have its own timestamp
        logger_options[:timestamp] = false
      when GitHub::Config::Logging::Destination::STDOUT
        logger_options[:timestamp] = true
      when GitHub::Config::Logging::Destination::FILE
        logger_options[:stream] = File.open(options[:log_path], "a")
        logger_options[:timestamp] = true
      when GitHub::Config::Logging::Destination::NULL
        logger_options[:stream] = NullStream.new
      end

      if GitHub.otel_logger_enabled?
        GitHub::Logging::OTelLogger.new(logger_options)
      else
        Scrolls::Logger.new(logger_options)
      end
    end

    # Internal: Do everything needed to use GitHub::Logger.log
    # ie global context, syslog in production
    # For ghe-migrator, pass in options hash with log_path and global_context fields to
    # configure logging for migrations
    def self.setup(destination = GitHub::Config::Logging.destination, options: {})
      @default_options = {
        global_context: default_log_data,
        exceptions: "single",
        strict_logfmt: true
      }
      @default_logger = setup_logger(destination, options: options)
      self._internal_set_logger = @default_logger
    end

    def self.is_setup?
      !@default_logger.nil?
    end

    # Internal: Disable logging to syslog and STDOUT.
    def self.disable
      self.setup(GitHub::Config::Logging::Destination::NULL)
    end

    # Public: Compatibility methods for various loggers.
    #
    # Convience wrapper methods so we can use GitHub::Logger in some specific
    # places (for example: env['rack.errors'], or Logger like instances).
    #
    # These are copied to add the level from Scrolls since the only method
    # Scrolls provides is the global non thread safe option and this logic is
    # not part of the logger instance object.
    #
    def self.puts(data, &blk)
      self.log(data, &blk)
    end

    # Public: Log at the Rails error level
    #
    # This maps to the Scrolls warning level, this is the same
    # as the current Scrolls implementation so the difference
    # is deliberate here.
    def self.error(data, &blk)
      data = data.merge(level: "warning") if data.is_a?(Hash)
      self.log(data, &blk)
    end

    # Public: Log at the Rails fatal level
    #
    # This maps to the Scrolls error level, this is the same
    # as the current Scrolls implementation so the difference
    # is deliberate here.
    def self.fatal(data, &blk)
      data = data.merge(level: "error") if data.is_a?(Hash)
      self.log(data, &blk)
    end

    # Public: Log at the Rails info level
    def self.info(data, &blk)
      data = data.merge(level: "info") if data.is_a?(Hash)
      self.log(data, &blk)
    end

    # Public: Log at the Rails info level
    #
    # This maps to the Scrolls notice level, this is the same
    # as the current Scrolls implementation so the difference
    # is deliberate here.
    def self.warn(data, &blk)
      data = data.merge(level: "notice") if data.is_a?(Hash)
      self.log(data, &blk)
    end

    # Public: Log at the Rails debug level
    def self.debug(data, &blk)
      data = data.merge(level: "debug") if data.is_a?(Hash)
      self.log(data, &blk)
    end

    # Public: Log at the Rails info level
    #
    # This maps to the Scrolls alert level, this is the same
    # as the current Scrolls implementation so the difference
    # is deliberate here.
    def self.unknown(data, &blk)
      data = data.merge(level: "alert") if data.is_a?(Hash)
      self.log(data, &blk)
    end

    def initialize(*args)
      super
      @personal = ActiveSupport::Logger.new(GitHub::AppEnvironment.root.join(PERSONAL_LOG_FILE))
      @indent_level = 0
    end

    def mine(message = nil)
      if message
        add(::Logger::INFO, message)
        @personal.add(::Logger::INFO, message)
      end

      if block_given?
        @indent_level += 1
        called_from = first_useful_caller

        @personal.add(::Logger::INFO, " ") if @indent_level == 1
        @personal.add(::Logger::INFO, formatted("Beginning block in #{called_from}", RED, true))
        res = yield @personal
        @personal.add(::Logger::INFO, formatted("Finished block in #{called_from}", RED, true))
        @personal.add(::Logger::INFO, " ") if @indent_level == 1

        res
      end
    ensure
      @indent_level -= 1 if block_given?
    end

    # These are stack trace entries we don't care about when looking for the
    # original caller for a log call
    CALLER_EXCLUSION_LIST = [
        GitHub::AppEnvironment.root.join("vendor"),
        GitHub::AppEnvironment.root.join("lib/github/logger.rb"),
    ].map(&:to_s)

    def add(severity, message = nil, progname = nil, &block)
      super(severity, message, progname, &block)

      if overriding?
        origin = first_useful_caller

        @personal.add(severity, formatted("Called from #{origin}", YELLOW), progname, &block)
        @personal.add(severity, formatted(message), formatted(progname), &block)
      end
    end

    private

    def overriding?
      @indent_level > 0
    end

    def formatted(message, color = nil, bold = false)
      return if message.nil?

      indent = "  " * (@indent_level - 1)
      bold = bold ? mode_to_ansi(:bold) : nil
      clear = bold || color ? mode_to_ansi(:clear) : nil

      "#{indent}#{bold}#{color}#{message.lstrip}#{clear}"
    end

    def mode_to_ansi(mode)
      "\e[#{MODES[mode]}m"
    end

    def first_useful_caller
      caller.find do |line|
        CALLER_EXCLUSION_LIST.none? { |start| line.start_with?(start) }
      end
    end

    private_class_method def self._internal_set_logger=(logger)
      Thread.current.thread_variable_set(:__github_logger_thread_local, logger)
    end

    private_class_method def self._internal_get_logger
      if !Thread.current.thread_variables.include?(:__github_logger_thread_local) && is_setup?
        Thread.current.thread_variable_set(:__github_logger_thread_local, @default_logger)
      end
      Thread.current.thread_variable_get(:__github_logger_thread_local)
    end
  end
end
