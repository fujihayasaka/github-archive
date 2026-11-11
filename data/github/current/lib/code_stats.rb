# typed: true
# frozen_string_literal: true

require "json"
require "serviceowners"
require "datadog_api_client"

module CodeStats
  SERVICEOWNERS = Serviceowners::Main.new
  DATADOG_API = DatadogAPIClient::V1::MetricsAPI.new

  CSS_GLOBS = %w[
    app/assets/stylesheets/**/*.{scss,css}
    app/components/**/*.{scss,css}
    packages/**/app/components/**/*.{scss,css}
    ui/packages/**/*.modules.css
  ].freeze

  ERB_GLOBS = %w[
    app/views/**/*.erb
    app/components/**/*.erb
    packages/**/app/components/**/*.erb
  ].freeze

  NON_MONOREPO_JS_GLOBS = %w[
    app/assets/**/*.{ts,tsx,js,jsx,mjs}
    app/components/**/*.{ts,tsx,js,jsx,mjs}
    test/**/*.{ts,tsx,js,jsx,mjs}
    script/**/*.{ts,tsx,js,jsx,mjs}
    lib/**/*.{ts,tsx,js,jsx,mjs}
  ].freeze

  MONOREPO_JS_GLOBS = %w[
    ui/packages/**/*.{ts,tsx,js,jsx,mjs}
  ].freeze

  TSX_GLOBS = %w[
    app/assets/modules/**/*.tsx
    ui/packages/**/*.tsx
  ].freeze

  JS_GLOBS = [
    *NON_MONOREPO_JS_GLOBS,
    *MONOREPO_JS_GLOBS
  ].freeze

  RB_GLOBS = %w[
    app/**/*.rb
    lib/**/*.rb
    jobs/**/*.rb
    config/**/*.rb
    test/**/*.rb
  ].freeze

  COMPONENT_TYPES = {
    "app/models": :model,
    "app/views": :view,
    "app/helpers": :helper,
    "app/view_models": :view_model,
    "app/components": :view_component,
    "app/controllers": :controller,
    "app/mailers": :mailer,
    "app/assets/stylesheets/bundles": :bundles,
    "app/assets/stylesheets/variables": :variables,
    "app/assets/stylesheets/components": :components,
    "app/assets/stylesheets": :stylesheet,
    "app/assets/modules": :javascript,
    "app/assets/types": :javascript,
    "app/api": :api,
    "lib": :lib,
    "jobs": :job,
    "config": :config,
    "db/migrate": :migration,
    "test": :test,
    "ui/packages": :javascript,
  }.freeze

  # Source code represents a file, all metrics and tags associated with it.
  class SourceCode
    attr_reader :path

    # @param path [String] the path to the source code file
    def initialize(path)
      @path = path.start_with?(Dir.pwd) ? path[(Dir.pwd.length + 1)..] : path # Remove current directory
      @values = Hash.new(0)

      # Default tags
      @tags = {
        # A shorter path representation to the file
        path: trim_path,
        # The owner of the file
        catalog_service: serviceowner,
        # A component type
        component: component,
        # Name of repo
        repo: "github/github"
      }
    end

    # Increment the source code value
    #
    # @param tag [Hash] a hash of tags to apply to the metric
    # @param value [Integer] the value to increment the metric by
    def increment(tag: {}, value: 1)
      @values[tag] += value
    end

    def add_tag(key, value)
      @tags[key] = value
    end

    # Get matching lines from the source code
    #
    # @param regex [Regex] a regex to match against the source code
    #
    # returns [Array] an array of matching lines Hash { match, line }
    def matching_lines(regex)
      matched_lines = []

      lines.each do |line|
        line.chomp!
        if !line.empty? && match = line.match(regex)
          matched_lines.push({
            match: match,
            line: line
          })
        end
      end

      matched_lines
    end

    # Compile values and tags into a array of metrics we can send to the DataDog API
    #
    # returns [Array] an array of metric Hash { tags, value }
    def metrics

      # For each metric we incremented
      @values.map do |tag, value|

        # If the tag has values
        if tag.keys.length > 0
          # Add to the default tags
          @tags.merge!(tag)
        end

        # Return hash
        { tags: tag_array, value: value }
      end
    end

    # Convert tags to an array of strings for the API "tag:value" format
    def tag_array
      @tags.map { |k, v| "#{trim_tags(k)}:#{trim_tags(v)}" }
    end

    # Get the service owner for the path
    def serviceowner
      spec = SERVICEOWNERS.spec_for_path(@path)
      if spec.nil? || spec.service.nil?
        "unknown"
      else
        "github/#{T.must(spec.service).name}"
      end
    end

    private

    # Read the file lines and store for later use
    def lines
      @lines ||= File.readlines(@path)
    end

    # Remove problematic characters from the tag value https://docs.datadoghq.com/getting_started/tagging/#defining-tags
    def trim_tags(s)
      s.to_s.downcase.strip.sub(/@/, "")
    end

    # shorten path to the file into taggable format
    def trim_path
      @path.strip
        .sub(/\A\//, "")
        # Remove app/*/ directories
        .sub(/app\/[^\/]+\//, "")
        # Remove compiled css hash from end of file
        .sub(/-[0-9a-z]{8,}\.css$/, ".css")
        # Remove compiled js hash from end of file
        .sub(/-[0-9a-z]{8,}\.js$/, ".js")
    end

    # Define the file as a component based on folder location
    def component
      if found_path = COMPONENT_TYPES.keys.find { |path| @path.start_with?(path.to_s) }
        COMPONENT_TYPES[found_path]
      else
        :other
      end
    end
  end

  # Report is the class that represents the report with source files and a series of metrics.
  class Report
    attr_reader :name, :sources, :series, :timestamp

    # @param name [Symbol] Name of the report to lookup later
    # @param key [String] Datadog metric key name
    def initialize(name:, key: "", &block)
      @name, @key, @block = name, key, block
      @sources = []
      @series = []

      # Get the current timestamp, but round down to nearest hour to avoid overlap with the next hour
      t = Time.now
      @timestamp = (t - t.sec - ((t.min % 60) * 60)).to_i
    end

    # Build the report by running the block and collecting the metrics for each source.
    def build
      # Call the block to build the report
      @block.call(self)

      # Skip building if no sources were found
      return if @sources.empty?

      # For each source compile the metrics and add them to the series
      @sources.each do |source|
        source.metrics.each do |metric|
          gauge(@key, metric.fetch(:value, 0), metric.fetch(:tags, []))
        end
      end
    end

    # Gauge a metric in the series. "Gauge" is a metric type term from the Datadog API.
    # https://docs.datadoghq.com/metrics/types/?tab=gauge#metric-types
    #
    # @param metric [String] The datadog metric name
    # @param value [Integer] The value of the metric
    # @param tags [Array<String>] The tags for the metric in format ["path:primer.scss", "catalog_service:unkown"]
    def gauge(metric, value, tags = [])
      @series << DatadogAPIClient::V1::Series.new({
        metric: metric,
        points: [[@timestamp, value]],
        type: "gauge",
        tags: tags
      })
    end

    # Match sources
    def match_sources(globs, regex, ignore = nil)
      begin
        Dir.glob(globs).each do |path|
          next if File.symlink?(path)

          add_source(path, regex, ignore)
        end
      rescue Errno::ENOENT
        # Gracefully handle missing directories
        # This can happen when globs reference non-existent directories
      end
    end

    # Add a source file to the report sources.
    #
    # @param path [String] The path to the source file
    #
    # returns [SourceCode] The source code object
    def add_source(path, regex = nil, ignore = nil)
      return if ignore&.match?(path)

      path = path.start_with?(Dir.pwd) ? path[(Dir.pwd.length + 1)..] : path # Remove current directory
      # If the source already exists, don't add it again
      if source = @sources.find { |source| source.path == path }
        return source
      end

      source = SourceCode.new(path)
      if regex.nil? || source.matching_lines(regex).any?
        @sources << source
        source
      end
    end

    def metric_key
      @key
    end
  end

  # Reporter is the class that organizes all the Reports and sends the metrics to Datadog
  class Reporter
    REPORTS = []

    # Register a report. Raise an exception if the report already exists.
    #
    # @param args [Hash] The arguments to pass to the report initializer
    # @param block [Proc] The block to call for the report
    def self.register_report(**args, &block)
      if self.report_names.include?(args[:name])
        raise ArgumentError, "Report #{args[:name]} already exists. Please use a different name."
      end

      REPORTS << Report.new(name: args[:name], key: args[:key], &block)
    end

    # Submit a report. Raises an exception if the report doesn't exist.
    # submits the report metrics to datadog, and prints the report to stdout.
    #
    # @param report_name [Symbol] The name of the report
    def self.submit_report(report_name)
      report = get_report(report_name)

      if report.nil?
        raise ArgumentError, "No report exits for #{report_name}. Please use one of the following: #{self.report_names.join(', ')}"
      end

      # Build the report and gather data
      report.build

      # Do nothing if the report doesn't have any data
      return unless report.series.any?

      series_batches = report.series.each_slice(5000).to_a
      series_batches.each_with_index do |series_batch, i|

        puts "Submitting #{series_batch.count} metrics from series #{i + 1} of #{series_batches.count}"
        puts "–" * 80

        # Only send series if the event name is schedule. This allows us to test a change
        # with the push: action event or local cli without polluting the datadog metrics.
        if ENV["GITHUB_EVENT_NAME"] == "schedule"
          begin
            # Submit metrics
            DATADOG_API.submit_metrics(DatadogAPIClient::V1::MetricsPayload.new({ series: series_batch }))
          rescue DatadogAPIClient::APIError => e
            puts "Error when calling MetricsAPI->submit_metrics: #{e}"
          end
        end

        # Print to stdout
        series_batch.each do |gauge|
          tag_string = gauge.tags.empty? ? "" : "[#{gauge.tags.join(', ')}]"

          puts "DOGSTATS: #{gauge.metric} #{tag_string} #{gauge.points.first[1]}|g"
        end
        puts "\n\n"
      end
    end

    # Get a report by name.
    #
    # @param report_name [Symbol] The name of the report
    #
    # returns [Report] The report with the given name
    def self.get_report(report_name)
      REPORTS.find { |report| report.name == report_name }
    end

    # returns [Array] The names of all the reports
    def self.report_names
      REPORTS.map(&:name)
    end
  end
end
