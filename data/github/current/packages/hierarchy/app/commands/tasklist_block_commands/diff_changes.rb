# typed: strict
# frozen_string_literal: true

module TasklistBlockCommands
  class DiffChanges
    SUBSCRIPTION_NAME = "tasklist.diff"

    sig do
      params(
        tasklist_blocks_previous: T::Array[TasklistBlock],
        tasklist_blocks_next: T::Array[TasklistBlock],
        issue: ::Issue,
        actor: ::User,
      ).void
    end
    def initialize(tasklist_blocks_previous:, tasklist_blocks_next:, issue:, actor:)
      @tasklist_blocks_previous = tasklist_blocks_previous
      @tasklist_blocks_next = tasklist_blocks_next
      @issue = issue
      @actor = actor
    end

    # Instruments info about the previous and next tasklist blocks for instrumentation
    # purposes.
    #
    # Returns a TasklistBlocks::CommandResult.
    sig { returns(TasklistBlockCommands::Result) }
    def call
      instrument_diff unless nothing_to_instrument?

      TasklistBlockCommands::Result.new(
        success: true,
        message: "diffed",
      )
    end

    private

    sig { returns(Integer) }
    def count_block_difference
      @tasklist_blocks_next.size - @tasklist_blocks_previous.size
    end

    sig { returns(Integer) }
    def count_item_difference
      @tasklist_blocks_next.flat_map(&:items).size -
        @tasklist_blocks_previous.flat_map(&:items).size
    end

    sig { void }
    def instrument_diff
      GlobalInstrumenter.instrument(SUBSCRIPTION_NAME, {
        actor: @actor,
        issue_repository: @issue.repository,
        issue: @issue,
        tasklist_block_diff: count_block_difference,
        tasklist_item_diff: count_item_difference,
      })
    end

    sig { returns(T::Boolean) }
    def nothing_to_instrument?
      count_block_difference.zero? && count_item_difference.zero?
    end
  end
end
