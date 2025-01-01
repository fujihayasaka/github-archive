# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

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

  # @param workflow [MemexProjectWorkflow]
  # @param input [Array<Tuple<content_type, content_id>>] - an array of tuples that the workflow will be run on either MemexProjectItems, Issues or PullRequests
  # @param actor [User] - the user that is triggering the workflow run
  # @param event_time [Time] - the time of the event that triggered the workflow run in nanoseconds
  def perform(workflow_id:, input:, actor_id:, event_time:, tags: [], manual_run: false)
    workflow = with_read { MemexProjectWorkflow.find(workflow_id) }
    actor = with_read { User.find(actor_id) }
    models = load_input(input)

    MemexProjectWorkflow::PipeRunner.run(workflow: workflow, input: models, actor: actor, tags: tags, event_time: event_time, manual_run: manual_run)
  end

  private

  sig { params(input: T.nilable(T::Array[T.untyped])).returns(T.nilable(T::Array[T.untyped])) }
  def load_input(input)
    # input can be nil in the case of manually-triggered workflows
    # ex: https://github.com/github/github/blob/87ec6b00c165b78e29defb5cb1ba6a46f110c67b/app/controllers/memexes/workflows_controller.rb#L64
    return nil if input.nil?

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
