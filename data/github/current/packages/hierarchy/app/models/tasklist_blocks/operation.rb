# typed: true
# frozen_string_literal: true

require_relative "./operations/append_item"
require_relative "./operations/remove_item"
require_relative "./operations/remove_tasklist_block"
require_relative "./operations/add_tasklist_block"
require_relative "./operations/update_item_position"
require_relative "./operations/convert_to_issue"
require_relative "./operations/update_tasklist_title"

module TasklistBlocks
  module Operation
    sig do
      params(payload: T.nilable(String), current_user: T.nilable(User), current_repository: T.nilable(Repository))
        .returns(
          T.nilable(
            T.any(
              TasklistBlocks::Operations::AppendItem,
              TasklistBlocks::Operations::UpdateItemTitle,
              TasklistBlocks::Operations::UpdateItemState,
              TasklistBlocks::Operations::RemoveItem,
              TasklistBlocks::Operations::RemoveTasklistBlock,
              TasklistBlocks::Operations::AddTasklistBlock,
              TasklistBlocks::Operations::UpdateItemPosition,
              TasklistBlocks::Operations::ConvertToIssue,
              TasklistBlocks::Operations::UpdateTasklistTitle
            )
          )
        )
    end
    def self.from(payload, current_user: nil, current_repository: nil)
      return unless payload.present?
      parsed = JSON.parse(payload)

      case parsed["operation"]
      when "append_item"
        TasklistBlocks::Operations::AppendItem.new(position: parsed["position"], value: parsed["value"])
      when "update_item_title"
        TasklistBlocks::Operations::UpdateItemTitle.new(position: parsed["position"], value: parsed["value"])
      when "update_item_state"
        TasklistBlocks::Operations::UpdateItemState.new(position: parsed["position"], closed: parsed["closed"])
      when "remove_item"
        TasklistBlocks::Operations::RemoveItem.new(position: parsed["position"])
      when "remove_tasklist_block"
        TasklistBlocks::Operations::RemoveTasklistBlock.new(position: parsed["position"])
      when "add_tasklist_block"
        TasklistBlocks::Operations::AddTasklistBlock.new
      when "update_item_position"
        TasklistBlocks::Operations::UpdateItemPosition.new(
          src: parsed["src"],
          dst: parsed["dst"]
        )
      when "convert_to_issue"
        return nil unless current_user && current_repository

        TasklistBlocks::Operations::ConvertToIssue.new(
          position: parsed["position"],
          issue_builder: ::Issue::Builder.new(current_user, current_repository)
        )
      when "update_tasklist_title"
        TasklistBlocks::Operations::UpdateTasklistTitle.new(position: parsed["position"], name: parsed["name"])
      else
        nil
      end
    rescue JSON::ParserError
      nil
    end
  end
end
