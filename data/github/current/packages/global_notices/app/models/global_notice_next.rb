# typed: true
# frozen_string_literal: true

# Public: Determines the current global notice to display to the user and
# exposes a basic interface for engineers to manage global notices they want to
# display.
#
# Pending global notices are set by background jobs or user actions
#
# This class manages two different states based on the current viewer:
#
# * the current notice (which notice we show the user)
# * when the current notice was last set or checked
#
# Both of these values are currently stored in the global_notices table
#
# The current notice state is straightforward, it stores which notice we should
# display to the user.
#
# The current notice last set/checked state is used for the following:
#
# When the user views a page, if the last set/checked value is > 12 hours old,
# we enqueue a job that:
#
# * Check if the current notice is still valid
# * If the current notice is not valid check if any other notices are valid
# * If the current notice is valid, update the last set/checked value to now so
#   we can check again in 12 hours.
class GlobalNoticeNext
  def initialize(viewer:)
    @viewer = viewer
  end

  # Public: Fetches the current notice check
  #
  # Returns an instance of a notice check. e.g. DisabledPersonalBillingCheck
  def current_notice
    viewer.global_notice.notice
  end

  # Public: Fetches the current notice name from the global_notices table
  #
  # Returns a symbol
  def current_notice_name
    name = viewer.global_notice.name

    if name.nil? || name == "no_notice"
      nil
    else
      name.to_sym
    end
  end

  def never_been_set?
    !viewer.global_notice.persisted?
  end

  # Public: Sets the current notice to given `notice_name` if no notice is set,
  # or if it has higher priority than the current notice.
  #
  # notice - the name of the notice to set
  # ignore_priority - ignores priority checks and overrides the current notice
  #
  # Returns nothing
  # Raises ArgumentError if notice_name is not in NOTICES_BY_PRIORITY
  def set_notice(notice_name)
    viewer.global_notice.set(notice_name)
  end

  # Public: Refreshes the current notices last checked at, or determines which
  # new notice to show, if any.
  def refresh
    viewer.global_notice.refresh
  end

  private

  attr_reader :viewer
end
