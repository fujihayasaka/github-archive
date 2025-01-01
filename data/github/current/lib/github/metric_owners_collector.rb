# typed: true
# frozen_string_literal: true

class MetricOwnersCollector
  def self.instance
    @instance ||= new
  end

  attr_reader :metrics_emitted

  def initialize
    @metrics_emitted = {}
  end

  def self.add_metric(metric_name)
    return if GitHub.enterprise?
    instance.add_metric(metric_name)
  end

  def add_metric(metric_name)
    return if metric_name.empty?
    return if @metrics_emitted.key?(metric_name)

    finder = MetricAttributionServiceFinder.new(caller)
    service_catalog = finder.service_owner || "unknown"

    # Fix formatting of metric names as they appear in DD
    metric_name = metric_name.to_s.gsub(/[\/#:]/, "_").gsub("'", "")

    @metrics_emitted[metric_name] = {
      line: finder.path,
      catalog_service: service_catalog
    }
  end

  def self.stop_tracking_metrics
    # prints the metrics to a file, empties the hash

    return if @instance.metrics_emitted.empty?

    file_name = "metrics_tracking.out"

    # if ARTIFACTS_DIR is set use that, otherwise use tmp
    path = ENV["ARTIFACTS_DIR"]
    path = Rails.root.join("tmp") unless path && File.directory?(path)

    output_file = File.join(path, file_name)
    File.open(output_file, "a") do |f|
      f.flock(File::LOCK_EX)
      instance.metrics_emitted.each do |metric, val|
        f.puts "#{metric},#{val[:catalog_service]},#{val[:line]}"
      end
    end

    # empty the hash
    @metrics_emitted = {}
  end
end

# TODO: consolidate with CauseCatalogServiceFinder
class MetricAttributionServiceFinder
  APPLICATION_CODE_ROOT_REGEX = /\A(?:\.\/)?(?:app|config|lib|packages|\(\w*\))/ # Do not include test or vendor files
  RAILS_ROOT_FILTER_REGEX = /^#{ENV["RAILS_ROOT"]}\//
  PATH_REGEX = /(?<path>.*):\d+:.*/
  PATH_AND_LINE_REGEX = /(?<path>.*:\d+):.*/
  IGNORED_PATHS = Regexp.union([
    %r{lib/github/null_dogstatsd.rb},
    %r{lib/github/memory_dogstats_d.rb},
    %r{lib/github/metric_owners_collector.rb},
  ])

  def initialize(backtrace)
    @backtrace = backtrace
  end

  def service_owner
    return nil if GitHub.serviceowners.nil?
    return nil if @backtrace.nil?
    return nil if relevant_backtrace_line.blank?

    if matches = relevant_backtrace_line.match(PATH_REGEX)
      service = catalog_service_for_path(matches[:path])
      return service if !service.blank?
      "no service"
    else
      "no backtrace"
    end
  end

  def path
    @_path ||= relevant_backtrace_line&.match(PATH_AND_LINE_REGEX)&.[](:path) || ""
  end

  def self.backtrace_cleaner
    @_cleaner ||= ActiveSupport::BacktraceCleaner.new.tap do |cleaner|
      cleaner.remove_silencers!
      cleaner.add_filter { |line| line.gsub(RAILS_ROOT_FILTER_REGEX, "") }
      cleaner.add_silencer { |line| !APPLICATION_CODE_ROOT_REGEX.match?(line) }
      cleaner.add_silencer { |line| line.match?(IGNORED_PATHS) }
    end
  end

  private

  def relevant_backtrace_line
    @_relevant_backtrace_line ||=
      self.class.backtrace_cleaner.clean(@backtrace)[0] ||
      "no backtrace cleaned"# self.class.backtrace_cleaner.clean(@backtrace, :noise).first # fallback to first line of backtrace
  end

  def catalog_service_for_path(path)
    owner = GitHub.serviceowners.service_for_path(path, prefix: true)
  end
end
