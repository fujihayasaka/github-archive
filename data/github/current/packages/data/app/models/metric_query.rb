# typed: false
# frozen_string_literal: true

##
# Base class for Queries intended for use with Org Metrics.
#
# The class is intended to (mostly) follow the AR Query Object pattern.
# Objects are instantiated with all the parameters necessary for the query,
# so an instance of the query object merely needs to be invoked via "#call"
# to actually trigger the query being made to the DB.
#
# Subclasses must implement the #all method, which should build up the
# AR relation representing the query.
class MetricQuery
  class_attribute :display_name

  attr_reader :timespan

  def self.inherited(subclass)
    # Set the default display_name
    subclass.display_name = subclass.name.demodulize.titleize
  end

  # Lookup method to find the query subclass by name
  # Underscores first so that we can accept underscored or camelized variants.
  # FooBar => Metric::FooBar
  # foo_bar => Metric::FooBar
  def self.[](subclass_name)
    const_get subclass_name.to_s.classify
  end

  # Builder method to instantiate query subclasses by string name
  def self.build(name, **params)
    self[name].new(**params)
  end

  # Shortcut to instantiate and #call in one step
  def self.call(**params)
    new(**params).call
  end

  def self.to_param
    name.demodulize
  end

  # Instances of MetricQuery subclasses are given all the necessary
  # query parameters at initialization
  def initialize(timespan: MetricTimespan::Week.new, **params)
    @params = params
    @timespan = timespan
  end

  # Must be implemented by subclasses and return the AR relation for the query
  # def all; end

  # Invoke the query against the db and return the results as MetricCounts
  def call
    GitHub.dogstats.time("metric_query", tags: ["name:#{name}", "period:#{timespan.period}"]) do
      MetricCounts.new(all, timespan.buckets)
    end
  end

  def name
    self.class.name.demodulize.underscore
  end

  # Return the same MetricQuery type, but from one timespan prior
  def previous
    self.class.new timespan: timespan.previous, **@params
  end

  def cache_get
    if FeatureFlag.vexi.enabled_or_raise?(:metric_query_kv) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
      GitHub.logger.info("metric_query_kv cache_get")
      return nil
    end

    GitHub.kv.get(cache_key). # rubocop:todo GitHub/DoNotUseGlobalKv
      map(&MetricCounts.method(:from_json)).
      tap do |val|
        GitHub.dogstats.increment "metric_query",
          tags: ["name:#{name}", "period:#{timespan.period}", "cache:#{val.ok? ? "hit" : "miss"}"]
      end.rescue do
        GitHub::Result.new do
          CollectMetricsJob.perform_later(@params)
          MetricCounts.new
        end
      end.
      value!
  end

  def cache_put
    if FeatureFlag.vexi.enabled_or_raise?(:metric_query_kv) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
      GitHub.logger.info("metric_query_kv cache_put")
      return
    end

    call.tap do |counts|
      ActiveRecord::Base.connected_to(role: :writing) do
        GitHub.kv.set(cache_key, counts.to_json, expires: cache_expiry) # rubocop:todo GitHub/DoNotUseGlobalKv
      end
    end
  end

  def inspect
    {
      name: name,
      owner: @params[:owner_id] || "instance",
      timespan: timespan.to_s,
    }
  end

  private

  def cache_key
    "owner:#{inspect.slice(:owner, :name, :timespan).values.join('.')}"
  end

  def cache_expiry
    timespan.next.to_range.end
  end
end
