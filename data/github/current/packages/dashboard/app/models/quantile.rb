# typed: true
# frozen_string_literal: true

class Quantile
  attr_reader :domain, :range

  def initialize(domain:, range:)
    @domain = domain.sort
    @range = range
    @indices = Array(0...range.size)
  end

  def n_quantile(x)
    quantile = thresholds.index { |threshold| x <= threshold }
    @indices[quantile || -1]
  end

  def scale(x)
    @range[n_quantile(x)]
  end

  private

  def thresholds
    @thresholds ||= begin
      q = range.size.to_f
      range.take(range.size - 1).map.with_index do |_, k|
        quantile(domain, (k + 1) / q)
      end
    end
  end

  # R-7 per <http://en.wikipedia.org/wiki/Quantile>
  def quantile(values, p)
    hh = (values.size - 1) * p + 1
    h = hh.floor
    v = values[h - 1]
    e = hh - h
    e ? v + e * (values[h] - v) : v
  end
end
