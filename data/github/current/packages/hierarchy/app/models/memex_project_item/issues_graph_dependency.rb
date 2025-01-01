# typed: strict
# frozen_string_literal: true

module MemexProjectItem::IssuesGraphDependency
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { MemexProjectItem }

  delegate :to_hierarchy_model_key, # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    :to_hierarchy_model,
    to: :content

  class SyncJobEnqueuedForDestroyedItemError < StandardError; end

  sig { returns(T.nilable(T.any(SyncMemexProjectItemByIdToIssuesGraphJob, FalseClass))) }
  def enqueue_sync_to_hierarchy_job
    # sync_to_hierarchy is a no-op for DraftIssues
    return if self.content.present? && self.content.is_a?(DraftIssue)

    return unless GitHub.issues_graph_api_enabled?

    is_destroyed = self.destroyed?

    GitHub.logger.info(
      "MemexProjectItem#enqueue_sync_to_hierarchy_job fired",
      "code.namespace": "MemexProjectItem",
      "code.function": "enqueue_sync_to_hierarchy_job",
      "gh.memex.item.id": self.id,
      "gh.memex.item.is_destroyed": is_destroyed
    )

    if is_destroyed
      raise SyncJobEnqueuedForDestroyedItemError.new "MemexProjectItem #{self.id} is destroyed"
    else
      SyncMemexProjectItemByIdToIssuesGraphJob.perform_later(self.id)
    end
  end

  # Public: Sync a memex project item and its project to the issues graph
  sig { void }
  def sync_to_hierarchy
    return unless GitHub.issues_graph_api_enabled?
    return unless memex_project

    content = self.content
    # Since `to_hierarchy_model` raises an error for DraftIssues
    # We can return early
    return if content.is_a?(DraftIssue)

    project = self.memex_project

    return unless project.present?
    return unless content.present?

    if content.is_a?(Issue) || content.owner.feature_enabled?(:tasklist_block)
      to = content.try(:to_hierarchy_model)
    end
    return unless to.present?

    from = project.to_hierarchy_model
    return unless from.present?

    GitHub
      .issues_graph_api_client
      .upsert_project_and_relationships(
        from: from,
        to: [to],
        stat_tags: ["context:memex_project_item.issues_graph_dependency.sync_to_hierarchy"]
      )
  end
end
