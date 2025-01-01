# typed: true
# frozen_string_literal: true
class MetricCounts
  include Enumerable # iterates in order by bucket start time
  extend Forwardable

  def self.from_json(json)
    new(JSON.parse(json))
  end

  def initialize(counts_hash = {}, buckets = [])
    zeroed = buckets.product([0]).to_h.stringify_keys
    @hash = zeroed.merge(counts_hash.to_h.stringify_keys).sort.to_h
  end

  def each(&block)
    @hash.each(&block)
  end

  def ==(other)
    @hash == other.to_h
  end

  def total
    @total ||= @hash.values.sum
  end

  def max
    @max ||= @hash.values.max
  end

  # Public: Difference between current total and previous' total
  def total_change_from(previous)
    total - previous.total
  end

  # Public: Percent change since previous period
  def percent_change_from(previous)
    previous_total = previous.total == 0 ? 1 : previous.total

    (total_change_from(previous) / previous_total.to_f * 100).to_i
  end

  def historical(time = Time.current)
    self.class.new @hash.take_while { |k, _| k.to_i < time.to_i }
  end

  private

  # Calculates a running subtotal for each key.
  # This makes finding the sum easy;
  # (it's the value of the last item's subtotal)
  # but also means we have the integral values if we need them.
  # Returns the final total
  def calculate_subtotals!(counts)
    counts.reduce(0) do |subtotal, (bucket, count)|
      (subtotal + count).tap do |new_subtotal|
        counts[bucket] = { count: count, subtotal: new_subtotal }
      end
    end
  end
end
