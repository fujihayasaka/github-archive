# typed: true
# frozen_string_literal: true

class MetricSet
  include Enumerable
  extend Forwardable

  def self.build(names = [], **params)
    new(Array(names).map { |name| Metric.build(name, **params) })
  end

  def initialize(metrics)
    @metrics = metrics
  end

  def each(&block)
    @metrics.each(&block)
  end

  # Public: MetricSet for the previous period
  def previous
    @previous ||= MetricSet.new(@metrics.map(&:previous))
  end

  # Public: The total of all metrics in the set
  def total
    @total ||= @metrics.map(&:total).sum
  end

  # Public: A Hash of metrics, indexed by their name
  # Accepts a block to transform the metrics, if necessary
  def by_name(&blk)
    @metrics.index_by(&:name).transform_values(&(blk || :itself))
  end

  # Public: A Hash of metrics, indexed by their display_name
  # Accepts a block to transform the metrics, if necessary
  def by_display_name(&blk)
    @metrics.index_by(&:display_name).transform_values(&(blk || :itself))
  end

  # Public: Calculate each metric's percentage of the total set,
  # using Largest Remainder method.
  # Accepts a block to first transform the metrics into a hash.
  def percentages(&indexed_by)
    # for each metric, calculate the percentage of the total set
    # sort (descending) by the percentage fraction
    # distribute the remainder (as integers), across
    metrics = indexed_by.call(self) { |m| m.percent_of(total) }

    return metrics if metrics.values.all?(&:zero?)

    metrics = metrics
      .sort_by { |(_k, v)| v % 1 }
      .reverse

    remainder = 100 - metrics.sum { |(_k, v)| v.to_i }

    metrics.zip(Array.new(remainder, 1))
      .map { |((k, v), r)| [k, v.to_i + r.to_i] }
      .to_h
  end

  def as_json(*)
    @as_json ||= {
      timespan: @metrics.first.timespan,
      metrics: @metrics,
    }
  end
end
