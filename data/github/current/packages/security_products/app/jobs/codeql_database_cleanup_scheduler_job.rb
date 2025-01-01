# typed: true
# frozen_string_literal: true

# Runs on a schedule and triggers instances of CodeqlDatabaseCleanupJob.
#
# Acts as a safety net to ensure that CodeqlDatabaseCleanupJob is triggered
# on each repository at least once in a fixed period. This allows us to be
# sure that we're meeting privacy concerns regarding CodeQL databases owned
# by private or deleted repositories. Otherwise the cleanup job is only
# triggered on certain events, such as a new database being uploaded.
class CodeqlDatabaseCleanupSchedulerJob < ApplicationJob
  queue_as :code_scanning_multi_repository_variant_analysis

  # this is a cross tenant background cleanup job
  exempt_from_tenant_context_requirement

  retry_on_dirty_exit

  # How frequently to run this job.
  SCHEDULE_INTERVAL = 1.hour

  # How frequently we ideally want to get to each individual repository.
  # As in, each repository should on average be processed once in this period.
  PROCESSING_INTERVAL = 1.week

  # Key for KV to store the ID of the last repository processed.
  # So next time it runs it can start from where it left off.
  LAST_REPO_ID_PROCESSED_KV_KEY = "codeql_database_cleanup_scheduler_job.last_repo_id_processed"

  schedule interval: SCHEDULE_INTERVAL, condition: -> { !GitHub.enterprise? }

  def perform
    repo_ids = get_repo_ids_to_process
    return if repo_ids.empty?

    repo_ids.each_with_index do |repo_id, index|
      # It doesn't matter if these jobs overlap, but spacing them out over the
      # scheduling period will hopefully help to lessen database load.
      delay = SCHEDULE_INTERVAL * index / repo_ids.size
      CodeqlDatabaseCleanupJob.set(wait: delay).perform_later(repository_id: repo_id)
    end

    ActiveRecord::Base.connected_to(role: :writing) do
      CodeScanning::KV.store.set(LAST_REPO_ID_PROCESSED_KV_KEY, repo_ids.last.to_s, expires: PROCESSING_INTERVAL.from_now)
    end
  end

  # Get the batch of repository IDs to process.
  def get_repo_ids_to_process
    # The last repository ID processed should be stored in KV.
    # If the value isn't in KV then start from 0.
    last_repo_id_processed = CodeScanning::KV.store.get(LAST_REPO_ID_PROCESSED_KV_KEY).value { 0 }.to_i

    repo_ids_batch = get_repo_ids_batch(last_repo_id_processed, num_repo_ids_to_process)
    return repo_ids_batch unless repo_ids_batch.empty?

    # If we don't find any repo IDs to process it may be we've reached the highest
    # ID value, so try again but start from the beginning.
    get_repo_ids_batch(0, num_repo_ids_to_process)
  end

  # Get a batch of repository IDs.
  # Returns an array of up to the given number of repository IDs,
  # in ascending order, starting at the min repo ID given.
  def get_repo_ids_batch(min_repo_id, num_repo_ids)
    CodeqlDatabase.where("repository_id > ?", min_repo_id)
      .group(:repository_id)
      .order(repository_id: :asc)
      .limit(num_repo_ids)
      .pluck(:repository_id)
  end

  # Returns how many repo IDs should be processed.
  # Is computed from the total number of unique IDs.
  def num_repo_ids_to_process
    @num_repo_ids_to_process ||= (1.0 * num_unique_repo_ids / (PROCESSING_INTERVAL / SCHEDULE_INTERVAL)).ceil
  end

  # Returns the number of unique repository IDs referenced by currently existing CodeQL databases.
  # Although this method is very simple, it is defined as a separate method so we can easily
  # override it in tests to avoid having to create lots of test repos.
  def num_unique_repo_ids
    @num_unique_repo_ids ||= CodeqlDatabase.select(:repository_id).distinct.count
  end
end
