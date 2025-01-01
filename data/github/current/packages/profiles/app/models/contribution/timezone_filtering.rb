# typed: false
# frozen_string_literal: true

class Contribution
  module TimezoneFiltering
    TIMEZONE_BUFFER = 1.day
    UnnecessaryTimeBuffering = Class.new(StandardError)

    private

    # Private: Some contribution types (CreatedPullRequest, CreatedIssue)
    # are filtered and ordered by a computed, timezone aware value.
    # We fetch these by created_at and then filter the
    # returned records by the computed field.
    #
    # This adds a buffer to the beginning and end of the time range so we get
    # all records that may match the time range considering timezone.
    #
    # date_range - A Range of Dates
    #
    # Returns a Range of Time objects.
    def buffered_time_range(date_range)
      # Adding a time buffer only makes sense if we will post-process the
      # records by filtering out the extra data via occurred_at.
      unless needs_filtering_by_occurred_at?
        raise UnnecessaryTimeBuffering.new("Contribution classes must support filtering by occurred_at in order to use buffered time ranges")
      end

      from = date_range.begin - TIMEZONE_BUFFER
      to = date_range.end + TIMEZONE_BUFFER

      from.beginning_of_day..to.end_of_day
    end

    def date_range_to_time_range(date_range)
      date_range.begin.beginning_of_day..date_range.end.end_of_day
    end
  end
end
