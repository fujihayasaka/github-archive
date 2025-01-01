# typed: true
# frozen_string_literal: true

class GitbackupsMaintenanceJob < ApplicationJob
  queue_as :gitbackups_maintenance

  retry_on GitHub::Restraint::UnableToLock, wait: 5.minutes, attempts: 10

  exempt_from_tenant_context_requirement

  # Run every interval.
  def perform(spec, opts: {})
    Failbot.push app: "gitbackups"

    # parallel maintenance for the same repo should not be allowed, but stil
    # allow jobs to be enqueued
    restraint = GitHub::Restraint.new
    restraint.lock!(spec, 1, 24.hours) do
      GitHub::Backups.maintenance(spec, opts: opts)
    end
  end
end
