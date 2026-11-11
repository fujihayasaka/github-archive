# typed: false
# frozen_string_literal: true

##
# A Metric is a single bit of graphable data (like a single line on a line
# chart). This class is essentially a tuple between the MetricQuery,
# (which represents the necessary logic for querying the data) and MetricCounts
# (which are the results). As such, most of the Metric interface is
# delegated to either the query or the counts.
class Metric
  extend Forwardable

  delegate [:name, :display_name, :timespan] => :@query
  delegate [:count, :max, :total] => :counts

  def self.build(name, **params)
    new MetricQuery.build(name, **params)
  end

  def initialize(query)
    @query = query
  end

  # Public: MetricCounts for period, truncating any buckets from the future.
  def counts
    @counts ||= @query.cache_get.historical
  end

  # Public: Difference between current period's and previous period's totals
  def total_change
    counts.total_change_from(previous)
  end

  # Public: Percent change since previous period
  def percent_change
    counts.percent_change_from(previous)
  end

  # Public: Percent of given value
  # NaN or Infinity are coerced to 0 (so division by 0 => 0)
  # Used such that a metric can report its own percentage of a metric set.
  def percent_of(other_total)
    p = (total / other_total.to_f * 100)
    p.finite? ? p : 0
  end

  # Public: Metric for previous period
  def previous
    @previous ||= Metric.new(@query.previous)
  end

  def as_json(*)
    {
      display_name: display_name,
      name: name,
      max: max,
      total: total,
      total_change: total_change,
      percent_change: percent_change,
      counts: counts.map { |(k, v)| { date: k.to_i * 1000, count: v } },
    }
  end

  # Internal: force set the counts, bypassing cache
  # Only used by tests right now to avoid the need to prime the cache.
  def reload!
    @counts = @query.call.historical
    self
  end
end
