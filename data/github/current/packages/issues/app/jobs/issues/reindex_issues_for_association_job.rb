# typed: true
# frozen_string_literal: true

module Issues
  class ReindexIssuesForAssociationJob < BatchedJob
    queue_as :index_high

    retry_on_dirty_exit
    retry_on_recoverable_exceptions
    # This configuration mirrors that of AddToSearchIndexJob
    retry_on GitHub::Restraint::UnableToLock, wait: :polynomially_longer, attempts: 20

    # How many concurrent jobs with the same key are allowed. Since this is
    # indexing content, only one at a time per document, please:
    RUNNING_JOBS_PER_KEY = 1

    # How long a running (or crashed) job is allowed to hold onto a lock, in
    # seconds, before it expires and another one takes over.
    JOB_LOCK_TTL = 5.minutes

    # Should be used to enqueue the job instead of perform_later directly
    def self.enqueue(association, id, options = {})
      perform_later(
        association_name: association,
        association_id: id,
        submitted_at: Timestamp.from_time(Time.now.utc),
        sharding_key: options[:sharding_key],
        sharding_key_value: options[:sharding_key_value],
      )
    end

    def next_batch(association_name:, association_id:, submitted_at:, timestamp: Time.now.utc, offset_item_id: 0, **options)
      restraint.lock!(restraint_lock_key, RUNNING_JOBS_PER_KEY, JOB_LOCK_TTL) do
        # Wait for the read replica for the association to receive the update before triggering indexing
        # We cannot declare via use_replicas because the cluster is dependent on the association enqueued
        WaitForReplication.new(
          submitted_at,
          store_name: association.klass.cluster_name,
          # See SmartDatabaseSelection for the default retry configuration for all ApplicationJobs
          max_wait_seconds: MAX_REPLICATION_DELAY_WAIT_SECONDS,
        ).wait!

        ids = if association.through_reflection?
          sql_bindings = {
            table: Arel.sql(association.through_reflection.klass.table_name),
            foreign_key: Arel.sql(association.foreign_key),
            issue_key: Arel.sql(association.through_reflection.foreign_key),
            sharding_key: sharding_key ? Arel.sql(sharding_key.to_s) : nil,
            sharding_key_value: sharding_key_value,
            association_id: association_id,
            last_seen: offset_item_id,
            count: Arel.sql(BATCH_SIZE.to_s),
          }

          sql = Arel.sql <<-SQL, **sql_bindings
            SELECT :issue_key from :table
            WHERE :foreign_key = :association_id
            AND :issue_key > :last_seen
          SQL

          if sharding_key && sharding_key_value
            sql += Arel.sql <<-SQL, **sql_bindings
              AND :sharding_key = :sharding_key_value
            SQL
          end

          sql += Arel.sql <<-SQL, **sql_bindings
            ORDER BY id
            LIMIT :count
          SQL

          association.through_reflection.klass.connection.select_values(sql)
        else
          sql_bindings = {
            table: Arel.sql(Issue.table_name),
            foreign_key: Arel.sql(association.foreign_key),
            association_id: association_id,
            sharding_key: sharding_key ? Arel.sql(sharding_key.to_s) : nil,
            sharding_key_value: sharding_key_value,
            last_seen: offset_item_id,
            count: Arel.sql(BATCH_SIZE.to_s),
          }

          sql = Arel.sql <<-SQL, **sql_bindings
            SELECT id from :table
            WHERE :foreign_key = :association_id
            AND id > :last_seen
          SQL

          if sharding_key && sharding_key_value
            sql += Arel.sql <<-SQL, **sql_bindings
              AND :sharding_key = :sharding_key_value
            SQL
          end

          sql += Arel.sql <<-SQL, **sql_bindings
            ORDER BY id
            LIMIT :count
          SQL

          Issue.connection.select_values(sql)
        end

        return Issue.none if ids.empty?

        Issue.where(id: ids)
      end
    end

    def process_batch(issues, *args, **options)
      issues.each(&:synchronize_search_index)
    end

    private

    def association_name
      options = arguments[0] || {}
      options[:association_name]
    end

    def association_id
      options = arguments[0] || {}
      options[:association_id]
    end

    def sharding_key
      options = arguments[0] || {}
      options[:sharding_key]
    end

    def sharding_key_value
      options = arguments[0] || {}
      options[:sharding_key_value]
    end

    # Returns the AssociationReflection for the association triggering indexing
    def association
      # For some security, use reflection to retrieve the table name rather than
      # relying on user input in the job arguments.
      Issue.reflect_on_association(association_name)
    end

    def restraint_lock_key
      "add_issues_to_search_index_restraint_#{association_name}_#{association_id}"
    end

    def restraint
      @restraint ||= GitHub::Restraint.new
    end
  end
end
