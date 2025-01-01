# typed: false
# frozen_string_literal: true

# This module implements the formatting and Pond response augmentation logic formerly handled by the
# deprecated analytics-app service.
module Pond
  module Granularity
    DAY = :DAY
  end

  module EventType
    CLONE = "clone"
    VIEW = "view"
  end

  module TopNType
    CONTENT = :content
    REFERRERS = :referrers
    REFERRER_PATHS = :referrer_paths
  end

  def self.format_time_series(**args)
    BucketedTimeSeries.new(**args).format
  end

  def self.format_top_n(**args)
    TopN.new(**args).format
  end

  class TopN
    def initialize(data:, top_n_type:, referrer: nil)
      @data = data
      @top_n_type = top_n_type
      @referrer = referrer
    end

    def format
      formatted = {
        top_n_type_key => @data.map do |value|
          tranformed = value.except("count", "uniques").merge({
            "total" => value["count"],
            "unique" => value["uniques"],
          })

          if @top_n_type == TopNType::REFERRERS
            tranformed.delete("searchEngine")
            tranformed["referrer_paths_allowed"] = referrer_paths_allowed?(value["referrer"])
          end

          tranformed
        end
      }

      if @top_n_type == TopNType::REFERRER_PATHS
        formatted["referrer"] = @referrer
      end

      formatted
    end

    private

    def top_n_type_key
      case @top_n_type
      when TopNType::CONTENT then "content"
      when TopNType::REFERRERS then "referrers"
      when TopNType::REFERRER_PATHS then "paths"
      end
    end

    def referrer_paths_allowed?(referrer)
      # Paths for search engines are not very meaningful.
      return false if SearchEngine.find_by_name(referrer)

      # Paths for github.com may expose private repositories.
      return false if /github\.com\z/i =~ referrer

      true
    end

    class SearchEngine
      def self.find_by_name(name) # rubocop:disable GitHub/FindByDef
        KNOWN_ENGINES[name]
      end

      attr_reader :domain

      def initialize(attrs = {})
        attrs.each_pair { |k, v| instance_variable_set(:"@#{k}", v) }
      end

      KNOWN_ENGINES = {
        "Google"     => SearchEngine.new(domain: "google.com"),
        "Yahoo"      => SearchEngine.new(domain: "search.yahoo.com"),
        "Bing"       => SearchEngine.new(domain: "bing.com"),
        "Search"     => SearchEngine.new(domain: "search.com"),
        "Ask"        => SearchEngine.new(domain: "ask.com"),
        "DuckDuckGo" => SearchEngine.new(domain: "duckduckgo.com"),
        "StartPage"  => SearchEngine.new(domain: "startpage.com"),
        "AOL"        => SearchEngine.new(domain: "search.aol.com"),
        "Baidu"      => SearchEngine.new(domain: "baidu.com"),
      }.freeze
    end
  end

  class BucketedTimeSeries
    BUCKET_SIZE = 86400 # One day

    # Public: Reformat raw Pond response data for display in graphs.
    # Emulates the data transformation behavior of the legacy analytics-app service + Octolytics gem.
    def initialize(data:, from:, to:, event_type:)
      @data = data
      @from = from
      @to = to
      @event_type = event_type
      @defaults = { "total" => 0, "unique" => 0 }
    end

    def format
      {
        "counts" => counts_with_defaults.reverse,
        "summary" => {
          "total" => @data["count"] || 0,
          "unique" => @data["uniques"] || 0,
        }
      }
    end

    private

    # Returns counts but fills in any bucket gaps with default values.
    def counts_with_defaults
      counts_by_bucket = counts.index_by { |c| c["bucket"] }

      first_bucket_value.step(@to.to_i, BUCKET_SIZE).map do |bucket|
        @defaults.merge counts_by_bucket[bucket] || { "bucket" => bucket }
      end
    end

    def counts
      @counts ||= @data[event_type_key].map do |bucket|
        {
          "bucket" => bucket["timestamp"] / 1000, # convert millis
          "total" => bucket["count"],
          "unique" => bucket["uniques"],
        }
      end
    end

    def event_type_key
      if @event_type == EventType::CLONE
        "clones"
      else
        "views"
      end
    end

    def first_bucket
      counts.map { |c| c["bucket"] }.min || @from.to_i
    end

    # Implementation borrowed from the deprecated analytics-app to infer a bucket-aligned value if
    # the first value timestamp doesn't align exactly with the first bucket timestamp. Dotcom
    # already aligns from/to timestamp to the bucket day boundary, so this should be unnecessary,
    # but leaving it for completeness.
    #
    # Original docstring:
    #
    # Private: Determine the first bucket value aligned to the data. A user may
    # request, for example, "-2w" worth of data, but 2 weeks ago aligned to
    # the current time will likely not align to a bucket interval.
    def first_bucket_value
      x = (@from.to_i / BUCKET_SIZE).to_i
      b = (first_bucket % BUCKET_SIZE)

      # Typical linear equation, y = mx + b
      # m is the slope (in our case, interval)
      BUCKET_SIZE * x + b
    end
  end
end
