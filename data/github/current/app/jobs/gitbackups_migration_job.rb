# typed: true
# frozen_string_literal: true

class GitbackupsMigrationJob < GitbackupsMaintenanceJob
  queue_as :gitbackups_migration
end
