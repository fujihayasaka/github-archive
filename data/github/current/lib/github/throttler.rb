# typed: true
# frozen_string_literal: true
require "active_support/core_ext/string" # String#camelize
require "freno/throttler"
require "github/throttler/datadog_instrumenter"
require "github/throttler/freno_stats_instrumenter"
require "github/throttler/instrumenter_chain"
require "github/throttler/safe_identity_mapper"
require "github/throttler/null"
require "github/throttler/per_second"
require "github/database_structure"

module GitHub

  # The GitHub::Throttler module provides a `throttle` helper method for
  # throttling database queries intelligently.
  #
  # In enterprise, test, or dev, the throttling code is a noop, but in
  # dotcom production, the read replicas' replication delay is taken into
  # account and the `throttle` block will sleep until all of the active read
  # replicas have caught up.
  #
  # Some caveats:
  #
  # * This is only intended for use in places where waiting won't affect
  #   anything. More to the point, this is not for use in a web request cycle.
  #   Background jobs and transitions only!
  # * This only runs replication delay throttling in dotcom production, and
  #   unfortunately there's no better place to test it out.
  # * Be aware that throttling from inside a transaction will only wait for
  #   *other* transactions, and if the transaction you're running inside is
  #   large it may cause its own problems with the replicas when it is
  #   committed. Don't build up large units of work.
  #
  # Talk to the @github/platform-data team if you have more questions about
  # this module and how to use it.
  module Throttler

    class ThrottledUnicornRequestError < RuntimeError
      def initialize(m = nil)
        super(m || "Throttle called from Unicorn process.")
      end
    end

    def self.null
      @null_throttler ||= GitHub::Throttler::Null.new
    end

    class << self
      attr_accessor :test_mode
    end
    self.test_mode = false

    def self.wait(seconds = 1)
      unless test_mode
        Kernel.sleep(seconds)
      end
    end

    module Base
      include Kernel

      DEFAULT_RETRY_COUNT = 1

      # Public: throttle the given block using the default throttling mechanism.
      #
      # Returns the block's value.
      def throttle(noop_on_foreground: false, low_priority: false, skip_reporting: false)
        if noop_on_foreground && GitHub.foreground?
          return yield
        end

        prevent_foreground_throttling! unless skip_reporting

        throttler.throttle(affected_clusters, low_priority: low_priority) do
          yield
        end
      end

      # Public: throttle the given block and retry up to max_retry_count times
      # if we hit a Freno::Throttler::Error
      def throttle_with_retry(max_retry_count: DEFAULT_RETRY_COUNT, err_msg: nil, noop_on_foreground: false, low_priority: false, skip_reporting: false)
        retry_count = 0

        begin
          throttle(noop_on_foreground: noop_on_foreground, low_priority: low_priority, skip_reporting: skip_reporting) do
            yield
          end
        rescue Freno::Throttler::Error => e
          # A retry:0 tag means that throttle_with_retry's very first attempt
          # failed. No retry has occurred yet.
          #
          # retry:1 means that the _first retry_ failed.
          # retry:2 means the second retry failed, etc.
          GitHub.dogstats.increment("github.throttle_with_retry.error", tags: ["retry:#{retry_count}", "cluster:#{affected_clusters.join}"])

          if retry_count >= max_retry_count
            msg = "Throttler timed out after retrying #{retry_count} times. #{err_msg}"
            raise e, msg
          else
            retry_count += 1
            GitHub::Throttler.wait(retry_count)
            retry
          end
        end
      end

      # Internal: a throttler instance to use for throttling.
      def throttler
        @throttler ||= create_throttler
      end

      # Internal: creates a new instance of the throttler
      def create_throttler(options = {})
        if freno_throttler_enabled?
          # Freno actively waits for max_wait_seconds when the clusters are not OK.
          # This means that the freno request rate is at most 1 request / max_wait_seconds.
          # On the other hand, the circuit breaker only looks for requests in the last
          # window_size_in_seconds and only after the first request_volume_threshold requests.
          # As a result, for the circuit breaker to be effective when freno is consistently
          # failing, the following constraint must be satisfied:
          # request_volume_threshold * max_wait_seconds <= window_size_in_seconds,
          #
          # Once the circuit is open, it allows a request every sleep_window_seconds.
          # When clusters are consistently not OK, this means that freno requests
          # will be disallowed for max(0, sleep_window_seconds - max_wait_seconds).
          # This means that sleep_window_seconds should be bigger than max_wait_seconds
          # to prevent any request in case of failure.
          #
          # In summary, the bigger max_wait_seconds the higher the time to detect
          # and the time recover from failures.
          Freno::Throttler.new client: Freno.client,
                              app: :github,
                              max_wait_seconds: 30,
                              wait_seconds: 1,
                              mapper: SafeIdentityMapper.new,
                              circuit_breaker: Resilient::CircuitBreaker.get("freno-#{affected_clusters.join}", properties: {
                                instrumenter: GitHub,
                                request_volume_threshold: 2,
                                window_size_in_seconds: 120,
                                sleep_window_seconds: 60,
                                # Set the default explicitly.
                                error_threshold_percentage: 50,
                              }),
                              instrumenter: InstrumenterChain.new(
                                instrumenters: [
                                  DatadogInstrumenter.new,
                                  FrenoStatsInstrumenter.new,
                                ]
                              )
        else
          GitHub::Throttler::Null.new
        end
      end

      # Internal: whether the freno throttler is enabled or not.
      def freno_throttler_enabled?
        return false unless GitHub.freno_enabled?
        GitHub.environment.fetch("FRENO_THROTTLE", "1") == "1"
      end

      def prevent_foreground_throttling!
        if GitHub.foreground? && throttler.class != GitHub::Throttler::Null
          Failbot.report(ThrottledUnicornRequestError.new.tap { |e| e.set_backtrace(caller) },
                         throttler: throttler.class.name,
                         app: "github-freno")
        end
      end

      def affected_clusters
        raise "Not implemented"
      end
    end
  end
end
