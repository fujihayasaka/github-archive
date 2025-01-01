# typed: true
# frozen_string_literal: true

# Public: Represents a day in a user's contribution graph.
class Contribution::CalendarDay
  attr_reader :date, :count, :color, :level

  # date - a Date
  # count - how many contributions were made on the given date; Integer
  # color - hex color code that indicates via intensity how many contributions were made on this
  #         date compared to other dates; String
  # level - relative amount of contributions, based on the quantile scale of the count, as
  #         compared to other days. Possible values are 0, 1, 2, 3, 4; Integer
  def initialize(date:, count:, color:, level:)
    @date = date
    @count = count
    @color = color
    @level = level
  end

  # Public: Get the integer representing which day of the week this is, e.g., 0 for Sunday.
  #
  # Returns an integer.
  def weekday
    date.wday
  end

  # Public: Determine if this day is a Sunday.
  #
  # Returns a Boolean.
  def sunday?
    weekday == 0
  end

  def platform_type_name
    "ContributionCalendarDay"
  end
end
