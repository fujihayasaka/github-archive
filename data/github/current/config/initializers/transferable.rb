# typed: true
# frozen_string_literal: true

module Transferable
  TRANSFERABLE_BATCH_LIMIT = 100

  # Transfers all records in the association to a new owner.
  #
  # If a block is given and the :octoshift_mannequin_reclaiming_reindex_issues_and_prs feature flag
  # is enabled, it will be called after each batch with the IDs that were transferred.
  # This allows callers to perform post-transfer actions (like reindexing) immediately after each batch,
  # ensuring idempotency on retries - already-transferred records won't be included in subsequent runs.
  #
  # Example:
  #   source.issues.transfer_to(target) do |transferred_ids|
  #     transferred_ids.each { |id| Search.add_to_search_index("issue", id) }
  #   end
  #
  def transfer_to(model, &after_batch)
    T.bind(self, ActiveRecord::Associations::CollectionProxy)

    reflection = proxy_association.reflection

    update_all_args = reflection.type ? { reflection.type => model.class.to_s, reflection.foreign_key => model.id } : { reflection.foreign_key => model.id }

    # Only capture IDs and execute callback if feature flag is enabled
    should_callback = block_given? && FeatureFlag.vexi.enabled?(:octoshift_mannequin_reclaiming_reindex_issues_and_prs, default: false)

    if FeatureFlag.vexi.enabled?(:octoshift_mannequin_reclaiming_in_batches, default: false)
      in_batches(of: TRANSFERABLE_BATCH_LIMIT) do |batch| # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        # Capture IDs before update_all since we need them for the callback
        batch_ids = should_callback ? batch.pluck(:id) : nil # domain-isolation-query-violation:ignore:packages/issues (SELECT)

        self.model.throttle do
          batch.update_all(**update_all_args) # domain-isolation-query-violation:ignore:packages/issues (UPDATE)
        end

        # Call the after_batch callback with transferred IDs
        after_batch.call(batch_ids) if should_callback && batch_ids.present?
      end
    else
      # For non-batched transfers, capture all IDs before update
      all_ids = should_callback ? pluck(:id) : nil # domain-isolation-query-violation:ignore:packages/issues (SELECT)

      update_all(**update_all_args) # domain-isolation-query-violation:ignore:packages/issues (UPDATE)

      after_batch.call(all_ids) if should_callback && all_ids.present?
    end
  end
end

ActiveRecord::Associations::CollectionProxy.include Transferable
