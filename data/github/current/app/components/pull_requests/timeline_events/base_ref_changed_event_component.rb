# typed: true
# frozen_string_literal: true

module PullRequests::TimelineEvents
  class BaseRefChangedEventComponent < ApplicationComponent
    attr_reader :issue_event, :repository

    def initialize(issue_event:, pull_request:)
      @issue_event = issue_event
      @repository = pull_request.repository
    end

    memoize def previous_ref_name
      issue_event.title_was
    end

    memoize def current_ref_name
      issue_event.title_is
    end
  end
end
