# typed: true
# frozen_string_literal: true

module Stratocaster::Filters
  class WorkflowEventsFilter < BaseFilter
    ALLOWLISTED_LABEL_NAMES = [Labelable::HELP_WANTED_NAME, Labelable::GOOD_FIRST_ISSUE_NAME].freeze

    def initialize(events)
      @events = events
    end

    def self.apply(events, _viewer)
      new(events).apply
    end

    def apply
      @events.
        delete_if(&:workflow_event?).
        delete_if { |event| event.member_event? && !event.has_add_action? }.
        delete_if { |event| event.create_event? && !event.repository_ref_type? }.
        delete_if do |event|
          lowercase_label_name = event.label_name&.downcase
          is_allowlisted_label = if lowercase_label_name
            lowercase_label_name.start_with?(*ALLOWLISTED_LABEL_NAMES)
          end
          event.pull_request_or_issues_event? && !is_allowlisted_label
        end
    end
  end
end
