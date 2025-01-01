# typed: true
# frozen_string_literal: true

module Stratocaster::Filters
  # Filters a list of events for org to exclude those which
  # type is not included in the list of events that are displayed in the
  # org_all timeline
  #
  # We fall back to show public org events, when there are not
  # enough events in the org_all timeline to show a page of them.
  # The problem is that the public org events contain a set of events
  # that are not included in the org_all timeline, for instance, starred
  # items.
  #
  # This filter removes those events, to retain only the public events that
  # could also be in the org_all timeline.
  #
  # events - Array of Stratocaster::Event items to filter in place
  class OrgAllEventTypesFilter < BaseFilter

    def self.apply(events, viewer)
      events.delete_if do |event|
        watched?(event)
      end
    end

    def self.watched?(event)
      event.event_type =~ /^Watch/
    end
  end
end
