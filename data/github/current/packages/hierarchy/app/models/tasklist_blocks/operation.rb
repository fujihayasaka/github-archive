# typed: true
# frozen_string_literal: true

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
