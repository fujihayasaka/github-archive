# typed: true
# frozen_string_literal: true

require "commonmarker"

module TasklistBlockCommands
  class AppendChildToParent
    include GitHub::Memoizer

    METRIC_NAME = "tasklist_blocks.commands.append_child_to_parent"
    EMPTY_TASKLIST_BLOCK = "\n```[tasklist]\n```"

    sig do
      params(
        parent: ::Issue,
        child: ::Issue,
        actor: ::User,
        position: Integer,
        dependencies: T::Hash[Symbol, T.untyped]
      ).void
    end
    def initialize(parent:, child:, actor:, position: -1, dependencies: {})
      @parent = parent
      @child = child
      @actor = actor
      @position = position

      @append_item_operation_class = dependencies[:append_item_operation_class] || TasklistBlocks::Operations::AppendItem
      @common_marker = dependencies[:common_marker] || CommonMarker
      @stats = dependencies[:stats] || GitHub.dogstats
      @result_class = dependencies[:result_class] || TasklistBlockCommands::Result
    end

    # Public: append the child issue URL to the parent issue's tasklist block.
    # If the parent issue does not have a tasklist block, one will be appended
    # to the parent issue body.
    #
    # Returns a TasklistBlocks::CommandResult.
    sig { returns(TasklistBlockCommands::Result) }
    def call
      new_body = append_item_operation.call(body_with_at_least_one_tasklist_block)
      return stat_and_return_result(success: false) unless new_body

      result = @parent.update_body(new_body, @actor)
      stat_and_return_result(success: result)
    end

    private

    sig { returns(TasklistBlocks::Operations::AppendItem) }
    def append_item_operation
      @append_item_operation_class.new(
        position: T.must(@position),
        value: @child.url,
      )
    end

    # Private: returns all the tasklist blocks we can parse in the parent issue
    # body.
    #
    # Note we are re-instantiating the operation here but that is very cheap.
    sig { returns(T::Array[CommonMarker::Node]) }
    memoize def parent_tasklist_blocks
      append_item_operation
        .tasklist_blocks(@common_marker.render_doc(safe_parent_issue_body.gsub(/\r\n?/, "\n")))
    end

    # Private: returns the parent issue body if the parent issue has a tasklist.
    # Otherwise return a string that is the a parent issue body with a tasklist
    # block appended to the end.
    sig { returns(String) }
    def body_with_at_least_one_tasklist_block
      return safe_parent_issue_body unless parent_tasklist_blocks.empty?

      safe_parent_issue_body + EMPTY_TASKLIST_BLOCK
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
      message = success ? "Success" : "Failed to append child to parent"

      @stats.increment(METRIC_NAME, tags: ["status:#{status}"])

      @result_class.new(
        success: success,
        message: message
      )
    end
  end
end
