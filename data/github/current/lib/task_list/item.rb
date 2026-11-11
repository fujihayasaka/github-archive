# typed: true
# frozen_string_literal: true

class TaskList
  class Item
    Complete = TaskList::Filter::CompletePattern

    attr_reader :checkbox_text
    attr_accessor :permalink

    def initialize(checkbox_text)
      @checkbox_text = checkbox_text
    end

    def complete?
      checkbox_text =~ Complete
    end
  end
end
