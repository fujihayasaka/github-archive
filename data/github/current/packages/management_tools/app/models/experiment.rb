# typed: true
# frozen_string_literal: true

# A science experiment.
#
# Minute-by-minute data is retrieved from Datadog since the science metrics
# are already stored there. Hour-by-hour "was there an error at all?" flags
# are kept in memcached instead since it's faster to retrieve them that way.
class Experiment < ApplicationRecord::Domain::Experiments
  # Public: Reasonable experiment percentages.
  PERCENTAGES = [0, 1, 2, 4, 10, 25, 50, 75, 100]

  # Internal: The amount of time before a cached percentage expires.
  TTL = T_5_MINUTES

  # Public: The number of weeks to warn of experiment running for too long
  RUNNING_WEEKS_THRESHOLD = 2

  # Public: Experiment name prefix for long running experiments
  LONG_RUNNING_PREFIX = "long_running"

  validates_presence_of   :name
  validates_uniqueness_of :name, case_sensitive: false

  # Name is used in Datadog and MySQL, so keep it clean:
  validates_format_of :name,
    message: "must be lowercase, dashes, underscores, and .'s, graphite-style",
    with: /\A[a-z\-_]+(\.[a-z\-_]+)*\z/

  validates_presence_of   :percent
  validates_inclusion_of  :percent, in: 0..100

  after_save do |e|
    GitHub.dogstats.gauge "science.enabled", e.percent, tags: ["name:#{e.name}"]
    GitHub.dogstats.event(
      "Experiment adjusted: #{e.name} at #{e.percent}%",
      "Experiment #{e.name} adjusted to #{e.percent}% of requests",
      tags: ["experiment:#{e.name}",
             "enabled:#{e.percent > 0 ? "true" : "false"}"])
  end
  after_update :publish_percentage_changed, if: :percent_previously_changed?

  # Clean up when an Experiment is destroyed.
  # Note: this does not clear the associated Datadog metrics. To do so
  # manually, use /carbon purge github.science.<name>
  after_destroy do |experiment|
    ScienceEvent.clear(experiment.name)
  end

  # Public: Get an Experiment by name or initialize a new, unsaved Experiment.
  def self.[](name)
    ExperimentCache.fetch(name) { where(name: name).first_or_initialize(name: name) }
  end

  # Public: Clear out the mismatches for all experiments.
  def self.clear_all
    all.each &:clear
    nil
  end

  # Internal: The percentage cache key for this Experiment name. The name is
  # hashed to avoid weird characters and key length issues.
  def self.key(name, *extras)
    ["science:experiment:v1", Digest::SHA256.hexdigest(name), *extras].join ":"
  end

  # Public: Get an Experiment's Integer 0-100 percentage by name.
  def self.percentage(name)
    GitHub.cache.fetch key(name), ttl: TTL do
      ActiveRecord::Base.connected_to(role: :reading) do
        self[name].percent
      end
    end
  end

  # Public: Get an Experiment's sample threshold, if set.
  def self.sample_threshold(name)
    if data = GitHub.cache.get(key(name, "sample"))
      data.first
    end
  end

  # Public: when does a sample run end?
  #
  # Used for UI display ("sampling ends in x seconds")
  #
  # Returns a timestamp, or nil if no sampling is present.
  def self.sample_ends_at(name)
    if data = GitHub.cache.get(key(name, "sample"))
      data.last
    end
  end

  # Public: Is this Experiment's percent greater than zero?
  def active?
    percent > 0
  end

  # Public: Set and save this Experiment's likelihood of running.
  def adjust(percent)
    self.percent = percent
    save!

    self
  end

  # Public: Clear out the mismatches for this experiment.
  def clear
    ScienceEvent.clear(name)
  end

  # Public: Set this Experiment's percent to 0.
  def disable
    adjust 0
  end

  # Public: disable sampling for this Experiment.
  def disable_sampling
    set_sample_threshold nil, nil
  end

  # Public: Is this Experiment's percent 0?
  def inactive?
    !active?
  end

  # Internal: The percentage cache key for this Experiment.
  def key(*extras)
    T.unsafe(self).class.key name, *extras
  end

  # Public: An Array of Hashes of mismatched candidate/control invocations.
  def mismatches(page: 1)
    raw = ScienceEvent.mismatch_page(name: name, page: page)
    raw.map do |m|
      begin
        ActiveSupport::JSON.decode(m)
      rescue MultiJson::ParseError
      end
    end.compact
  end

  def total_mismatches
    ScienceEvent.mismatch_count(name)
  end

  # Public: are there mismatches for this experiment
  #
  # Returns a boolean
  def mismatches?
    total_mismatches.positive?
  end

  # Public: the sampling status for this experiment
  #
  # Returns whether or not this experiment is currently sampling
  def currently_sampling?
    sample_threshold.to_i.positive?
  end

  # Public: the sample threshold for this experiment
  #
  # Returns the threshold if set, nil otherwise.
  def sample_threshold
    self.class.sample_threshold name
  end

  # Public: when does a sample run end?
  #
  # Returns a timestamp, or nil if no sampling is present.
  def sample_ends_at
    self.class.sample_ends_at name
  end

  # Public: An Array of Hashes of sampled experimental results.
  def samples(page: 1)
    raw = ScienceEvent.sample_page(name: name, page: page)
    raw.map { |m| ActiveSupport::JSON.decode m }
  end

  def total_samples
    ScienceEvent.sample_count(name)
  end

  # Public: Set a threshold for collecting samples for this experiment.
  #
  # threshold - Float millisecond threshold: any run where any candidate takes
  #             longer than this will be stored for later analysis.
  #             Pass in nil to disable sampling for this experiment.
  # duration  - Integer, how many seconds to collect data for. Required unless
  #             threshold is nil.
  #
  # Returns nothing.
  def set_sample_threshold(threshold, duration)
    if threshold.nil?
      GitHub.cache.delete key("sample")
    else
      # Just in case:
      raise ArgumentError, "must provide a duration!" unless duration

      ends_at = Time.now + duration
      GitHub.cache.set key("sample"), [threshold, ends_at], duration
    end
  end

  # Public: Does this experiment use one of the standard percentages?
  def standard?
    PERCENTAGES.include? percent
  end

  # Internal: Use this Experiment's name when generating routes.
  def to_param
    name
  end

  def running_too_long?
    active? && !name.starts_with?(LONG_RUNNING_PREFIX) && T.unsafe(updated_at) < RUNNING_WEEKS_THRESHOLD.weeks.ago
  end

  # How often per minute is this experiment running?
  def activity_rate
    rates[0].to_i
  end

  # How often per minute is this experiment mismatching?
  def mismatch_rate
    rates[1].to_i
  end

  def code_usage
    @code_usage ||= GitHub::Grep.new.code_use(
      /science( |\()('|")#{name}/,
      dirs: %w[app config jobs lib packages]
    )
  end

  # Internal: retrieve activity rates for this experiment from datadog
  def rates
    return @rates if defined? @rates
    return @rates = [0, 0] if !active?

    query = %Q(ewma_5(sum:science{experiment:#{name}}.as_count().rollup(sum, 60)),
    ewma_5(sum:science{experiment:#{name},result:mismatch}.as_count().rollup(sum, 60)))
    to   = DateTime.now
    from = to - 5.minutes

    begin
      status, results = GitHub.dogapi.get_points(query, from, to)
    rescue RuntimeError => e
      GitHub.dogstats.increment("dogapi.get_points.errors", tags: ["exception:#{e.class}"])
      return @rates = [0, 0]
    end

    if status != "200"
      GitHub.dogstats.increment("dogapi.get_points.errors", tags: ["http_error_status:#{status}"])
      return @rates = [0, 0]
    end
    return @rates = [0, 0] if results.blank? || results["series"].nil?

    series = results["series"]
    total_series = series.find { |s| s["scope"] == "experiment:#{name}" }
    mismatch_series = series.find { |s| s["scope"] == "experiment:#{name},result:mismatch" }

    _, total_rate = total_series ? total_series["pointlist"].last : [nil, 0]
    _, mismatch_rate = mismatch_series ? mismatch_series["pointlist"].last : [nil, 0]
    @rates = [total_rate, mismatch_rate]
  end

  def self.viewer_can_read?(viewer)
    return false unless GitHub.experiments_graphql_enabled?
    return false unless viewer
    viewer.github_developer? || viewer.site_admin?
  end

  def self.async_viewer_can_read?(viewer)
    Promise.resolve(viewer_can_read?(viewer))
  end

  def async_viewer_can_read?(viewer)
    self.class.async_viewer_can_read?(viewer)
  end

  def global_id
    name
  end

  private

  def publish_percentage_changed
    return unless GitHub.publish_events_to_delorean?
    return if GitHub.flipper[:disable_delorean_publishing].enabled?

    actor = GitHub.context[:actor] || "Someone"

    GitHub.delorean_client.publish_event(
      timeline_id: 1, # TODO: replace with the correct timeline id
      type: "science_experiment",
      operation: operation,
      title: "Science experiment '#{name}' #{operation} to #{percent}%",
      description: "#{actor} #{operation} the '#{name}' science experiment " \
                   "to #{percent}% (was #{percent_previously_was}%)",
      occurred_at: Time.current,
      actions: {
        "Devtools": "https://admin.github.com/devtools/experiments/#{name}",
      },
      group_key: "science_experiment_#{name}",
    )
  rescue => e # rubocop:todo Lint/GenericRescue
    # If Delorean is down or our client code has an issue, we don't want to affect experiment operations
    Failbot.report(e)
    GitHub.dogstats.increment("experiment.publish_delorean_event.failure")
  end

  def operation
    if percent_previously_was == 0 && percent > 0
      "enabled"
    elsif T.unsafe(percent_previously_was) > 0 && percent == 0
      "disabled"
    elsif T.unsafe(percent_previously_was) < percent
      "increased"
    else
      "decreased"
    end
  end
end
