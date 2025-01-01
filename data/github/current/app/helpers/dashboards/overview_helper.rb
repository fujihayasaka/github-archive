# typed: true
# frozen_string_literal: true

module Dashboards
  module OverviewHelper
    def previous_time_period_in_words(period = "week", time = Time.now)
      previous_time = case period
      when "week"  then time - 1.week
      when "month" then time - 1.month
      when "year"  then time - 1.year
      end
      time_period_in_words(period, previous_time)
    end

    def time_period_in_words(period = "week", time = Time.now)
      case period
      when "week"
        beginning = time.beginning_of_week
        "the #{period} of #{beginning.strftime("%B #{beginning.day.ordinalize}, %Y")}"
      when "month"
        beginning = time.beginning_of_month
        "the #{period} of #{beginning.strftime("%B, %Y")}"
      when "year"
        beginning = time.beginning_of_year
        "the #{period} #{beginning.strftime("%Y")}"
      end
    end
  end
end
