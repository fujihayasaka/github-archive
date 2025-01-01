# typed: true
# frozen_string_literal: true

require "faraday"

# Read access to our Graphite cluster. WARNING: Our installation is not to be
# considered production ready. Any usage of this library should accept that
# requests will fail.
#
# Example:
#
#  GitHub.graphite.value('github.interactions.signups.total', '-2hour')
#    => 25910.00
#
class Graphite
  class Error < StandardError; end
  class Timeout < Error; end

  FARADAY_TIMEOUT_ERRORS = [
    Faraday::TimeoutError, # wraps most Net timeout errors
    Faraday::ConnectionFailed, # wraps Net::OpenTimeout
  ]

  class Results
    attr_reader :stats

    def initialize(stats)
      @stats = stats
    end

    # Public: Expand target wildcards to non-wildcard target names.
    #
    # Returns an Array of non-wildcard target name Strings.
    def targets
      return [] unless stats
      stats.collect { |r| r["target"] }
    end

    # Public: drop timestamp portion of datapoints in a dataset
    #
    # Returns a Graphite::Results object with all 'datapoints' hashes
    # containing only data items, without timestamps.
    def data_only
      return self unless stats
      data = stats.inject([]) do |results, entry|
        if entry["target"] && entry["datapoints"]
          results << {
            "target" => entry["target"],
            "datapoints" => entry["datapoints"].map(&:first),
          }
        end
        results
      end

      self.class.new data
    end

    # Public: drop nil datapoints from a dataset
    #
    # Returns a Graphite::Results object with all nil data points removed,
    # as well as any associated timestamps.
    def compact_data
      return self unless stats
      data = stats.inject([]) do |results, entry|
        if entry["target"] && entry["datapoints"]
          results << {
            "target" => entry["target"],
            "datapoints" => compact_datapoints(entry["datapoints"]),
          }
        end
        results
      end

      self.class.new data
    end

    # Public: drop nil datapoints from an array
    #
    # datapoints - array of data points or data+timestamp pairs
    #
    # Returns a list of data points (or data+timestamp pairs) with nil
    # data items removed.
    def compact_datapoints(datapoints)
      if datapoints.first.is_a? Array
        # remove data+timestamp pairs for nil data items
        datapoints.select { |point| !point.first.nil? }
      else
        # we only have datapoints left
        datapoints.compact
      end
    end

    # Public: drop all series which have empty data sets
    #
    # Returns a Graphite::Results object with all entries removed which had no
    # data values.
    def compact_keys
      return self unless stats
      data = stats.inject([]) do |results, entry|
        if entry["target"] && entry["datapoints"]
          results << entry unless compact_datapoints(entry["datapoints"]).empty?
        end
        results
      end

      self.class.new data
    end

    # Public: replace datapoints for each series according to a block
    #
    # block - block to apply to datapoints in a dataset
    #
    # Returns a Graphite::Results object with all datapoints entries transformed
    # by the supplied block.
    def apply(&block)
      return self unless stats
      data = stats.inject([]) do |results, entry|
        if entry["target"] && entry["datapoints"]
          results << {
            "target" => entry["target"],
            "datapoints" => Array(yield(entry["datapoints"])),
          }
        end
        results
      end

      self.class.new data
    end

    # Public: clean a dataset by dropping timestamps, removing nil data points,
    # applying a block transformation (as in `#apply` above), and finally
    # removing any targets which no longer had data.
    #
    # block - block to apply to compacted datapoints in a dataset
    #
    # Returns a Graphite::Results object with transformed datapoints
    def summarize(&block)
      data_only.compact_data.apply(&block).compact_keys
    end

    # Public: extract the first and last values for all targets in a dataset
    #
    # Returns an Array of 3-element Arrays, containing a target name String,
    # and the value of the first and last data values for that target.
    def extract_endpoints
      return [] unless stats = data_only.compact_data.stats
      stats.inject([]) do |results, entry|
        results << [entry["target"]] + entry["datapoints"].values_at(0, -1)
      end
    end
  end

  attr_reader :connection

  # Create a new instance to query the Graphite install.
  #
  # url — The URL of a Graphite install, can include port.
  def initialize(url)
    @connection = Faraday.new(url: url) do |faraday|
      faraday.adapter Faraday.default_adapter
      faraday.options[:timeout] = 5
      faraday.options[:open_timeout] = 2
    end
  end

  # Public: Expand target wildcards to non-wildcard target names.
  #
  # target - The String target name, expected to contain wild-cards
  #          (ex: "github.backscatter.count.*")
  # from   - The Strings specifying the graphite start time (default: '-2min')
  #
  # Returns an Array of non-wildcard target name Strings.
  def targets(target, from = "-2min")
    query(target, from).targets
  end

  # Public: Retrieve the first data value from the first target.
  #         This is convenient when working with targets without wildcards.
  #
  # target - The String target name (ex: "github.interactions.signup_count")
  # from   - The Strings specifying the graphite start time (default: '-2min')
  #
  # Returns a Float or nil if no data is found.
  def first_value(target, from = "-2min")
    return nil unless results = query(target, from).extract_endpoints
    return nil if results.empty?
    results.first[1]
  end
  alias_method :value, :first_value

  # Public: Retrieve the last data value from the first target.
  #         This is convenient when working with targets without wildcards.
  #
  # target - The String target name (ex: "github.interactions.signup_count")
  # from   - The Strings specifying the graphite start time (default: '-2min')
  #
  # Returns a Float or nil if no data is found.
  def last_value(target, from = "-2min")
    return nil unless results = query(target, from).extract_endpoints
    return nil if results.empty?
    results.first[2]
  end

  # Public: Extract all targets and their most first values
  #
  # target - The String target name, expected to contain wild-cards
  #          (ex: "github.backscatter.count.*")
  # from   - The Strings specifying the graphite start time (default: '-2min')
  #
  # Returns an array of Hashes mapping non-wildcard target name Strings to their
  # oldest datapoint values
  def first_values(target, from = "-2min")
    return [] unless results = query(target, from).extract_endpoints
    results.inject([]) do |collection, data|
      collection << { data[0] => data[1] }
    end
  end

  # Public: Extract all targets and their most last values
  #
  # target - The String target name, expected to contain wild-cards
  #          (ex: "github.backscatter.count.*")
  # from   - The Strings specifying the graphite start time (default: '-2min')
  #
  # Returns an array of Hashes mapping non-wildcard target name Strings to their
  # most recent datapoint values
  def last_values(target, from = "-2min")
    return [] unless results = query(target, from).extract_endpoints
    results.inject([]) do |collection, data|
      collection << { data[0] => data[2] }
    end
  end

  # Private: Queries the Graphite install and parses the JSON response.
  #
  # target - The String target name (ex: "github.interactions.signup_count")
  # from   - The Strings specifying the graphite start time (default: '-2min')
  #
  # Returns a Hash.
  def query(target, from = "-2min", timeout = 5)
    result = connection.get "/render", format: :json, target: target, from: from do |request|
      request.options.timeout = timeout
    end
    if result.status == 200
      Results.new GitHub::JSON.parse(result.body)
    else
      Results.new(nil)
    end
  rescue *FARADAY_TIMEOUT_ERRORS
    raise Timeout
  end

  # https://graphite.readthedocs.org/en/1.0/url-api.html
  QUERY_PARAMS = %w(
    target
    from until
    format
    graphOnly
    width height
    template
    margin
    bgcolor fgcolor
    fontName fontSize fontBold fontItalic
    yMin yMax
    yMinLeft yMaxLeft
    yMinRight yMaxRight
    colorList
    title
    vtitle
    lineMode lineWidth
    hideLegend hideAxes hideGrid
    minXStep majorGridLineColor minorGridLineColor minorY
    thickness
    min max
    tz
  ).map(&:to_sym)

  def render(options = {})
    # Pluck keys from parameter allowlist
    options = options.symbolize_keys.slice(*QUERY_PARAMS)
    options[:format] = "png"

    result = connection.get "/render", options
    if result.status == 200
      result.body
    else
      ""
    end
  rescue *FARADAY_TIMEOUT_ERRORS
    raise Timeout
  end

  def render_data_uri(options = {})
    blob = render(options)
    base64 = Base64.strict_encode64(blob)
    "data:image/png;base64,#{Rack::Utils.escape(base64)}"
  end
end
