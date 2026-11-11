# frozen_string_literal: true

# Base class for data transitions
#
# TODO: Edit
# This transition base class is safer in that it defaults
# to a dry_run mode.  In dry run mode it will use the read-only Mysql
# connection to ensure any errant writes fail.
#
module Dependabot
  class Transition
    attr_reader :dry_run, :verbose, :other_args, :started_at, :ended_at

    # Create an instance of the transition.
    #   dry_run: used for testing and viewing the output of what *would* change
    #   verbose: used for detailed output
    #   other_args: an arbitrary hash of any extra arguments for the transition
    def initialize(dry_run: true, verbose: false, **other_args)
      @started_at = Time.now.utc
      @verbose = verbose
      @dry_run = dry_run
      @other_args = other_args

      log "Creating transition #{name} at #{started_at}"
      if verbose?
        log "  dry_run: #{dry_run?}"
        log "  verbose: #{verbose?}"
        log "  other_args: #{other_args}"
      end

      $stdout.sync = true # always print immediately even if piping to a log file
      after_initialize
    end

    # Public: Hook method called after initialize is called
    #
    # Subclasses can override this to do any other setup needed
    def after_initialize; end

    # Public: Driver method to run the transition.
    #
    # Subclasses should override perform, not this method.  This method ensures
    # that we in a read only mode if the transition is run in dry_run mode.
    #
    # Returns the result of `perform`
    def run
      log "Starting #{name}#run"
      log "[dry_run] In dry_run mode" if dry_run?
      result = perform
    ensure
      set_ended_at

      log "Finished #{name}#run at #{ended_at}"
      result
    end

    private

    # Do the actual work of the transition.
    #
    # Subclasses should implement this method.
    def perform
      raise "Implement perform for #{self}"
    end

    # Private: Is this transition in a dry run mode?
    def dry_run?
      @dry_run
    end

    # Private: Should we verbosely print out status?
    def verbose?
      @verbose
    end

    # Private: Write a log message - send to STDOUT if not in test
    # rubocop:disable Rails/Output
    def log(message)
      Rails.logger.debug message
      return if Rails.env.test?

      puts "[#{Time.now.iso8601.sub(/-\d+:\d+$/, '')}] #{message}"
      $stdout.flush
    end
    # rubocop:enable Rails/Output

    # Private: name of the current transition for logs / debugging.
    def name
      self.class.to_s.underscore
    end

    def set_ended_at
      @ended_at = Time.now.utc
    end
  end
end
