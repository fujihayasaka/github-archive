# typed: true
# frozen_string_literal: true

module PullRequests::TimelineEvents
  class ReadyForReviewComponent < ApplicationComponent
    attr_reader :issue_event

    def initialize(issue_event:)
      @issue_event = issue_event
    end
  end
end
