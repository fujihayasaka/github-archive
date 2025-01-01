# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class GitbackupsEnsureFreshKeyJob < ApplicationJob
  queue_as :gitbackups_encryption

  schedule interval: 1.hour, condition: -> { GitHub.realtime_backups_enabled? }

  exempt_from_tenant_context_requirement

  def perform
    Failbot.push app: "gitbackups"

    GitHub::Backups.ensure_fresh_key
  end
end
