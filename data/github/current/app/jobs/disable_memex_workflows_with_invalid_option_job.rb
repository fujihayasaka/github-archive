# typed: true
# frozen_string_literal: true

class DisableMemexWorkflowsWithInvalidOptionJob < ApplicationJob
  queue_as :disable_memex_workflows_with_invalid_option

  METRIC = "memex.disable_memex_workflows_with_invalid_option_job"

  # These actions are configured with an option id
  AFFECTED_ACTION_TYPES = [:set_field, :get_project_items]

  # Retry if the job is killed externally for whatever reason
  retry_on_dirty_exit

  # There are a number of common availability issues that are transient. Retry!
  # See https://github.com/github/github/blob/37ae9df4b5706e60f70ef3622046ce1d1ef5efcf/app/jobs/application_job.rb#L205
  retry_on_recoverable_exceptions

  # This error is thrown if there are too many jobs in parallel. Just retry!
  # See https://github.com/github/github/blob/master/lib/github/restraint.rb
  retry_on GitHub::Restraint::UnableToLock

  # Find and disable any actions (and related workflows) that were configured with
  # the column id and options id(s) that were removed from it.
  #
  # column_id - Integer - The column that was updated to remove 1 or more # options
  # removed_option_ids - Array<String> - The option ids that were removed from
  # the given column
  #
  # Returns nothing
  def perform(column_id:, removed_option_ids:)
    actions = with_read do
      MemexProjectWorkflowAction.where(action_type: AFFECTED_ACTION_TYPES)
      .where(option_id: removed_option_ids)
      .where(memex_project_column_id: column_id)
    end
    return tag_404 if actions.empty?

    with_write_workflows do
      # Disable related workflows
      MemexProjectWorkflow
        .where(id: actions.map(&:memex_project_workflow_id))
        .each { |workflow| workflow.update_attribute(:enabled, false) }
    end

    # Nullify `fieldOptionId` for easier validation later
    with_write_actions do
      actions.each do |action|
        action.arguments["fieldOptionId"] = nil
        action.save
      end
    end

    tag_200
  end

  private def with_read
    ActiveRecord::Base.connected_to(role: :reading) do
      yield
    end
  end

  private def with_write
    ActiveRecord::Base.connected_to(role: :writing) do
      yield
    end
  end

  private def with_write_workflows
    with_write do
      MemexProjectWorkflow.throttle do
        yield
      end
    end
  end

  private def with_write_actions
    with_write do
      MemexProjectWorkflowAction.throttle do
        yield
      end
    end
  end

  private def tag_200
    log("status:200")
  end

  private def tag_404
    log("status:404")
  end

  private def log(tags)
    yield if block_given?

    GitHub.dogstats.increment(
      METRIC,
      tags: [tags],
    )
  end
end
