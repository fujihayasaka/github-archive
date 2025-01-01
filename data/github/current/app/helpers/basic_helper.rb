# typed: false
# frozen_string_literal: true

# Basic view helpers, not dependent on any models.  This is shared with the
# Event mustache views.
#
# Requires ActionView::Helpers::TagHelper
module BasicHelper
  # Return the time formatted as a String: 2012-06-12 13:21:52.
  def timestamp(time)
    time.in_time_zone(Time.zone).strftime("%Y-%m-%d %H:%M:%S")
  end

  # Public: Format the given time with the full month name, e.g., May 25, 2016.
  #
  # time - a Time or DateTime
  # omit_current_year - set to true when you want to not include the year when the given time
  #                     is in the current year; defaults to false
  #
  # Returns a String.
  def full_month_date(time, omit_current_year: false)
    viewer_time = time.in_time_zone
    format = if omit_current_year && viewer_time.year == Time.zone.now.year
      "%b %-d"
    else
      "%b %-d, %Y"
    end
    viewer_time.strftime(format)
  end

  def time_ago_in_words_js(time, class_name = nil)
    content_tag :"relative-time", full_month_date(time),
      datetime: time.utc.iso8601,
      class: ["no-wrap", class_name].compact.join(" ")
  end

  def date_with_time_tooltip(time, format: "%Y-%m-%d")
    content_tag :time, time.strftime(format), title: timestamp(time), class: "no-wrap"
  end
end
