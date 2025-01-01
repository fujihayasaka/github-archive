# typed: true
# frozen_string_literal: true

class TaskList
  autoload :CheckItem, "task_list/check_item"
  autoload :RenameItem, "task_list/rename_item"
  autoload :Filter, "task_list/filter"
  autoload :Indent, "task_list/indent"
  autoload :Item, "task_list/item"
  autoload :MoveItem, "task_list/move_item"
  autoload :NodeRange, "task_list/node_range"
  autoload :Summary, "task_list/summary"
  autoload :TaskList, "task_list/task_list"
  autoload :ConvertToBlock, "task_list/convert_to_block"
  autoload :TrackedIssueAnchor, "task_list/tracked_issue_anchor"
end
