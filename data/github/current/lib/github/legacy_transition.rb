# typed: true
# frozen_string_literal: true

# DEPRECATED: DON'T USE. Use Transition instead
#
# Legacy base class for GitHub data transitions
#
module GitHub
  class LegacyTransition
    class ImpossibleJoinsError < StandardError
      def initialize(msg = "This transition is a legacy transition and contains impossible joins due to the tables it's joining existing in separate clusters. If you need to run this transition in dotcom you will need to update it to remove joins. Legacy transitions still work on Enterprise since it doesn't use multiple clusters.")
        super
      end
    end

    def initialize
      STDOUT.sync = true # always print immediately even if piping to a log file
      Failbot.push app: "github-transitions"
    end

    # Internal: Wrap a block of code with readonly replica usage.
    #
    # This also disables the slow query logger for the duration of the block, as
    # it's expected that readonly queries in transitions are frequently slow
    # enough to trigger the logger unnecessarily.
    #
    # IMPORTANT: if you're using this, and your query might really be a bad one,
    # please notify the database team. It's still possible to take down the database/site
    # with a bad query, even when using the read replicas.
    #
    def readonly(&block)
      ActiveRecord::Base.connected_to(role: :reading) do
        SlowQueryLogger.disabled(&block)
      end
    end

    # Internal: Write a log message - send to STDOUT if not in test
    def log(message)
      Rails.logger.debug message
      return if Rails.env.test?
      puts "[#{Time.now.iso8601.sub(/-\d+:\d+$/, '')}] #{message}"
    end

    # Write live-updating status message to stderr.
    def status(message, *args)
      return if !$stderr.tty?
      $stderr.printf(" #{message}\r", *args)
    end
  end
end
