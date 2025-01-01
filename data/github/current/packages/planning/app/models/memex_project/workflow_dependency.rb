# typed: strict
# frozen_string_literal: true

module MemexProject::WorkflowDependency
  extend ActiveSupport::Concern
  extend T::Helpers
  extend T::Sig

  requires_ancestor { MemexProject }

  class_methods do
    extend T::Sig

    sig do
      params(
        creator: User,
        status_column: MemexProjectColumn,
      ).returns(T::Array[T::Hash[Symbol, T.untyped]])
    end
    def default_persisted_workflow_attributes(creator:, status_column:)
      [
        MemexProjectWorkflow.default_closed_workflow_attributes(
          status_column: status_column,
          creator: creator,
          enabled: true
        ),
        MemexProjectWorkflow.default_merged_workflow_attributes(
          status_column: status_column,
          creator: creator,
          enabled: true
        ),
        MemexProjectWorkflow.default_auto_close_workflow_attributes(
          status_column: status_column,
          creator: creator,
          enabled: true
        )
      ]
    end
  end

  sig { returns(T::Array[MemexProjectWorkflow]) }
  def default_workflows
    default_workflow_attributes.map do |workflow_attributes|
      MemexProjectWorkflow.new(workflow_attributes).tap(&:readonly!)
    end
  end

  sig { params(actor: T.nilable(User)).returns(T::Array[MemexProjectWorkflowConfiguration]) }
  def workflow_configurations(actor)
    default_workflow_attributes.map do |workflow_attributes|
      MemexProjectWorkflowConfiguration.new(default_workflow_attributes: workflow_attributes, actor: actor)
    end
  end

  sig do
    params(
      creator: T.nilable(User),
      repository: T.nilable(Repository)
    ).returns(T::Array[T::Hash[Symbol, T.untyped]])
  end
  def default_workflow_attributes(creator: nil, repository: nil)
    attributes = [
      MemexProjectWorkflow.default_item_added_workflow_attributes(
        status_column: T.must(status_column),
        creator: creator
      ),
      MemexProjectWorkflow.default_reopened_workflow_attributes(
        status_column: T.must(status_column),
        creator: creator
      ),
      MemexProjectWorkflow.default_closed_workflow_attributes(
        status_column: T.must(status_column),
        creator: creator
      ),
      MemexProjectWorkflow.default_review_changes_requested_workflow_attributes(
        status_column: T.must(status_column),
        creator: creator
      ),
      MemexProjectWorkflow.default_review_approved_workflow_attributes(
        status_column: T.must(status_column),
        creator: creator
      ),
      MemexProjectWorkflow.default_merged_workflow_attributes(
        status_column: T.must(status_column),
        creator: creator
      ),
      MemexProjectWorkflow.default_auto_archive_workflow_attributes(
        creator: creator
      ),
      MemexProjectWorkflow.default_auto_add_workflow_attributes(
        creator: creator,
        repository: repository
      ),
      MemexProjectWorkflow.default_auto_close_workflow_attributes(
        status_column: T.must(status_column),
        creator: creator
      )
    ]

    attributes << MemexProjectWorkflow.default_sub_issues_workflow_attributes(
      creator: creator
    ) if SubIssuesFeature.enabled?(T.cast(self, MemexProject))

    attributes
  end

  private

  sig { void }
  def enqueue_memex_project_disable_all_workflows_job
    return if self.closed_at.nil?

    MemexProjectDisableAllWorkflowsJob.perform_later(id)
  end
end
