# typed: true
# frozen_string_literal: true

# Methods related to pollable API endpoints.
#
# For use in APIs that are likely to be polled for new activity data (e.g., the
# events API, the notifications API).
module Api::App::PollIntervalDependency
  PollHeader = "X-Poll-Interval".freeze

  # Public: Set the poll interval header for the response.
  #
  # Returns nothing.
  def set_poll_interval_header!
    @meta[PollHeader] = poll_interval.to_s
  end

  private

  # Internal: Return the interval (in seconds) at which the API encourages users
  # to poll.
  #
  # Override to provide a custom poll interval for a specific resource family.
  #
  # Returns the number of seconds as an Integer.
  def poll_interval
    5.minutes
  end
end
