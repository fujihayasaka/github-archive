# typed: true
# frozen_string_literal: true

module SlowQueryLogger
  # This is an array of tuples, representing queries for which we don't want to record exceptions.
  #
  # For each, t0 is a filename to ignore and t1 is a method name.
  # If an exception backtrace includes a line with that filename and that method, the query will be
  # ignored. This allows for fine-grained ignoring.
  #
  # Additionally, if nil is given as t1, then any backtrace with that filename will be ignored. This allows
  # ignoring for any exception that calls anything in that file, regardless of method.
  IGNORED = [
              ["lib/timer_daemon.rb", nil],                      # all run at intervals
              ["jobs/update_total_counts.rb", nil],
              ["app/models/trending.rb", nil],
              ["lib/github/dgit/delegate.rb", nil],
            ]

  class SlowQuery < StandardError
    def initialize(sql, time)
      super("[%.2f sec]  %s" % [time, sql])
    end
  end

  class << self
    attr_accessor :enabled
  end

  # Disable the slow query logger for the duration of the block. Please use with
  # caution and only with the readonly connection.
  def self.disabled
    @enabled = false
    yield
  ensure
    @enabled = true
  end

  self.enabled = true

  # A somewhat hackish way to determine if we should skip this particular slow query
  # and not send it to Sentry. Checks each line of the trace to see if it includes
  # an ignorable file. Will also skip if the slow query logger is disabled via
  # SlowQueryLogger.disable.
  #
  # Returns true or false.
  def self.should_skip?(trace)
    return true if !enabled
    return true if ENV.fetch("GH_PERF_NEEDLES_DISABLED", 0) != 0

    paths_and_methods = trace.map { |t| [t.split(":")[0], t.split(":")[2]] }

    # For each line of the backtrace..
    paths_and_methods.each do |path, method|

      # And for each (path, method) tuple we are to ignore..
      IGNORED.each do |ignored_path, ignored_method|
        if path.include?(ignored_path)
          # We should ignore this path. Let's check if we should ignore based on method..
          if ignored_method.nil? || method.include?(ignored_method)
            return true
          end
        end
      end
    end

    false # nothing matched
  end
end
