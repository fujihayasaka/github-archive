# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class GitbackupsWalJob < ApplicationJob
  queue_as :gitbackups_wal

  schedule interval: 1.hour, condition: -> { GitHub.enterprise? && GitHub.realtime_backups_enabled? }

  # This covers uploading the file, and for incrementals also creating the
  # packfile. Uploading large bases can take hours and we currently upload to
  # two places. Having too small a timeout here can lead to undetected data loss.
  WAL_GRACE_PERIOD = "12h"

  def perform
    Failbot.push(app: "gitbackups")

    GitHub::Backups.garbage_collect_wal(WAL_GRACE_PERIOD)
  end
end
