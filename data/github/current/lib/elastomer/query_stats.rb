# typed: true
# frozen_string_literal: true

require "github/colorize"

module Elastomer
  # Simple container for collecting ES query stats. These numbers are
  # displayed in the staff bar, and the actual queries are shown via a dialog.
  class QueryStats
    include Singleton
    include Enumerable

    # This is a singleton. Use the `QueryStats.instance` to get the instance.
    def initialize
      @ary = []
      @track = true
      clear
    end

    # Convenience method for checking for timeouts.
    def self.timed_out?
      instance.any? { |stat| stat.timed_out }
    end

    attr_reader :count, :time
    attr_accessor :track
    alias :track? :track

    # Add a new query hash to the stats collector.
    #
    # hash - A query Hash containing the :url, :body, and :time it took to run
    #
    # Returns this QueryStats instance.
    def <<(hash)
      if track?
        @count += 1
        @time += hash[:time]
        @ary << Stat.new(hash)
      end
      self
    end

    # Remove all current stats and clear out our list of queries.
    def clear
      @ary.clear
      @count = 0
      @time  = 0
    end

    # Iterate over the list of query stats. This method will yield a Stat
    # instance to the block.
    def each(&block)
      @ary.each(&block)
    end

    # Filters the list of query stats. This yields a smaller list of stats.
    def filter(&block)
      @ary.filter(&block)
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
