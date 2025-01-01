# typed: true
# frozen_string_literal: true

class RevokeAllPermissionsForActorJob < BatchedJob
  queue_as :background_destroy

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  def next_batch(actor_id, actor_type, entry_point, timestamp: Time.now.utc, offset_item_id: 0, progress: 0, **options)
    Permissions::Service.permission_ids_granted_on_actor_with_limit_and_offset(
      actor_type: actor_type, actor_id: actor_id, offset_id: offset_item_id, limit: BATCH_SIZE
    )
  end

  def process_batch(batch, *args, **options)
    entry_point = args.last
    Permissions::Service.revoke_permissions_by_id(batch, entry_point: entry_point)
  end

  def next_batch_offset_item_id(batch, *args, **options)
    batch.max
  end
end
