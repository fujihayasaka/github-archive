# typed: true
# frozen_string_literal: true

class TaskList
  attr_reader :record

  # `record` is the resource with the Markdown source text with task list items
  # following this syntax:
  #
  #   - [ ] a task list item
  #   - [ ] another item
  #   - [x] a completed item
  #
  def initialize(record)
    @record = record
  end

  # Public: return the TaskList::Summary for this task list.
  #
  # Returns a TaskList::Summary.
  def summary
    @summary ||= TaskList::Summary.new(record.task_list_items)
  end
end
