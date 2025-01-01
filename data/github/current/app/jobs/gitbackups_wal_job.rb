# typed: true
# frozen_string_literal: true

class GitbackupsWalJob < ApplicationJob
  queue_as :gitbackups_wal

  schedule interval: 1.hour, condition: -> { GitHub.enterprise? && GitHub.realtime_backups_enabled? }

  # This covers uploading the file, and for incrementals also creating the
  # packfile. Even when we upload gigabytes, we don't expect to take more
  # than a few minutes.
  WAL_GRACE_PERIOD = "4h"

  def perform
    Failbot.push(app: "gitbackups")

    GitHub::Backups.garbage_collect_wal(WAL_GRACE_PERIOD)
  end
end
