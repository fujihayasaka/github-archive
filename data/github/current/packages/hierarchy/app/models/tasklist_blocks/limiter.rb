# typed: true
# frozen_string_literal: true

module TasklistBlocks
  class Limiter

    extend T::Sig

    SOFT_LIMIT_TASKS_PER_TASKLIST = 50
    HARD_LIMIT_TASKS_PER_TASKLIST = 250
    SOFT_LIMIT_TASKLISTS_PER_ISSUE = 5
    HARD_LIMIT_TASKLISTS_PER_ISSUE = 10

    sig { params(tasklist_block_hard_limits_enabled: T::Boolean, tasklist_block_soft_limits_enabled: T::Boolean).void }
    def initialize(tasklist_block_hard_limits_enabled, tasklist_block_soft_limits_enabled)
      @tasklist_block_hard_limits_enabled = tasklist_block_hard_limits_enabled
      @tasklist_block_soft_limits_enabled = tasklist_block_soft_limits_enabled
    end

    # Checks if the tasks or tasklists in an issue have exceeded the limits
    # For soft limits, we return when it is "more than" the limit to display the warning
    # For hard limits, we return when it is "equal" the limit to display the error and
    # we return LimitError when it is "more than" the limit to prevent issue create and update
    #
    #  Returns a tuple of the type of limit exceeded and the limit error if any
    sig do
      params(number_of_tasks: Integer, number_of_tasklists: Integer)
      .returns([T.nilable(String), T.nilable(LimitError)])
    end
    def check_if_exceed_limit(number_of_tasks, number_of_tasklists)
      if @tasklist_block_hard_limits_enabled && number_of_tasks >= HARD_LIMIT_TASKS_PER_TASKLIST
        GitHub.dogstats.increment(TasklistBlocks::TasklistBlock::TASKLIST_BLOCK_VALIDATION, tags: ["type:tasks_per_tasklist_exceeded", "level:error"])
        # Prevent create and update only when number has exceeded limit
        limit_error = TasklistBlocks::LimitError.new(number_of_tasks, "tasks per tasklist") if number_of_tasks > HARD_LIMIT_TASKS_PER_TASKLIST
        return ["hard_limit_tasks_per_tasklist", limit_error]
      elsif @tasklist_block_hard_limits_enabled && number_of_tasklists >= HARD_LIMIT_TASKLISTS_PER_ISSUE
        GitHub.dogstats.increment(TasklistBlocks::TasklistBlock::TASKLIST_BLOCK_VALIDATION, tags: ["type:tasklists_per_issue_exceeded", "level:error"])
        # Prevent create and update only when number has exceeded limit
        limit_error = TasklistBlocks::LimitError.new(number_of_tasklists, "tasklists per issue") if number_of_tasklists > HARD_LIMIT_TASKLISTS_PER_ISSUE
        return ["hard_limit_tasklists_per_issue", limit_error]
      elsif @tasklist_block_soft_limits_enabled && number_of_tasks > SOFT_LIMIT_TASKS_PER_TASKLIST
        GitHub.dogstats.increment(TasklistBlocks::TasklistBlock::TASKLIST_BLOCK_VALIDATION, tags: ["type:tasks_per_tasklist_exceeded", "level:warning"])
        return ["soft_limit_tasks_per_tasklist", nil]
      elsif @tasklist_block_soft_limits_enabled && number_of_tasklists > SOFT_LIMIT_TASKLISTS_PER_ISSUE
        GitHub.dogstats.increment(TasklistBlocks::TasklistBlock::TASKLIST_BLOCK_VALIDATION, tags: ["type:tasklists_per_issue_exceeded", "level:warning"])
        return ["soft_limit_tasklists_per_issue", nil]
      end

      [nil, nil]
    end
  end
end
