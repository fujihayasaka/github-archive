# typed: true
# frozen_string_literal: true

module PullRequests::TimelineEvents
  class AutomaticBaseChangeComponent < ApplicationComponent

    attr_reader :issue_event, :action

    def initialize(issue_event:, action:)
      @issue_event = issue_event
      @action = action
    end

    def badge_bg
      action == :success ? :success_emphasis : :danger_emphasis
    end

    def old_base
      issue_event.title_was
    end

    def new_base
      issue_event.title_is
    end
  end
end
