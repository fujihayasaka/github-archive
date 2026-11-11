# typed: true
# frozen_string_literal: true

# Public: Represents a month of time in a user's contribution graph.
class Contribution::CalendarMonth
  attr_reader :first_day, :total_weeks

  # first_day - a Date representing the start of this month
  # total_weeks - how many weeks started in this month; Integer
  def initialize(first_day:, total_weeks:)
    @first_day = first_day
    @total_weeks = total_weeks
  end

  # Public: The name of this month in short format.
  #
  # Returns a String.
  def name
    first_day.strftime("%b")
  end

  def full_name
    first_day.strftime("%B")
  end

  # Public: The year this month occurs in.
  #
  # Returns an Integer.
  def year
    first_day.year
  end

  def platform_type_name
    "ContributionCalendarMonth"
  end
end
