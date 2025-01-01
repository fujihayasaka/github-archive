# typed: true
# frozen_string_literal: true

require "commonmarker"

module TasklistBlockCommands
  class RemoveChildFromParent
    include GitHub::Memoizer

    METRIC_NAME = "tasklist_blocks.commands.remove_child_from_parent"
    EMPTY_TASKLIST_BLOCK = "\n```[tasklist]\n```"

    sig do
      params(
        parent: ::Issue,
        child: ::Issue,
        actor: ::User,
        dependencies: T::Hash[Symbol, T.untyped]
      ).void
    end
    def initialize(parent:, child:, actor:, dependencies: {})
      @parent = parent
      @child = child
      @actor = actor

      @remove_item_operation_class = dependencies[:remove_item_operation_class] || TasklistBlocks::Operations::RemoveItem
      @get_items_and_positions_operation_class = dependencies[:get_items_and_positions_operation_class] || TasklistBlocks::Operations::GetItemsAndPositions
      @common_marker = dependencies[:common_marker] || CommonMarker
      @stats = dependencies[:stats] || GitHub.dogstats
      @result_class = dependencies[:result_class] || TasklistBlockCommands::Result
    end

    # Public: remove the child issue URL from the parent issue's tasklist block.
    # If the parent issue does not have a tasklist block, no-op
    #
    # Returns a TasklistBlocks::CommandResult.
    sig { returns(TasklistBlockCommands::Result) }
    def call
      return stat_and_return_result(success: false) if parent_tasklist_blocks.empty?

      items_and_positions = get_items_and_positions.call(safe_parent_issue_body)
      return stat_and_return_result(success: false) unless items_and_positions.length > 0

      found_child = T.let(false, T::Boolean)
      # this nested reduce manipulates the body of the given parent issue, and the result
      # should be that body with all instances of the child issue removed
      # for each block...
      new_body = items_and_positions.reduce(safe_parent_issue_body) do |body, block_items|
        # iterate through the items in the block...
        block_items.reduce(body) do |body_inner, item|
          # skip this item if it doesn't match the child we are intending to remove
          next body_inner unless item.does_match_issue?(@child)
          found_child = true
          # and remove the item if it matches the child we are intending to remove
          remove_operation = @remove_item_operation_class.new(position: item.position)
          body_inner = remove_operation.call(body_inner)
          return stat_and_return_result(success: false) unless body_inner
          body_inner
        end
      end

      return stat_and_return_result(success: false) unless found_child

      result = @parent.update_body(new_body, @actor)
      stat_and_return_result(success: result)
    end

    private

    sig { returns(TasklistBlocks::Operations::GetItemsAndPositions) }
    def get_items_and_positions
      @get_items_and_positions_operation_class.new
    end

    # Private: returns all the tasklist blocks we can parse in the parent issue
    # body.
    #
    # Note we are re-instantiating the operation here but that is very cheap.
    sig { returns(T::Array[CommonMarker::Node]) }
    memoize def parent_tasklist_blocks
      get_items_and_positions
        .tasklist_blocks(@common_marker.render_doc(safe_parent_issue_body.gsub(/\r\n?/, "\n")))
    end

    # Private: guard against nil values for the parent issue body.
    sig { returns(String) }
    def safe_parent_issue_body
      @parent.body || ""
    end

    # Private: stat the result of the command and return the result object.
    sig { params(success: T::Boolean).returns(TasklistBlockCommands::Result) }
    def stat_and_return_result(success:)
      status = success ? "success" : "failure"
      message = success ? "Success" : "Failed to remove child to parent"

      @stats.increment(METRIC_NAME, tags: ["status:#{status}"])

      @result_class.new(
        success: success,
        message: message
      )
    end
  end
end
