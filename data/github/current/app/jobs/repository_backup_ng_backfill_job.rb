# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class RepositoryBackupNgBackfillJob < RepositoryBackupNgJob
  # We use the different queue in order not to block the backups from new
  # activity, but it's otherwise the same job.
  queue_as :gitbackups_backfill
end
