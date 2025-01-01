# typed: true
# frozen_string_literal: true

# Public: Represents a week of time in a user's contribution graph.
class Contribution::CalendarWeek
  attr_reader :contribution_days

  # contribution_days - an Array of Contribution::CalendarDay instances for the days in this week
  def initialize(contribution_days)
    @contribution_days = contribution_days
  end

  def first_day
    contribution_days.first&.date
  end

  def platform_type_name
    "ContributionCalendarWeek"
  end
end
