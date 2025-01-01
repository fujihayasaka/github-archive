# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class LdapTeamSyncJob < ApplicationJob
  queue_as :ldap_team_sync

  schedule interval: GitHub.ldap_team_sync_interval.hours, condition: -> {
    LdapTeamSyncJob.enabled?
  }
  # This timeout is the amount of time that the lock will be kept
  # whether the job completes or not. It is set to a very long
  # value (2 days) to assure that jobs don't stack up under normal
  # circumstances.
  locked_by timeout: 48.hours + 1.minute, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  def self.enabled?
    GitHub.enterprise? && GitHub.ldap_sync_enabled?
  end

  # Public: Sync given team by `team_id` or all teams if no id specified.
  #
  # NOTE: Updates all Teams that map to the same DN.
  #
  # Emits `ldap_team_sync.perform` event with:
  #  :count - number of teams synced
  def perform(team_id = nil)
    return unless LdapTeamSyncJob.enabled?

    sync = GitHub::LDAP::TeamSync.new
    iterator =
      if team_id
        LdapMapping.where(subject_type: "Team", subject_id: team_id)
      else
        # Find LdapMapping records with unique Distinguished Name (DN)
        # values. Wrap the ActiveRecord scope with an `Enumerator` object
        # so when `each` is called it'll perform finds in batches.
        LdapMapping.where(subject_type: "Team").
          select("DISTINCT(dn)").select(:id).enum_for(:find_each)
      end

    GitHub.instrument "ldap_team_sync.perform", count: 0 do |payload|
      iterator.group_by(&:dn).each_key do |dn|
        with_write { sync.perform(dn) }
        payload[:count] += 1
      end
    end
  end
end
