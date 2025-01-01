# typed: true
# frozen_string_literal: true

# Generates a static contribution calendar, with the green squares spelling
# out "Awesome !!!", for a brand new user who hasn't made any contributions yet.
class Contribution::CalendarSample
  # Spells "Awesome !!!"
  DATA = [
    0,
    0, 0, 0, 0, 0, 0, 0,
    1, 0, 0, 2, 0, 1, 0,
    0, 1, 0, 2, 0, 0, 1,
    0, 9, 6, 9, 6, 6, 0,
    0, 9, 1, 6, 0, 2, 0,
    0, 9, 0, 6, 0, 0, 0,
    0, 9, 6, 9, 7, 6, 1,
    2, 0, 0, 0, 1, 0, 0,
    0, 9, 9, 6, 6, 0, 0,
    1, 0, 2, 2, 0, 9, 0,
    0, 1, 0, 0, 0, 9, 0,
    0, 6, 9, 9, 6, 0, 1,
    0, 1, 1, 0, 2, 9, 0,
    1, 0, 0, 1, 0, 6, 1,
    0, 9, 6, 9, 9, 0, 0,
    2, 0, 2, 0, 0, 0, 1,
    0, 9, 9, 6, 9, 6, 2,
    1, 9, 0, 9, 1, 7, 0,
    0, 9, 2, 6, 0, 9, 0,
    1, 9, 0, 6, 0, 7, 0,
    0, 0, 1, 0, 2, 0, 0,
    0, 2, 6, 1, 2, 9, 2,
    0, 9, 0, 6, 0, 9, 0,
    0, 9, 1, 9, 0, 9, 0,
    1, 9, 2, 6, 0, 9, 0,
    2, 8, 2, 0, 9, 0, 1,
    0, 2, 0, 0, 0, 1, 1,
    0, 0, 6, 9, 6, 0, 0,
    2, 9, 0, 1, 0, 9, 0,
    0, 6, 0, 1, 0, 9, 0,
    0, 0, 9, 9, 6, 2, 1,
    2, 0, 1, 2, 0, 0, 0,
    0, 6, 9, 9, 9, 6, 0,
    0, 9, 0, 1, 0, 0, 2,
    1, 9, 1, 0, 0, 2, 1,
    0, 0, 9, 9, 6, 9, 0,
    0, 9, 0, 2, 1, 0, 1,
    1, 9, 2, 0, 0, 1, 0,
    0, 1, 9, 9, 6, 9, 0,
    2, 0, 1, 0, 0, 1, 0,
    0, 9, 9, 9, 9, 9, 2,
    0, 6, 0, 7, 0, 9, 0,
    2, 9, 0, 9, 2, 9, 0,
    0, 9, 1, 6, 0, 9, 2,
    0, 0, 0, 0, 1, 0, 2,
    0, 9, 9, 6, 2, 9, 0,
    1, 0, 0, 0, 1, 1, 0,
    0, 9, 9, 6, 0, 9, 0,
    0, 0, 1, 0, 0, 0, 1,
    2, 6, 6, 9, 0, 9, 2,
    1, 2, 1, 2, 2, 0, 0,
    0, 0, 1, 1, 1, 1, 1,
    0
  ].freeze

  # Mimics Contribution::Calendar#days but returns static sample data.
  #
  # Returns an Array of [[day, count],...].
  def days
    data = DATA.rotate(Time.new.wday)
    year_ago = 1.year.ago - 1.day
    data.map.with_index do |count, ix|
      time = year_ago + (ix + 1).days
      [time.to_date, count]
    end
  end

  def weeks
    ::Contribution::Calendar.weeks_from(days, quantile: quantile)
  end

  def months
    ::Contribution::Calendar.months_from(weeks)
  end

  def days_of_week
    ::Contribution::Calendar.days_of_week_from(weeks)
  end

  # Public: Returns a Quantile for the days in this calendar using the default range of colors
  # for the contribution graph.
  def quantile
    outliers = OutlierFilter.new
    counts = days.map { |pair| pair[1] }
    counts = outliers.filter(counts)
    Quantile.new(domain: [0, counts.max], range: Contribution::Calendar::DEFAULT_COLORS)
  end

  def platform_type_name
    "ContributionCalendar"
  end
end
