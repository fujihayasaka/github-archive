# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# SyncFeatureActorBatchJob is queued for each feature that has actors to batch synchronize to the feature-flag-hub
# during milestone 3 batch import.
module LegacyFeatureFlag
  class SyncFeatureActorBatchJob < ActorBatchedJob

    queue_as :sync_feature_flags
    retry_on_dirty_exit
    retry_on_recoverable_exceptions
    REQUEST_TIMEOUT = 10.0 # seconds
    MAX_RETRIES = 1
    BATCH_SIZE = 1000

    # Connect to the feature flag hub sync API and send the batch of actors to be synchronized for the feature flag.
    # This batch is using a merge sync algorithm where the actorids are sorted and contain a start and end subset of
    # actor ids that are contigious. The last actor id of each batch in a multiple batch list will match the first actor
    # in the next batch. This allows the feature flag hub to merge the actors into the feature flag by detecting which
    # actors to delete, insert or ignore.
    def process_batch(batch, feature, display_user, sync_correlation_id, **options)
      GitHub.logger.info("Starting sync feature actor batch job",
        "code.namespace": "LegacyFeatureFlag::SyncFeatureActorBatchJob",
        "code.function": "process_batch",
        "gh.correlation_id": sync_correlation_id,
        "feature_flag.key": feature.name,
      )

      client = T.let(nil, T.nilable(FeatureManagement::FeatureFlagHubClient))
      begin
        client = FeatureManagement::FeatureFlagHubClient.new(REQUEST_TIMEOUT, nil, MAX_RETRIES)
      rescue FeatureManagement::FeatureFlagHubClientError => e
        Failbot.report(e)
        GitHub.dogstats.count("sync_feature_actor_batch_job.failed_syncs.count", 1, tags: ["sync_correlation_id:#{sync_correlation_id}"])
        return
      end

      # We need to know if this is the first or last batch of sync for the feature flag so any actors remaining before the first batch
      # or the last batch can be deleted. The API will remove any actor before the first provided actor when first batch is true and also
      # any actor after the last actor provided if last batch is true. When the list is empty all actors will be removed and the provided list will not be used.
      first_batch = options[:offset_item_name] == ""
      last_batch = !has_next_batch?(batch)

      client.bulk_sync_feature_actors(feature.name, sync_correlation_id, first_batch, last_batch, batch)
      GitHub.dogstats.count("sync_feature_actor_batch_job.successful_syncs.count", batch_size(batch), tags: ["sync_correlation_id:#{sync_correlation_id}", "start_actor:#{batch.first}", "end_actor:#{batch.last}", "first_batch:#{first_batch}", "last_batch:#{last_batch}"])
    end

    # Retrieve the next subset of actors for the specified feature ordering by actor name. Add an additional actor to the end of the batch to make them continguous.
    # The actor ids look like a type:id, e.g. User:23234234. This list only contains the actor gates for the feature flag in the next batch of the total list.
    def next_batch(feature, display_user, sync_correlation_id, timestamp: Time.now.utc, offset_item_name: "", progress: 0, **options)
      FlipperGate
        .where(flipper_feature_id: feature.id)
        .where(name: "actors")
        .where("value > ?", offset_item_name)
        .order(value: :asc)
        .limit(BATCH_SIZE + 1)
        .pluck(:value)
    end

    # We have more work to do if the batch size is equal (or greater) to the max batch size. It will be greater if we have more batches remaining.
    def has_next_batch?(batch, **options)
      batch.size >= BATCH_SIZE
    end

    # When we create a batch it may have an additional value at the end for the merge sync to be contiguous. We need to ignore that in the size usages
    def batch_size(batch)
      if batch.size > BATCH_SIZE
        batch.size - 1
      else
        batch.size
      end
    end

    # The next batch offset will start after the last item in the batch unless our batch has the extra item for the contiguous merge sync
    def next_batch_offset_item_name(batch, feature, display_user, sync_correlation_id, **options)
      if batch.size <= BATCH_SIZE
        batch.last
      else
        batch[batch.length - 2]
      end
    end

    # Entry point for the batched job. This will be called by the scheduler and will continue to call itself until there are no more batches to process.
    # This entry point is queued by the job named SyncFeatureActorsJob for each feature that has actors to synchronize.
    def perform(feature, display_user, sync_correlation_id, **options)
      super
    end
  end
end
