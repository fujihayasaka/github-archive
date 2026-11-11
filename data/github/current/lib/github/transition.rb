# typed: true
# frozen_string_literal: true

ENV["GH_TRANSITION"] = "true"

require "github/sql/readonly"
require "progeny"

# Base class for safer GitHub data transitions
#
# This transition base class is safer in that it defaults
# to a dry_run mode.  In dry run mode it will use the read-only Mysql
# connection to ensure any errant writes fail.
#
module GitHub

  module WithPrefixlessBackgroundJobQueues
    def perform(*, **)
      strip_prefix do
        super
      end
    end

    def process(*, **)
      strip_prefix do
        super
      end
    end

    private

    # Private: Make sure jobs are enqueued to the prefixless queues so that they
    # are worked on by the full fleet of workers, not just the few workers we have
    # in staff environments (lab/garage/review-lab) in the case that we're running
    # the transition from one of the staff environment. This is a no-op when
    # running in full production
    def strip_prefix
      old_prefix = GitHub.background_job_queue_prefix
      GitHub.background_job_queue_prefix = nil
      yield
    ensure
      GitHub.background_job_queue_prefix = old_prefix
    end
  end

  class Transition

    MAX_THROTTLE_RETRIES = 5

    attr_reader :dry_run, :verbose, :other_args, :log_lines

    def self.inherited(subclass)
      subclass.prepend(WithPrefixlessBackgroundJobQueues)
      super
    end

    # Create an instance of the transition.
    #   dry_run: used for testing and viewing the output of what *would* change
    #   verbose: used for detailed output
    #   other_args: an arbitrary hash of any extra arguments needed for the transition
    def initialize(dry_run: true, verbose: false, **other_args)
      @started_at = Time.now.utc
      @verbose = verbose
      @dry_run = dry_run
      @other_args = other_args

      log "Creating transition #{name} at #{started_at}"
      if verbose?
        log "  dry_run: #{dry_run?} verbose: #{verbose?} other_args: #{other_args}"
      end

      STDOUT.sync = true # always print immediately even if piping to a log file
      init_context

      after_initialize
    end

    # Public: Hook method called after initialize is called
    #
    # Subclasses can override this to do any other setup needed if they so desire
    def after_initialize
    end

    # Public: Driver method to run the transition.
    #
    # Subclasses should override perform, not this method.  This method ensures
    # that we in a read only mode if the transition is run in dry_run mode.
    #
    # Returns the result of `perform`
    def run
      log "Starting #{name}#run"
      log "[dry_run] In dry_run mode" if dry_run?
      emit_delorean_event(occurred_at: started_at, operation: "started") unless dry_run?
      error_raised = false
      result = enforce_read_only_if_dry_run do
        perform
      end
    rescue StandardError => e # rubocop:todo Lint/RescueException
      unless dry_run?
        emit_delorean_event(occurred_at: Time.current, operation: "failed")
        error_raised = true
      end
      raise e
    ensure
      set_ended_at
      emit_delorean_event(occurred_at: ended_at, operation: "completed") unless dry_run? || error_raised

      log "Finished #{name}#run at #{ended_at}"
      result
    end

    # Do the actual work of the transition.
    #
    # Subclasses should implement this method.
    def perform
      raise "Implement perform for #{self}"
    end
    private :perform

    def process(*args)
      raise "Implement process for #{self}"
    end
    private :process

    private

    # Private: The start time that this transition began at.
    #
    # Returns Time
    def started_at
      @started_at
    end

    # Private: The end time when things finished.
    #
    # Returns nil or Time
    def ended_at
      @ended_at
    end

    # Private: Is this transition in a dry run mode?
    def dry_run?
      @dry_run
    end

    # Private: Who started running this transition? (via gudo)
    def sudo_user
      ENV["SUDO_USER"]
    end

    # Private: Should we verbosely print out status?
    def verbose?
      @verbose
    end

    # Private: Write a log message - send to STDOUT if not in test
    def log(message)
      Rails.logger.debug message
      @log_lines ||= []
      log_lines << message if Rails.env.test?
      return if Rails.env.test?
      puts "[#{Time.now.iso8601.sub(/-\d+:\d+$/, '')}] #{message}"
      STDOUT.flush
    end

    # Private: Write live-updating status message to stderr.
    def status(message, *args)
      return if !$stderr.tty?
      $stderr.printf(" #{message}\n", *args)
    end

    # Private: Setup Failbot, GitHub & Audit context
    def init_context
      context = {
        actor: ENV["USER"],
        app: "github-transitions",
        console_host: Socket.gethostname,
        sudo_user: sudo_user,
        transition: name,
        transition_started_at: started_at,
      }
      Failbot.push context
      GitHub.context.push context
      Audit.context.push context
    end

    # Private: Enforce a read only database connection if we are in dry_run mode
    # mode.
    def enforce_read_only_if_dry_run
      if dry_run?
        @original_read_only = GitHub.read_only?
        GitHub.read_only = true
      end
      yield
    ensure
      if dry_run?
        GitHub.read_only = @original_read_only
      end
    end

    # Private: name of the current transition for logs / debugging.
    def name
      self.class.to_s.underscore
    end

    def set_ended_at
      @ended_at = Time.now.utc

      context = { transition_ended_at: ended_at }

      GitHub.context.push context
      Audit.context.push context
      Failbot.push context
    end

    def emit_delorean_event(occurred_at:, operation:)
      return unless GitHub.publish_events_to_delorean?
      return if FeatureFlag.vexi.enabled?(:disable_delorean_publishing, default: false)

      url = "https://github.com/github/github/blob/#{GitHub.current_sha}/lib/github/transitions/#{identifier}"
      GitHub.delorean_client.publish_event(
        timeline_id: 1,
        type: "database_transition",
        operation: operation,
        title: "Database transition #{operation}: '#{identifier}'",
        description: [
          "- **actor**: @#{sudo_user}",
          "- **command**: `#{command_line}`",
          "- **console host**: `#{GitHub.context[:console_host]}`",
        ].join("\n"),
        occurred_at: occurred_at,
        actions: { "Source code" => url },
        group_key: "database_transition_#{identifier}"
      )
    rescue => e # rubocop:todo Lint/RescueException
      # If Delorean is down or our client code has an issue, we don't want to affect transitions
      Failbot.report(e)
      GitHub.dogstats.increment("transition.publish_delorean_event.failure")
    end

    # Private: Command Line used to call transition
    def command_line
      @command_line ||= Progeny::Command.new("ps -p #{$$} -o args --no-headers").out.strip
    end

    # Private: Identifier of this transition
    def identifier
      @identifier ||= File.basename($0) # filename of transition run
    end

    # Private: Wrap a block of code with readonly replica usage.
    #
    # Reads are not throttled automatically here, because writes to primaries
    # are slow enough that reads from replicas do not become an issue. If throttling
    # is needed for reads, that should done explicitly at the point where the reads
    # are happening.
    #
    # This also disables the slow query logger for the duration of the block, as
    # it's expected that readonly queries in transitions are frequently slow
    # enough to trigger the logger unnecessarily.
    #
    # IMPORTANT: if you're using this, and your query might really be a bad one,
    # please notify Ops. It's still possible to take down the database/site
    # with a bad query, even when using the read replicas.
    #
    def readonly(&block)
      ActiveRecord::Base.connected_to(role: :reading) do
        SlowQueryLogger.disabled(&block)
      end
    end
  end
end
