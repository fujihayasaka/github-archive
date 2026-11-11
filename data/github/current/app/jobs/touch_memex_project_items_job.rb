# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class TouchMemexProjectItemsJob < ApplicationJob
  queue_as :touch_memex_project_items

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  locked_by timeout: 5.minutes, key: ->(job) {
    job.arguments[0]
  }

  MAX_THROTTLE_RETRIES = 5
  BATCH_SIZE = 50

  def perform(issue)
    if FeatureFlag.vexi.enabled?(:touch_memex_project_items_job_read_from_replica, default: false)
      items, actor = with_read do
        items = issue.memex_project_items.to_a
        # Prefill associations that the touch + after_commit callbacks
        # would otherwise lazily SELECT from the primary inside
        # the `throttle_writes` block below.
        #
        # `{ content: :repository }` walks into the polymorphic `:content`
        # (resolved to `issue` via `available_records`) and preloads its
        # `:repository`. Without this, `notify_socket_subscribers`
        # (after_commit) would lazy `Repositories.domain.by_id` from the
        # primary inside `throttle_writes`.
        GitHub::PrefillAssociations.prefill_associations(
          items,
          [:memex_project, :creator, { content: :repository }],
          available_records: [issue],
        )
        # Resolve the contextual actor once on the replica and memoize it onto
        # each item so `ContextualActor#actor` doesn't `User.find_by(...)` from
        # the primary once per item during instrumentation callbacks.
        actor_id = GitHub.context[:actor_id]
        actor = (actor_id && User.find_by(id: actor_id)) || User.ghost
        [items, actor]
      end
      return if items.empty?

      items.each_slice(BATCH_SIZE) do |slice|
        MemexProjectItem.throttle_writes do
          # Touch each item individually to trigger after_commit callbacks,
          # which emit project_item_metadata_update events for each item.
          # Prefill the resolved actor onto each item just before `touch` so
          # `ContextualActor#actor` reuses it instead of issuing a primary
          # `User.find_by` lookup inside the `throttle_writes` block.
          slice.each do |item|
            item.prefill_actor(actor)
            item.touch
          end
        end
      end
    else
      memex_project_items = issue.memex_project_items
      return unless memex_project_items.any?

      with_write do
        memex_project_items.in_batches.each_record(&:touch)
      end
    end
  end
end
