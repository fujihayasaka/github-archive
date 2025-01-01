# typed: true
# frozen_string_literal: true

module Site::EventsDateHelper
  def format_event_date_range(start_date:, end_date:)
    start_date = start_date.is_a?(Date) ? start_date : Date.iso8601(start_date)
    end_date = end_date.is_a?(Date) ? end_date : Date.iso8601(end_date)

    if start_date == end_date
      start_date.strftime("%B %d, %Y")
    elsif start_date.month == end_date.month && start_date.year == end_date.year
      "#{start_date.strftime("%b %-d")} - #{end_date.day}, #{start_date.year}"
    elsif start_date.year == end_date.year
      "#{start_date.strftime("%B")} - #{end_date.strftime("%B %Y")}"
    else
      "#{start_date.strftime("%b %Y")} - #{end_date.strftime("%b %Y")}"
    end
  end
end
