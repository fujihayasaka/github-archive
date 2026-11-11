# typed: strict
# frozen_string_literal: true

class CommitContribution
  # Inner class to handle batch writing of commit contribution records
  class BatchWriter
    RowType = T.type_alias { [Integer, Integer, Date, Integer, Arel::Nodes::SqlLiteral, Arel::Nodes::SqlLiteral] }

    USER_ID_IDX = 0
    REPO_ID_IDX = 1
    COMMITTED_DATE_IDX = 2
    COMMIT_COUNT_IDX = 3
    CREATED_AT_IDX = 4
    UPDATED_AT_IDX = 5

    BATCH_SIZE = 20
    MAX_RETRIES = 5
    MAX_WAIT_SECONDS = 5

    DOGSTATS_PREFIX = "commit_contributions.track_push."

    class PartialDeleteError < StandardError; end

    # Public: Convenience method to create an instance and call it.

    # Insert commit contribution records in batches
    #
    # rows - Array of arrays representing commit contribution data in format:
    #        [user_id, repository_id, committed_date, commit_count, created_at, updated_at]
    #
    # Returns Integer count of rows processed
    sig { params(rows: T::Array[RowType]).returns(Integer) }
    def self.call(rows:)
      new(rows: rows).call
    end

    sig { params(rows: T::Array[RowType]).void }
    def initialize(rows:)
      @rows = rows

      @deleted_count = T.let(0, Integer)
      @inserted_count = T.let(0, Integer)

      @before_delete = T.let(->() {}, T.proc.void)
      @before_insert = T.let(->() {}, T.proc.void)
    end

    sig { returns(Integer) }
    def call
      rows.each_slice(BATCH_SIZE) do |batch|
        delete_then_insert_batch(batch: batch)
      end

      @inserted_count
    end

    # Install a callback to be invoked just before deleting existing contributions in each batch. This is used
    # for testing.
    sig { params(block: T.proc.void).void }
    def before_delete_hook(&block)
      @before_delete = block
    end

    # Install a callback to be invoked just before inserting new contributions in each batch. This is used for
    # testing.
    sig { params(block: T.proc.void).void }
    def before_insert_hook(&block)
      @before_insert = block
    end

    private

    sig { params(batch: T::Array[RowType]).void }
    def delete_then_insert_batch(batch:)
      retry_count = 0
      while retry_count < MAX_RETRIES
        # Load any existing rows that correspond to the batch we'd like to insert.
        relation = batch.inject(CommitContribution.none) do |scope, row|
          scope.or(CommitContribution.where(
            user_id: row[USER_ID_IDX],
            repository_id: row[REPO_ID_IDX],
            committed_date: row[COMMITTED_DATE_IDX],
          ))
        end
        existing_rows = ActiveRecord::Base.connected_to(role: :reading) do
          relation.limit(batch.size).index_by do |contribution|
            [contribution.user_id, contribution.repository_id, contribution.committed_date]
          end
        end

        begin
          if existing_rows.any?
            deletion_relation = existing_rows.values.inject(CommitContribution.none) do |scope, contribution|
              scope.or(CommitContribution.where(id: contribution.id, commit_count: contribution.commit_count))
            end

            @before_delete.call
            batch_deletion_count = CommitContribution.throttle_writes do
              # Use a transaction here so we don't successfully delete some of the existing rows but not others and
              # lose data. requires_new: true emulates nested transactions with savepoints if necessary (like in
              # tests).
              CommitContribution.transaction(requires_new: true) do
                rows_deleted = deletion_relation.limit(existing_rows.size).delete_all
                if rows_deleted < existing_rows.size
                  # Race condition: some of the rows we fetched just above were deleted by another process in the
                  # interim. We can't continue here because we may end up double-counting commits. Abort the
                  # transaction and retry the whole batch instead so we also redo the SELECT again.
                  raise PartialDeleteError
                end
                rows_deleted
              end
            end
            @deleted_count += batch_deletion_count
          end

          attributes = batch.map do |row|
            existing = existing_rows[[row[USER_ID_IDX], row[REPO_ID_IDX], row[COMMITTED_DATE_IDX]]]

            {
              user_id: row[USER_ID_IDX],
              repository_id: row[REPO_ID_IDX],
              committed_date: row[COMMITTED_DATE_IDX],
              commit_count: row.fetch(COMMIT_COUNT_IDX, 0) + (existing&.commit_count || 0),
              created_at: row[CREATED_AT_IDX],
              updated_at: row[UPDATED_AT_IDX],
            }
          end

          @before_insert.call
          CommitContribution.throttle_writes do
            CommitContribution.insert_all!(attributes)
          end
          @inserted_count += attributes.size

          dogstats_count("rows_deleted", @deleted_count)
          dogstats_count("rows_inserted", @inserted_count)
          dogstats_distribution("retries", retry_count)
          return
        rescue ActiveRecord::RecordNotUnique, PartialDeleteError => e
          retry_count += 1
          if retry_count >= MAX_RETRIES
            # This will inherit the gh.repo.id tag from its caller, so we can reindex contributions for that repo
            # manually if necessary.
            GitHub.logger.error("Exhausted #{MAX_RETRIES} retries writing CommitContribution batch.", e)
            raise
          else
            # Give the replicas a chance to receive the writes that caused the conflict before we try the SELECT
            # again.
            wait_for_replication!
          end
        end
      end
    end

    sig { returns(T::Array[RowType]) }
    attr_reader :rows

    sig { params(metric: String, value: Numeric).void }
    def dogstats_count(metric, value = 1)
      GitHub.dogstats.count("#{DOGSTATS_PREFIX}#{metric}", value)
    end

    sig { params(metric: String, value: Numeric).void }
    def dogstats_distribution(metric, value)
      GitHub.dogstats.distribution("#{DOGSTATS_PREFIX}#{metric}", value)
    end

    sig { void }
    def wait_for_replication!
      WaitForReplication.new(
        { CommitContribution.cluster_name => { time: Timestamp.from_time(Time.current) } },
        max_wait_seconds: MAX_WAIT_SECONDS,
      ).wait!
    end
  end
end
