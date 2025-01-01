# typed: true
# frozen_string_literal: true

require "logger"
require "github/pages/management"

module GitHub::Pages::Management

  REPLICA_QUERY_SIZE = 50

  MAX_THROTTLE_RETRIES = 5

  # The is a command run manually to initiate the migration job
  class MigrateHost

    def initialize(delegate:, source_host:, start_replica_id: nil)
      @delegate = delegate
      @source_host = source_host
      @start_replica_id = start_replica_id || 0
      nil
    end

    def perform
      while true
        @delegate.log "Migrating pages from #{@source_host} start with replica id #{@start_replica_id}"
        binds = {
          source_host: @source_host,
          size: Arel.sql(REPLICA_QUERY_SIZE.to_s),
          start_replica_id: @start_replica_id
        }

        # query pages_replicas table find the replica not migrated
        results = ApplicationRecord::Domain::Repositories.connection.select_rows(Arel.sql(<<-SQL, **binds))
          SELECT r.id, r.page_id, r.pages_deployment_id
          FROM pages_replicas r
          LEFT JOIN pages_migrations m ON r.page_id = m.page_id AND r.pages_deployment_id = m.page_deployment_id
          WHERE r.id > :start_replica_id
          AND r.host = :source_host
          AND m.page_id IS NULL
          ORDER BY r.id asc
          LIMIT :size
        SQL

        if results.empty?
          @delegate.log "No more pages to migrate from #{@source_host}"
          return true
        end

        # create pages_migrations records
        rows = results.map do |replica|
          page_deployment_id = replica[2].present? ? replica[2] : 0
          { page_id: replica[1], page_deployment_id: page_deployment_id, created_at: GitHub::SQL::ArelLiterals::NOW, updated_at: GitHub::SQL::ArelLiterals::NOW, status: :created }
        end

        Page::PagesMigrations.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES, skip_reporting: true) do
          ActiveRecord::Base.connected_to(role: :writing) do
            Page::PagesMigrations.insert_all(rows)
          end
        end
        @start_replica_id = results.last[0]
      end
    end

    def reset_migration(batch_size = 500)
      updated_total = 0
      last_created_migration_id = Page::PagesMigrations.where(status: :created).last&.id || 0
      while true
        Page::PagesMigrations.throttle_writes_with_retry do
          updated_count = Page::PagesMigrations.where(status: :running)
            .where("updated_at <= ?", Time.now - 2.hours)
            .where("id > ?", last_created_migration_id)
            .order(created_at: :asc)
            .limit(batch_size)
            .update_all(status: :created)
          updated_total += updated_count
          @delegate.log " Reseted #{updated_total} running migrations to created status"
          return updated_total if updated_count < batch_size
          last_created_migration_id = Page::PagesMigrations.where(status: :created).last&.id || 0
          sleep 1
        end
      end
    end
  end
end
