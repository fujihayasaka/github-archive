# typed: true
# frozen_string_literal: true

module Api::Serializer::MergeQueueDependency
  extend T::Helpers

  requires_ancestor { T.class_of(Api::Serializer) }

  def merge_queue_hash(queue, options = {})
    return nil unless queue
    {
      id: queue.id,
      node_id: global_id_for(queue, options),
    }
  end

  def merge_queue_entry_hash(entry, options = {})
    return nil unless entry
    {
      id: entry.id,
      is_solo: entry.solo?,
      node_id: global_id_for(entry, options),
    }
  end
end
