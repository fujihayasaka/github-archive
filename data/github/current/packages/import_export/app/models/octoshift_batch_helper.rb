# typed: true
# frozen_string_literal: true

class OctoshiftBatchHelper

  class TargetRepoState

    STORAGE_KEY_PREFIX = "TargetRepoBatchedMigrationState"

    attr_reader :current_octoshift_migration_id, :current_cursor, :storage_key

    def initialize(storage_key, current_octoshift_migration_id, current_cursor)
      @storage_key = storage_key
      @current_octoshift_migration_id = current_octoshift_migration_id
      @current_cursor = current_cursor.to_i
    end

    def self.fetch(repo_nwo)
      storage_key = "#{STORAGE_KEY_PREFIX}-#{repo_nwo.parameterize}"
      value = GitHub::Migrator::KV.store.get(storage_key).value { nil } || "{}"
      parsed = JSON.parse(value)
      new(
        storage_key,
        parsed.fetch("current_octoshift_migration_id", nil),
        parsed.fetch("current_cursor", 0)
      )
    end

    def set_current_octoshift_migration_id(migration_guid)
      @current_octoshift_migration_id = migration_guid
      save
    end

    def set_current_cursor(cursor)
      @current_cursor = cursor
      save
    end

    def save
      ActiveRecord::Base.connected_to(role: :writing) do
        data = {
          current_octoshift_migration_id: current_octoshift_migration_id,
          current_cursor: current_cursor
        }.to_json
        GitHub::Migrator::KV.store.set(storage_key, data)
      end
    end
  end

  class MigrationState

    STORAGE_KEY_PREFIX = "MigrationState"

    attr_reader :octoshift_repo_migration_id, :target_repo_nwo, :source_repo_url, :current_cursor, :next_cursor, :storage_key

    def initialize(storage_key, target_repo_nwo, source_repo_url, current_cursor, next_cursor)
      @storage_key = storage_key
      @target_repo_nwo = target_repo_nwo
      @source_repo_url = source_repo_url
      @current_cursor = current_cursor.to_i
      @next_cursor = next_cursor.to_i
    end

    def self.create(octoshift_repo_migration_id, target_repo_nwo, source_repo_url, current_cursor)
      storage_key = "#{STORAGE_KEY_PREFIX}-#{octoshift_repo_migration_id}"
      new(storage_key, target_repo_nwo, source_repo_url, current_cursor, nil).tap(&:save)
    end

    def self.fetch(octoshift_repo_migration_id)
      storage_key = "#{STORAGE_KEY_PREFIX}-#{octoshift_repo_migration_id}"
      value = GitHub::Migrator::KV.store.get(storage_key).value { nil } || "{}"
      parsed = JSON.parse(value)
      new(
        storage_key,
        parsed.fetch("target_repo_nwo", nil),
        parsed.fetch("source_repo_url", nil),
        parsed.fetch("current_cursor", 0).to_i,
        parsed.fetch("next_cursor", 0).to_i
      )
    end

    def self.fetch_from_migration_guid(migration_guid)
      MigrationExportLink.fetch(migration_guid).then do |octoshift_migration_id|
        fetch(octoshift_migration_id)
      end
    end

    def set_next_cursor(next_cursor)
      @next_cursor = next_cursor
      save
    end

    def save
      ActiveRecord::Base.connected_to(role: :writing) do
        data = {
          target_repo_nwo: target_repo_nwo,
          source_repo_url: source_repo_url,
          current_cursor: current_cursor,
          next_cursor: next_cursor
        }.to_json
        GitHub::Migrator::KV.store.set(storage_key, data)
      end
    end
  end

  class MigrationExportLink
    STORAGE_KEY_PREFIX = "MigrationExportLink"

    def self.fetch(migration_guid)
      storage_key = "#{STORAGE_KEY_PREFIX}-#{migration_guid}"
      GitHub::Migrator::KV.store.get(storage_key).value { nil }
    end

    def self.create(migration_guid, octoshift_migration_id)
      storage_key = "#{STORAGE_KEY_PREFIX}-#{migration_guid}"
      GitHub::Migrator::KV.store.set(storage_key, octoshift_migration_id)
    end
  end
end
