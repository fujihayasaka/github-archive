# typed: true
# frozen_string_literal: true

module Octoshift
  class RepositoryMigration
    include GitHub::Relay::GlobalIdentification
    extend Forwardable

    attr_reader :migration_source

    def_delegators :@migration, :id, :repository_name, :source_url, :failure_reason, :continue_on_error,
      :warnings_count, :migration_log_url

    def_delegator :@migration, :migration_state, :state
    def_delegator :@migration, :id, :database_id

    def initialize(migration, source)
      @migration = migration
      @migration_source = source
    end

    def async_migration_source
      Promise.resolve(migration_source)
    end

    def platform_type_name
      "RepositoryMigration"
    end

    def created_at
      @migration.created_at.to_time
    end

    def ==(other)
      self.class == other.class &&
        id == other.id && migration_source == other.migration_source
    end
  end
end
