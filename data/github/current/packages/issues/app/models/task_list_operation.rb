# typed: true
# frozen_string_literal: true

class TaskListOperation
  # Builds an operation to be performed on task list Markdown text based on
  # the payload data from the request.
  #
  # payload - A JSON string from the browser.
  #
  # Returns nil if no operation is defined in the payload.
  def self.from(payload)
    return unless payload.present?
    parsed = JSON.parse(payload)

    case parsed["operation"]
    when "check"
      TaskList::CheckItem.new(position: parsed["position"], checked: !!parsed["checked"])
    when "move"
      TaskList::MoveItem.new(source: parsed["src"], dest: parsed["dst"])
    when "convert_to_block"
      TaskList::ConvertToBlock.new(position: parsed["position"])
    else
      nil
    end
  rescue JSON::ParserError
    nil
  end
end
