# typed: true
# frozen_string_literal: true

require "active_support/core_ext"
require "github/config/notifications"

module GitHub
  # Times an entire request, as well as sub-portions of that request as
  # indicated via GitHub.instrument().
  class RequestTimer
    EventStats = Struct.new(:count, :duration)

    EVENT_ALLOWLIST = Set[
      "ability.team.user_ids_for",
      "ack_message.producer.kafka",
      "adapter_operation.flipper",
      "deliver_messages.producer.kafka",
      "issue.create",
      "issue.event.assigned",
      "migration.create",
      "migration.download",
      "org.remove_outside_collaborator",
      "pull_request.synchronize",
      "query.graphql",
      "remote_call.gitrpc",
      "security_key.register",
      "user.change_password",

      # These entries are only used in tests
      "foo.baz",
      "charge.foo",
      "charge.bar",
    ].freeze

    def initialize
      reset!
      @subscribers = EVENT_ALLOWLIST.map do |event|
        GitHub.subscribe(event) do |name, start, finish, id, payload|
          track_event(name, start, finish, id, payload)
        end
      end
    end

    # Stops tracking all events. Mostly useful for testing.
    #
    # Returns nothing.
    def stop_tracking!
      @subscribers.each { |subscriber| GitHub.unsubscribe(subscriber) }
    end

    def stats
      # duplicate the hash in order to safely iterate through it
      # see https://github.com/github/github/pull/81279
      @stats_hash.clone.freeze
    end

    # Computes the amount of time spent in a particular
    # ActiveSupport::Notification instrumentation block so far in this request.
    #
    # name - The String event name passed to GitHub.instrument.
    #
    # Returns a Float number of seconds.
    def elapsed(name = nil)
      @stats_hash.key?(name) ? @stats_hash[name].duration / 1000.0 : 0
    end

    # Formats stats as a table suitable for terminal output or inclusion in
    # Failbot context.
    #
    # Returns a formatted String.
    def formatted_stats
      rows = stats
        .sort_by { |_name, stat| -stat.duration }
        .map     { |name, stat| sprintf("%7.3f | %7d | %s\n", stat.duration / 1000.0, stat.count, name) }

      sprintf("%7s | %7s | %s\n%s", "Seconds", "Count", "Name", rows.join(""))
    end

    # Resets all durations and counts. Call this at the start of each request.
    #
    # Returns nothing.
    def reset!
      @stats_hash = Hash.new { |h, k| h[k] = EventStats.new(0, 0) }
    end

    # Records all durations and counts to Graphite. Call this at the end of
    # each request.
    #
    # Each tracked notification is recorded in request_timer.events.dist.
    #
    # Returns nothing.
    def record!
      stats = self.stats
      total = stats.sum { |_name, stat| stat.count }
      GitHub.dogstats.distribution("request_timer.total_events.count", total)

      stats.each do |name, stats|
        if EVENT_ALLOWLIST.include?(name)
          GitHub.dogstats.timing("request_timer.events.time", stats.duration, tags: ["event:#{name}"])
        end
      end
    end

    private

    def track_event(name, start, finish, id, payload)
      event = ActiveSupport::Notifications::Event.new(name, start, finish, id, payload)
      stats = @stats_hash[event.name]
      stats.count += 1
      stats.duration += event.duration
    end
  end
end
