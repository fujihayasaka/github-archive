# typed: true
# frozen_string_literal: true

class TaskList
  class TrackedIssueAnchor
    Complete = TaskList::Filter::CompletePattern

    attr_reader :title
    attr_reader :state

    def initialize(state_text, title)
      @state = state_text =~ Complete ? "closed" : "open"
      @title = title
    end
  end
end
