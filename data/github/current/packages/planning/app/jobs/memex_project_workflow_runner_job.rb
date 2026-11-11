# typed: strict
# frozen_string_literal: true

# Executes an automation that a user has set up for a Project.
class MemexProjectWorkflowRunnerJob < ApplicationJob

  queue_as :memex_project_workflow_runner

  RETRY_ATTEMPTS = 7 # ~2 hours

  retry_on_dirty_exit
  retry_on_recoverable_exceptions attempts: RETRY_ATTEMPTS
  retry_on GitHub::Spokes::ClientError
  retry_on Faraday::TimeoutError # set_field actions related to pulls have a dependency on the Spokes API, which can timeout

  resolve_tenant_context do |args|
    workflow = MemexProjectWorkflow.find_by(id: args[:workflow_id])
    workflow&.memex_project&.resolve_tenant
  end

  # @param workflow_id Identifier for the MemexProjectWorkflow to execute
  # @param input An array of tuples of the form [content_type, content_id] (e.g. ["Issue", 123]) describing the inputs
  #   that the workflow should operate on
  # @param actor_id Identifier for the user who initiated the workflow
  # @param event_time The timestamp from when the Hydro event that triggered the workflow was published
  # @param tags A list of additional tags to add to Datadog metrics emitted during workflow execution
  # @param manual_run Whether or not this workflow was kicked off manually rather than as the result of a Hydro event
  sig do
    params(
      workflow_id: Integer,
      input: T.nilable(T::Array[[String, Integer]]),
      actor_id: T.nilable(Integer),
      event_time: T.nilable(Time),
      manual_run: T::Boolean,
      tags: T::Array[String],
      additional_log_attributes: T::Hash[String, T.untyped],
    )
    .void
  end
  def perform(
    workflow_id:,
    input:,
    actor_id: nil,
    event_time: nil,
    manual_run: false,
    tags: [],
    additional_log_attributes: {})

    workflow = with_read { MemexProjectWorkflow.find(workflow_id) }
    actor = actor_id && with_read { User.find(actor_id) }

    MemexProjectWorkflow::PipeRunner
      .new(
        workflow:,
        input: load_input(input),
        actor:,
        event_time:,
        manual_run:,
        tags:,
        additional_log_attributes:
      )
      .run
  end

  sig do
    params(input: T.nilable(T::Array[[String, Integer]]))
    .returns(T.nilable(T::Array[T.any(MemexProjectItem, Issue, PullRequest, DraftIssue)]))
  end
  private def load_input(input)
    return if input.nil?

    priority = input.each_with_index.reduce({}) do |hash, (tuple, index)|
      hash[tuple] = index
      hash
    end

    content_ids_by_type = Hash.new { |h, k| h[k] = [] }
    input.reduce(content_ids_by_type) do |hash, tuple|
      hash[tuple[0]] << tuple[1]
      hash
    end

    models_by_type = Hash.new { |h, k| h[k] = [] }
    content_ids_by_type.keys.reduce(models_by_type) do |hash, content_type|
      klass = content_type.constantize
      hash[content_type] = with_read { klass.where(id: content_ids_by_type[content_type]) } # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      hash
    end

    input_models = models_by_type
      .values
      .flatten
      .sort_by { |model| priority[[model.class.name, model.id]] }
      .reject { |model| model.is_a?(MemexProjectItem) && model.archived_at.present? } # project workflow automations should not run on archived items

    input_models
  end
end
