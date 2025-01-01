# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class TaskListItemStatus < Platform::Enums::Base
      mobile_only true
      description "The possible task list item statuses, according to its checkbox."

      value "COMPLETE", "Task list item's checkbox is checked", value: :complete
      value "INCOMPLETE", "Task list item's checkbox is unchecked", value: :incomplete
    end
  end
end
