# frozen_string_literal: true

# A thin wrapper around statsd for use in enterprise. Since we are not able to
# use tags in GHES, most of these are dropped. Any tags in the ALLOWED_TAG_NAMES
# list are appended to the metric name.
class EnterpriseMetrics
  include Singleton

  ALLOWED_TAG_NAMES = %i(
    code
    consumer
    error_type
    event
    event_source
    handler
    hit
    host
    job
    method
    prefix
    queue
    repo_ids_bucket
    slo_met
    status
    update_type
    warning_type
  ).freeze

  def initialize
    @statsd = Statsd.new(host, port).tap do |statsd|
      statsd.namespace = "dependabot-api"
    end
  end

  %i(count gauge timing).each do |method_name|
    define_method method_name do |stat, v, tags: {}|
      stat = append_allowed_tags_to_metric_name(stat, tags)
      statsd.send(method_name, stat, v)
    end
  end

  def increment(stat, tags: {})
    stat = append_allowed_tags_to_metric_name(stat, tags)
    statsd.increment(stat)
  end

  def time(stat, tags: {}, &block)
    stat = append_allowed_tags_to_metric_name(stat, tags)
    statsd.time(stat, &block)
  end

  def histogram(stat, value, tags: {})
    timing(stat, value, tags: tags)
  end

  def distribution(stat, value, tags: {})
    timing(stat, value, tags: tags)
  end

  def host
    Resolv.getaddress(ENV["STATSD_HOST"] || "127.0.0.1")
  end

  def port
    ENV["STATSD_PORT"]&.to_i || 8125
  end

  def distribution_time(key, tags: {})
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
  ensure
    distribution(key, duration(start), tags: tags)
  end

  def close
    # No-op
  end

  private

  attr_reader :statsd

  def monotonic_time
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def duration(start, ending = nil)
    ending ||= case start
               when Float
                 monotonic_time
               else
                 Time.current
               end

    ((ending - start) * 1_000).round
  end

  def hashify_tags(tags)
    unless tags.instance_of?(Hash)
      begin
        tags = tags.map { |s| s.split(":") }.to_h.transform_keys(&:to_sym)
      rescue ArgumentError
        # malformed tags, return?
        return {}
      end
    end
    tags
  end

  def append_allowed_tags_to_metric_name(stat, tags)
    tags = hashify_tags(tags)

    return stat unless (tags.keys & ALLOWED_TAG_NAMES).any?

    allowed_tags = tags.select { |key, _| ALLOWED_TAG_NAMES.include?(key) }.
                   map { |key, val| "#{key}:#{val}" }.
                   sort
    [stat, *allowed_tags].join(".")
  end
end
