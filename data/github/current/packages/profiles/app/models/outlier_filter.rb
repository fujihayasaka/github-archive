# typed: true
# frozen_string_literal: true

class OutlierFilter
  CRITICAL_VALUE = 3.77972616981

  # Detecting outliers with Grubbs' test.
  #
  #   http://graphpad.com/support/faqid/1598/
  #
  # data - An Array of numbers to filter.
  #
  # Returns an Array of numbers, minus any outliers.
  def filter(data)
    return data if data.empty?

    stdev = stdev(data)
    mean = mean(data)

    # Run the outlier test for a few rounds so we can ignore multiple days with
    # extreme outlying numbers of contributions. If the range or max is small,
    # just run one outlier run, since there won't be an outlier problem.
    max = data.max
    topRange = max - mean
    rounds = (topRange < 6 || max < 15) ? 1 : 3

    rounds.times do
      upperExtreme = data.find do |n|
        p = ((mean - n) / stdev).abs
        p > CRITICAL_VALUE
      end
      if upperExtreme
        data = data.select { |n| n != upperExtreme }
      end
    end

    data
  end

  private

  def mean(data)
    data.sum / data.size.to_f
  end

  def stdev(data)
    Math.sqrt(variance(data))
  end

  def variance(data)
    return 0 if data.size == 1
    mean = mean(data)
    sum = data.sum { |value| (value - mean)**2 }
    sum / (data.size - 1).to_f
  end
end
