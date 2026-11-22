# typed: true
# frozen_string_literal: true

require "github/colorize"

module Elastomer
  # Simple per-thread container for collecting ES query stats. These numbers are
  # displayed in the staff bar, and the actual queries are shown via a dialog.
  class QueryStats
    include Singleton
    include Enumerable

    THREAD_STATE_KEY = :elastomer_query_stats_state
    State = Struct.new(:queries, :count, :time, :track, keyword_init: true)

    # Convenience method for checking for timeouts.
    def self.timed_out?
      instance.any? { |stat| stat.timed_out }
    end

    def count
      state.count
    end

    def time
      state.time
    end

    def track
      state.track
    end

    def track=(value)
      state.track = value
    end

    alias :track? :track

    # Add a new query hash to the stats collector.
    #
    # hash - A query Hash containing the :url, :body, and :time it took to run
    #
    # Returns this QueryStats instance.
    def <<(hash)
      if track?
        state.count += 1
        state.time += hash[:time]
        state.queries << Stat.new(hash)
      end
      self
    end

    # Remove all current stats and clear out our list of queries.
    def clear
      state.queries.clear
      state.count = 0
      state.time = 0
    end

    # Iterate over the list of query stats. This method will yield a Stat
    # instance to the block.
    def each(&block)
      state.queries.each(&block)
    end

    # Filters the list of query stats. This yields a smaller list of stats.
    def filter(&block)
      state.queries.filter(&block)
    end

    private

    def state
      thread = if defined?(GitHub::DataCollector) && GitHub::DataCollector.respond_to?(:collector_thread)
        GitHub::DataCollector.collector_thread
      else
        Thread.current
      end

      thread.thread_variable_get(THREAD_STATE_KEY) ||
        thread.thread_variable_set(
          THREAD_STATE_KEY,
          State.new(queries: [], count: 0, time: 0, track: true)
        )
    end

    # Little convenience wrapper around the query stats. It provides accessors
    # for the query body and a syntax highlighted query body. We also have a
    # `curl` method for getting a curl command you can copy/paste to the
    # command line.
    class Stat
      # Create a new Stat given a Hash of data about the query.
      #
      # hash - A query Hash containing the :url, :body, and :time it took to run
      def initialize(hash)
        @url = hash[:url]
        @body = hash[:body]
        @time = hash[:time]
        @total = hash[:total] || 0
        @timed_out = hash[:timed_out]
      end

      attr_reader :time, :url, :total, :timed_out

      # Returns the query body as a pretty-printed JSON String.
      def body
        return @pretty_body if defined? @pretty_body
        h = JSON.parse(@body)
        @pretty_body = JSON.pretty_generate(h)
      end

      # Returns the query body _without_ pretty-printing the JSON
      def original_body
        @body
      end

      # Returns the query body as an HTML highlighted String.
      def hl_body
        return @hl_body if defined? @hl_body
        @hl_body = GitHub::Colorize.highlight_json(body)
      end

      def url_path
        @url.path
      end

      def cluster
        @url.host.split(".").first
      end

      # Returns a curl command as a String.
      def curl
        return @curl if defined? @curl

        url = @url.dup
        url.query = url.query.nil? ? "pretty" : "pretty&#{url.query}"
        @curl = "curl -v -XGET '#{url}' -d '#{@body}'"
      end
    end
  end
end
