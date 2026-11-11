# typed: strict
# frozen_string_literal: true

module MemexBulkAddNotificationsHelper
  PROGRESS_MESSAGE_TYPE = T.let("project_items_bulk_add_progress", String)
  COMPLETION_MESSAGE_TYPE = T.let("project_items_bulk_add_complete", String)

  sig do
    params(
      memex_project: MemexProject,
      actor_id: T.nilable(Integer),
      percentage: Integer,
      request_context: T.nilable(T::Hash[Symbol, T.untyped])
    ).void
  end
  def notify_clients_of_progress(memex_project, actor_id:, percentage:, request_context:)
    context = request_context || {}
    # Keep in sync with client event contract (BulkAddUpdateProgressSocketMessageData)
    memex_project.notify_memex_channel({
      type: PROGRESS_MESSAGE_TYPE,
      actor: { id: actor_id },
      percentage: percentage,
      requestId: context[:request_id]
    })
  end

  sig do
    params(
      memex_project: MemexProject,
      actor_id: T.nilable(Integer),
      added: Integer,
      failed: Integer,
      request_context: T.nilable(T::Hash[Symbol, T.untyped]),
      initial_import: T.nilable(T::Boolean)
    ).void
  end
  def notify_clients_of_completion(memex_project, actor_id:, added:, failed:, request_context: {}, initial_import: nil)
    context = request_context || {}
    # Keep in sync with client event contract (BulkAddUpdateCompleteSocketMessageData)
    memex_project.notify_memex_channel({
      type: COMPLETION_MESSAGE_TYPE,
      actor: { id: actor_id },
      totalItemsAdded: added,
      totalItemsFailed: failed,
      requestId: context[:request_id],
      initialImport: initial_import,
      invalidateQueryCache: true,
    })
  end
end
