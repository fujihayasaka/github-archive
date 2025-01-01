# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class RepairAbilitiesFromUsersToAncestorTeamsJob < ApplicationJob
  queue_as :repair_abilities_from_users_to_ancestor_teams

  locked_by key: ->(job) { job.class.lock(*job.arguments) }, timeout: ActiveJob::LockingJob::DEFAULT_LOCK_TIMEOUT

  retry_on StandardError

  # Only a single unique instance of the job can be concurrently running
  # per organization
  def self.lock(org_id, options = {})
    org_id
  end

  def perform(org_id, options = {})
    with_write { Team::ParentChange::RepairAbilitiesOperation.new(org_id, options).execute }
  end
end
