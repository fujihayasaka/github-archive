# typed: strict
# frozen_string_literal: true

# This job purges expired Memex Elasticsearch consistency scores for elasticsearch
# indices that no longer exist, ensuring that the Elasticsearch consistency metrics
# remain relevant and up-to-date over time.
#
# The job leverages the `BatchedJob` framework which helps manage resilience and
# performance when dealing with large datasets.
#
# It identifies scores by checking the `index_name` against a list of currently readable
# Elasticsearch indices. If the `index_name` is not in the list, it is considered expired,
# and the corresponding consistency score is deleted.
class PurgeExpiredMemexElasticsearchConsistencyScoresJob < BatchedJob
  include ActiveJob::InitiallyEnqueuedAt

  BATCH_SIZE = 1000

  queue_as :purge_expired_memex_elasticsearch_consistency_scores
  locked_by timeout: 8.hours, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  retry_on WaitForReplication::DataUnavailable do |job, error|
    job.failed(error)
  end

  retry_on_dirty_exit do |job, error|
    job.failed(error)
  end

  retry_on_recoverable_exceptions(wait: 3.seconds) do |job, error|
    job.failed(error)
  end

  sig do
    override
      .params(
        args: T.untyped,
        timestamp: Time,
        offset_item_id: Integer,
        progress: Integer,
        _options: T.untyped
      )
      .returns(T::Array[MemexProjectElasticsearchConsistency])
  end
  def next_batch(*args, timestamp: Time.now.utc, offset_item_id: 0, progress: 0, **_options)
    indices_to_keep = T.let(
      Elastomer::Indexes::MemexProjectItems.readable_indices,
      T::Array[Elastomer::Indexes::MemexProjectItems]
    )

    MemexProjectElasticsearchConsistency
      .where("index_name NOT IN (?) OR index_name IS NULL", indices_to_keep.map(&:name))
      .where("id > ?", offset_item_id)
      .order(:id)
      .limit(BATCH_SIZE)
      .to_a
  end

  sig { override.params(batch: T::Array[MemexProjectElasticsearchConsistency], args: T.untyped, options: T.untyped).void }
  def process_batch(batch, *args, **options)
    GitHub.dogstats.count("purge_expired_memex_elasticsearch_consistency_scores.deleted_scores_count", batch.count)
    return if batch.empty?

    # Delete all records included in the batch
    MemexProjectElasticsearchConsistency.throttle do
      batch.each do |score|
        with_write { score.destroy! }
      end
    end
  end
end
