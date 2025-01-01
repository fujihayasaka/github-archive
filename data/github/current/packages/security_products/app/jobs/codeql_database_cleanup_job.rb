# typed: true
# frozen_string_literal: true

# CodeqlDatabaseCleanupJob finds and deletes any CodeQL databases can or should be deleted.
#
# It is triggered on a single repository at a time in response to certain events:
# - when a new database is uploaded
# - when the repository changes visibility from public to private
# - when the repository is deleted
#
# This job is also triggered on a schedule by CodeqlDatabaseCleanupSchedulerJob which ensures
# that this job runs at least once in a defined period for all repos with uploaded databases.
#
# Uses a lock to ensure that only one instance of this job is running at a time.
class CodeqlDatabaseCleanupJob < ApplicationJob
  queue_as :code_scanning_multi_repository_variant_analysis

  retry_on_dirty_exit

  # If two jobs on the same repo conflict we generally don't care.
  # This job is triggered frequently enough that another job will run
  # and handle any new state.
  discard_on GitHub::Restraint::UnableToLock

  # How long should we wait before we consider a lock to be invalid because
  # the job holding it has probably died / stopped running.
  LOCK_TIME_LIMIT = 6.hours

  # How many databases to fetch in each query.
  LIMIT_PER_QUERY = 100

  # repository_id - Repository to act upon.
  def perform(repository_id:)
    return if GitHub.enterprise?

    lock! do
      loop do
        db = next_database
        break if db.nil?

        # Delete the databases one by one because it also triggers deleting the blob in azure.
        # Must use "destroy" instead of "delete" in order to trigger the "before_destroy" callback.
        ActiveRecord::Base.connected_to(role: :writing) do
          CodeqlDatabase.throttle do
            db.destroy!
          end
        end
        GitHub.dogstats.increment("code_scanning.codeql_database.deleted")
      end
    end
  rescue Storage::Uploadable::DeletionError => e
    handle_deletion_error(e)
  end

  private

  def repository_id
    arguments.first[:repository_id]
  end

  # Obtain lock for this job running on this repository ID.
  def lock!
    restraint = GitHub::Restraint.new
    lock_key = "#{self.class.name}:#{repository_id}"
    max_concurrent_jobs = 1
    lock_ttl = LOCK_TIME_LIMIT
    restraint.lock!(lock_key, max_concurrent_jobs, lock_ttl) do
      yield
    end
  end

  # Returns the next database to delete.
  # Caches a list internally and queries for more when needed.
  # Returns nil when there are no more databases to delete.
  def next_database
    @databases_to_delete ||= []
    @sources ||= database_sources

    while @databases_to_delete.empty? && @sources.any?
      @databases_to_delete += @sources[0].call
      @sources.shift if @databases_to_delete.empty?
    end

    @databases_to_delete.shift
  end

  # Returns an array of closures with the signature () => [CodeqlDatabase].
  # Each closure returns a different category of databases to delete.
  def database_sources
    sources = []

    repository = Repository.find_by(id: repository_id)

    # note that "!active?" means it is hidden and is in the process of being deleted.
    repo_is_deleted = repository.nil? || !repository.active?
    sources.push(proc { all_uploaded_databases }) if repo_is_deleted

    repo_is_private = repository.present? && repository.private?
    sources.push(proc { all_bulk_built_databases }) if repo_is_private

    sources.push(proc { invalid_databases })
    sources.push(proc { superseded_databases })

    sources
  end

  # Find all databases that are in the uploaded state. Should be used when you
  # want to delete all databases for a repository.
  #
  # We ignore databases that are not in the uploaded state to avoid touching databases
  # that are in the process of being uploaded currently. Deleting those records could lead to us
  # losing track of the azure blob. Also note that a cleanup job will be triggered when the upload
  # of these databases completes. When combined with the "invalid_databases" method this should
  # allow finding all databases with high-enough certainty.
  def all_uploaded_databases
    CodeqlDatabase.where(repository_id: repository_id, state: :uploaded)
      .limit(LIMIT_PER_QUERY)
      .to_a
  end

  # Find all databases that are built by the bulk builder. For a database that was previously
  # public but is now private, we will want to delete any databases that were built by the bulk
  # builder without the involvement of the repository owners.
  #
  # Returns the empty array if there is no code scanning bot, which should indicate there are
  # no bulk built databases to delete.
  def all_bulk_built_databases
    # If we're unable to find the ID of the code scanning bot, default to not deleting any databases
    # but also crucially not throwing any errors. This should be safer in production and is also
    # useful during tests as we don't need to set up the code scanning integration as often.
    @code_scanning_bot_id ||= Apps::Privileged.integration(:code_scanning)&.bot&.id
    return [] if @code_scanning_bot_id.nil?

    CodeqlDatabase.where(repository_id: repository_id, state: :uploaded, uploader_id: @code_scanning_bot_id)
      .limit(LIMIT_PER_QUERY)
      .to_a
  end

  # Find databases that are older than the upload timeout but are not in the "uploaded" state.
  # This implies that something went wrong with the upload process. The PATCH endpoint should now
  # disallow modifying these databases, and hence it should be safe to get rid of them.
  def invalid_databases
    CodeqlDatabase.where(repository_id: repository_id)
      .where.not(state: :uploaded)
      .where("created_at < ?", CodeqlDatabase::UPLOAD_TIMEOUT.ago)
      .order(created_at: :asc)
      .limit(LIMIT_PER_QUERY)
      .to_a
  end

  # Find databases that have been superseded by a newer database.
  # These databases should be essentially invisible to the user now because all operations
  # use the latest database, so the old databases can be deleted.
  #
  # Repositories should still be kept long enough that any signed URLs remain valid.
  # This is implemented by finding the latest database for each language that is at least as old
  # as the signed URL timeout. This database could still have a signed URL that is valid because
  # the next newest database after it is newer than the signed URL timeout. But anything that's
  # older than this database can be deleted as any signed URL will have expired.
  def superseded_databases
    conditions = CodeqlDatabase.latest_for_repo(repository_id, min_age: CodeqlDatabase::STORAGE_DOWNLOAD_EXPIRATION)
      .map do |db|
        CodeqlDatabase.arel_table[:language].eq(db.language)
          .and(CodeqlDatabase.arel_table[:created_at].lteq(db.created_at))
          .and(CodeqlDatabase.arel_table[:id].lt(db.id))
      end
      .reduce { |all_conditions, condition| all_conditions.or(condition) }

    return [] if conditions.nil?

    CodeqlDatabase.where(repository_id: repository_id, state: :uploaded)
      .where(conditions)
      .order(created_at: :asc)
      .limit(LIMIT_PER_QUERY)
      .to_a
  end

  def handle_deletion_error(err)
    Failbot.report(err, "gh.repo.id": repository_id)
    GitHub.dogstats.increment("code_scanning.codeql_database.failed_deletion")
  end
end
