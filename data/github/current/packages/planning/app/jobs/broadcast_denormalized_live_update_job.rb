# typed: strict
# frozen_string_literal: true

# Delayed broadcaster for the memex denormalization pipeline's live-update
# websocket messages.
#
# The `DenormalizationProcessor` normally broadcasts a live update inline
# after writing to Elasticsearch. When the
# `:projects_processor_skip_es_refresh` flag causes a processor to write with
# `Refresh::False`, the ES document is not yet visible to search when the
# write returns. Broadcasting immediately in that case would cause clients to
# refetch via GraphQL and see stale data for up to `index.refresh_interval`
# (~1s for `memex_project_items`).
#
# To avoid that race, the processor enqueues this job with a small wait
# (`BROADCAST_REFRESH_DELAY`) so the websocket fires AFTER the next ES
# periodic refresh has run. Inputs are pre-resolved to scalars at enqueue
# time so the job payload contains no ActiveRecord references (project may
# have been deleted by the time the job runs; `broadcast_resolved` filters
# missing projects safely).
class BroadcastDenormalizedLiveUpdateJob < ApplicationJob
  queue_as :memex_broadcast_denormalized_live_update
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  sig do
    params(
      memex_project_ids: T::Array[Integer],
      timestamp: Integer,
      source_topic: T.nilable(String),
      model_gids: T::Array[String],
      items_by_project: T::Hash[T.untyped, T::Array[T::Hash[T.untyped, T.untyped]]],
      request_id: T.nilable(String),
    ).void
  end
  def perform(memex_project_ids:, timestamp:, source_topic: nil, model_gids: [], items_by_project: {}, request_id: nil)
    # ActiveJob serializes Hash keys to strings via JSON; restore the
    # `{Integer => [{id:, gid:}, ...]}` shape that `broadcast_resolved`
    # expects.
    normalized_items = T.let({}, T::Hash[Integer, T::Array[T::Hash[Symbol, T.any(Integer, String)]]])
    items_by_project.each do |project_id, items|
      normalized_items[project_id.to_i] = items.map do |item|
        { id: item[:id] || item["id"], gid: item[:gid] || item["gid"] }
      end
    end

    MemexProjectColumn::Interface::Indexable::Processor::LiveUpdateBroadcaster.broadcast_resolved(
      memex_project_ids:,
      timestamp:,
      source_topic:,
      model_gids:,
      items_by_project: normalized_items,
      request_id:,
    )
  end
end
