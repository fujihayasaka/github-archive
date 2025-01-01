# typed: true
# frozen_string_literal: true

module TasklistBlockCommands
  class ExtractPositionFromUrlTasklist
    BlockIndex = T.type_alias { Integer }
    ItemIndex = T.type_alias { Integer }
    Position = T.type_alias { [BlockIndex, ItemIndex] }

    sig do
      params(
        action: Symbol,
        issue: T.nilable(Issue),
        block_uuid: String,
        item_uuid: T.nilable(String),
        next_item_uuid: T.nilable(String),
        previous_item_uuid: T.nilable(String),
        dependencies: T::Hash[Symbol, T.untyped]
      ).void
    end
    def initialize(action:, issue:, block_uuid:, item_uuid: nil, next_item_uuid: nil, previous_item_uuid: nil, dependencies: {})
      @action = action
      @issue = issue
      @block_uuid = block_uuid
      @item_uuid = item_uuid
      @next_item_uuid = next_item_uuid
      @previous_item_uuid = previous_item_uuid

      @result_class = dependencies[:result_class] || TasklistBlockCommands::Result::ExtractPosition
    end

    sig { returns(TasklistBlockCommands::Result::ExtractPosition) }
    def call
      @result_class.new(success: false, action: @action) unless @issue

      case @action
      when :add then build_block_position_result
      when :remove, :convert_to_issue, :update_draft_issue then build_block_and_item_position_result
      when :update_issue_position then build_block_and_update_issue_position_result
      else @result_class.new(success: false, action: @action)
      end
    end

    private

    sig { returns(TasklistBlockCommands::Result::ExtractPosition) }
    def build_block_position_result
      return fail_result unless block_position = fetch_position_of_block_by_uuid

      @result_class.new(
        success: true,
        action: @action,
        data: block_position,
      )
    end

    sig { returns(TasklistBlockCommands::Result::ExtractPosition) }
    def build_block_and_item_position_result
      return fail_result unless block_position = fetch_position_of_block_by_uuid
      return fail_result unless item_position = fetch_position_of_item_by_uuid(block_position)

      @result_class.new(
        success: true,
        action: @action,
        data: [block_position, item_position],
      )
    end

    sig { returns(TasklistBlockCommands::Result::ExtractPosition) }
    def build_block_and_update_issue_position_result
      return fail_result unless block_position = fetch_position_of_block_by_uuid
      return fail_result unless source_position = fetch_position_of_item_by_uuid(block_position)
      return fail_result unless destination_position = fetch_destination_by_next_and_previous(
        block_position,
        source_position
      )

      # only returns one block position because the old reordering strategy don't support
      # drag-n-drop items across tasklists
      @result_class.new(
        success: true,
        action: @action,
        data: [block_position, source_position, destination_position],
      )
    end

    sig { returns(T.nilable(BlockIndex)) }
    def fetch_position_of_block_by_uuid
      tasklist_blocks.find_index do |tracking|
        tracking.key.primary_key&.uuid == @block_uuid
      end
    end

    sig { params(block_position: BlockIndex).returns(T.nilable(ItemIndex)) }
    def fetch_position_of_item_by_uuid(block_position)
      return unless block = tasklist_blocks[block_position]

      block.items.find_index { |item| item.uuid == @item_uuid }
    end

    sig do
      params(
        block_position: BlockIndex,
        source_position: ItemIndex,
      ).returns(T.nilable(ItemIndex))
    end
    def fetch_destination_by_next_and_previous(block_position, source_position)
      return unless block = tasklist_blocks[block_position]

      previous_idx = block.items.find_index { |item| item.uuid == @previous_item_uuid }
      next_idx = block.items.find_index { |item| item.uuid == @next_item_uuid }

      return 0 unless previous_idx
      return block.items.length - 1 unless next_idx

      source_position > next_idx ? next_idx : previous_idx
    end

    sig { returns(T::Array[TasklistBlock]) }
    def tasklist_blocks
      @issue&.hierarchy&.tasklist_blocks.presence || []
    end

    def fail_result(message: "")
      @result_class.new(success: false, action: @action, message: message)
    end
  end
end
