# typed: true
# frozen_string_literal: true

# SyncFeatureActorsJob is queued on demand from the devtools feature flag controller when the user clicks the "Sync Actors" button.
# This job will find all features that have the "actors" gate enabled and changed and queue a SyncFeatureActorBatchJob for each feature
# to start the sync process of actors in batches.
module LegacyFeatureFlag
  class SyncFeatureActorsJob < BatchedJob
    queue_as :sync_feature_flags
    retry_on_dirty_exit
    retry_on_recoverable_exceptions
    MAX_RETRIES = 1
    BATCH_SIZE = 1000

    # the logic of a single batch processing goes here.
    # you need to override this method in your custom job.
    #
    # batch - a batch object returned from next_batch()
    #
    # *args and **options will contain all params you have passed to YourJob.perform_later(*args, options) call
    def process_batch(batch, sync_start_date, display_user, sync_correlation_id, **options)
      requested_syncs = 0
      batch.each do |feature|
        LegacyFeatureFlag::SyncFeatureActorBatchJob.perform_later(feature, display_user, sync_correlation_id)
        requested_syncs += 1
        GitHub.dogstats.count("sync_feature_actors_job.requested_syncs.count", 1, tags: ["sync_correlation_id:#{sync_correlation_id}"])
      end

      begin
        GitHub::Chatterbox.client.say!("#{display_user}", "Job batch status for your sync feature actors job with sync_correlation_id #{sync_correlation_id}: Requested #{requested_syncs} features to sync actors. Check Sentry for more details in case of failures.")
      rescue Chatterbox::Error => e
        Failbot.report(e, "gh.feature_management.sync_correlation_id" => sync_correlation_id)
      end
    end

    # query for the batch to be processed.
    # you need to override this method in your custom job
    #
    # :timestamp - a timestamp for when the job was initially scheduled.
    #              Useful for querying using `created_at` attribute of records.
    # :offset_item_id - an id of the record to be used as the first one for the current batch in `where id > ?` clause.
    # **options - will contain all params you have passed to YourJob.perform_later(*args, options) call
    #
    # Both parameters will be injected into **options by the base algorithm
    # Additionally, you can use all params you have passed to YourJob.perform_later(*args, options) call
    #
    # Should return a batch object (e.g. array or records) that would be used by other methods
    def next_batch(sync_start_date, display_user, sync_correlation_id, timestamp: Time.now.utc, offset_item_id: 0, progress: 0, **options)
      features = FlipperFeature
        .where(rollout_updated_at: sync_start_date..Time.now.utc)
        .where("id > ?", offset_item_id)
        .order(id: :asc)
        .limit(BATCH_SIZE)
    end

    def perform(sync_start_date, display_user, sync_correlation_id, **options)
      super
    end
  end
end
