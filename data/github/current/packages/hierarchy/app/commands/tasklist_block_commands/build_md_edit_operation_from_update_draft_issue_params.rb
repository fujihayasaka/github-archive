# typed: true
# frozen_string_literal: true

module TasklistBlockCommands
  class BuildMdEditOperationFromUpdateDraftIssueParams
    extend T::Sig

    BlockIndex = T.type_alias { Integer }
    ItemIndex = T.type_alias { Integer }
    Position = T.type_alias { [BlockIndex, ItemIndex] }

    sig do
      params(
        issue: T.nilable(Issue),
        block_uuid: String,
        item_uuid: T.nilable(String),
        position_data: T.nilable(Position),
        title: T.nilable(String),
        closed: T.nilable(String),
        dependencies: T::Hash[Symbol, T.untyped]
      ).void
    end
    def initialize(issue:, block_uuid:, item_uuid:, position_data:, title:, closed:, dependencies: {})
      @issue = issue
      @block_uuid = block_uuid
      @item_uuid = item_uuid
      @position_data = position_data
      @title = title
      @closed = closed

      @result_class = dependencies[:result_class] || TasklistBlockCommands::Result::CommandResult
      @update_title_operation_class = dependencies[:update_title_operation_class] || TasklistBlocks::Operations::UpdateItemTitle
      @update_state_operation_class = dependencies[:update_state_operation_class] || TasklistBlocks::Operations::UpdateItemState
    end

    sig { returns(TasklistBlockCommands::Result::CommandResult) }
    def call
      return fail_result unless @issue
      return fail_result unless tracking_block = fetch_tracking_block
      return fail_result unless draft_issue = fetch_draft_issue(tracking_block)
      return fail_result unless draft_issue?(draft_issue)

      update_item_title_operation = maybe_create_update_title_operation(draft_issue)
      return success_result(command: update_item_title_operation) if update_item_title_operation

      update_item_state_operation = maybe_create_update_state_operation(draft_issue)
      return success_result(command: update_item_state_operation) if update_item_state_operation

      fail_result(message: "No updates required")
    end

    private

    sig { params(draft_issue: TasklistBlocks::Issue).returns(T.nilable(TasklistBlocks::Operations::UpdateItemTitle)) }
    def maybe_create_update_title_operation(draft_issue)
      return if @title == draft_issue.title

      @update_title_operation_class.new(position: @position_data, value: @title)
    end

    sig { params(draft_issue: TasklistBlocks::Issue).returns(T.nilable(TasklistBlocks::Operations::UpdateItemState)) }
    def maybe_create_update_state_operation(draft_issue)
      return unless draft_issue_state_changed?(draft_issue)

      @update_state_operation_class.new(position: @position_data, closed: @closed == "true")
    end

    sig { returns(T.nilable(TasklistBlock)) }
    def fetch_tracking_block
      tasklist_blocks.find do |block|
        block.key.primary_key&.uuid == @block_uuid
      end
    end

    sig { params(tracking_block: TasklistBlock).returns(T.nilable(TasklistBlocks::Issue)) }
    def fetch_draft_issue(tracking_block)
      tracking_block.items.find { |item| item.uuid == @item_uuid }
    end

    sig { returns(T::Array[TasklistBlock]) }
    def tasklist_blocks
      @issue&.hierarchy&.tasklist_blocks.presence || []
    end

    sig { params(draft_issue_candidate: TasklistBlocks::Issue).returns(T::Boolean) }
    def draft_issue?(draft_issue_candidate)
      is_draft_item_type = T.let(draft_issue_candidate.item_type.nil? || @item_type == :UNDEFINED || draft_issue_candidate.item_type == TrackingBlocks::DraftIssue::ITEM_TYPE.to_sym, T::Boolean)
      is_draft_state = [TasklistBlocks::DraftIssueState::OPEN, TasklistBlocks::DraftIssueState::CLOSED].include?(draft_issue_candidate.state)
      is_draft_item_type && is_draft_state
    end

    sig { params(draft_issue: TasklistBlocks::Issue).returns(T::Boolean) }
    def draft_issue_state_changed?(draft_issue)
      (@closed == "true" && draft_issue.state != TasklistBlocks::DraftIssueState::CLOSED) ||
        (@closed == "false" && draft_issue.state != TasklistBlocks::DraftIssueState::OPEN)
    end

    def fail_result(message: "")
      @result_class.new(success: false, message: message)
    end

    def success_result(command:)
      @result_class.new(success: true, command: command)
    end
  end
end
