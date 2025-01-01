# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# This job scans for externally managed EMU teams that have a mismatch between the external_group members and the team members.
# If mismatched teams are found, the job will notify the external-identities team on slack and kick off an ExternalGroupTeamReconcileJob for each team.
# This job repeats every day (frequency TBD).
class ScanEmuExternalTeamsJob < ApplicationJob
  include ChecksJobUtility

  BATCH_SIZE = 10
  INTERVAL_OFFSET = 3

  queue_as :scan_emu_external_teams

  # This job's original start time is 6:30AM PST / 9:30AM EST / 14:30 UTC every day
  schedule interval: 12.hours, condition: -> { !GitHub.enterprise? }

  retry_on_dirty_exit

  exempt_from_tenant_context_requirement

  def perform
    # Runs only during off-peak traffic times to reduce DB load
    return if peak_traffic_time?

    interval = 0
    interval, external_group_teams_for_reconcile = perform_external_group_team_reconcile(interval)
    external_group_teams_for_deletion = perform_external_group_team_delete(interval)

    external_group_teams_to_skip = [*external_group_teams_for_reconcile, *external_group_teams_for_deletion]

    check_all_out_of_sync_external_group_teams(external_group_teams_to_skip)
  end

  private

  def perform_external_group_team_reconcile(interval)
    external_group_team = ExternalGroupTeam.joins(:team).pluck(:id, :external_group_id, :team_id).to_h { |id, external_group_id, team_id| [id, { external_group_id: external_group_id, team_id: team_id }] }

    external_group_no_members = ExternalIdentityGroupMembership.joins(:external_group).
      where.not(external_group: { deleted_at: nil }).group(:external_group_id).count

    # get all external group ids and batch selects for counts
    external_group_ids = ExternalGroup.all.pluck(:id)
    external_group_counts = {}
    external_group_ids.each_slice(5000) do |ids|
      external_group_counts.merge!(ExternalIdentityGroupMembership.joins(:external_identity).
        where(external_group_id: ids).where(external_identity: { disabled_at: nil }).group(:external_group_id).count)
    end
    external_group_no_members.each { |external_group_id, _count| external_group_counts[external_group_id] = 0 }

    team_ids = external_group_team.values.map { |val| val[:team_id] }.uniq

    team_counts = {}
    team_ids.each_slice(5000) { |ids| team_counts.merge!(Ability.where(subject_id: ids, subject_type: "Team", actor_type: "User", priority: Ability.priorities[:direct]).group(:subject_id).count("DISTINCT actor_id")) }
    mismatched_team_ids = external_group_team.reject { |_id, val| !team_counts.has_key?(val[:team_id]) && external_group_counts[val[:external_group_id]] == 0 || external_group_counts[val[:external_group_id]] == team_counts[val[:team_id]] }.keys

    mismatched_teams = ExternalGroupTeam.where(id: mismatched_team_ids)

    message = if mismatched_teams.empty?
      "No mismatched externally managed EMU teams found today!"
    else
      "Mismatched externally managed EMU teams found. See dashboard https://splunk.githubapp.com/en-US/app/github_identity/external_group_team"
    end
    GitHub::Chatterbox.client.say!("#external-identities-ops", message) unless GitHub.enterprise?

    businesses_available_licenses = businesses_available_licenses(external_group_teams: mismatched_teams)

    mismatched_teams.each_slice(BATCH_SIZE) do |egts|
      egts.each do |egt|
        # Skip teams that don't belong to an organization
        # All EMU teams should belong to an organization
        next unless egt.team&.organization

        instrument_mismatch_event(external_group_team: egt, businesses_available_licenses: businesses_available_licenses)

        ExternalGroupTeamReconcileJob.set(wait: interval.minutes).perform_later(external_group_id: egt.external_group_id, team_id: egt.team_id, caller: self.class.name)
      end

      interval += INTERVAL_OFFSET
    end

    [interval, mismatched_teams]
  end

  def perform_external_group_team_delete(interval)
    external_group_teams = ExternalGroupTeam.left_joins(:team).where(team: { id: nil })

    businesses_available_licenses = businesses_available_licenses(external_group_teams: external_group_teams)

    external_group_teams.each_slice(BATCH_SIZE) do |egts|
      egts.each do |egt|
        instrument_delete_event(external_group_team: egt, businesses_available_licenses: businesses_available_licenses)

        ExternalGroupTeamReconcileJob.set(wait: interval.minutes).perform_later(external_group_id: egt.external_group_id, team_id: egt.team_id, caller: self.class.name)
      end

      interval += INTERVAL_OFFSET
    end

    external_group_teams
  end

  def check_all_out_of_sync_external_group_teams(external_group_teams_to_skip)
    ExternalGroupTeam.where.not(sync_status: :in_sync).where.not(id: external_group_teams_to_skip.pluck(:id)).each do |external_group_team|
      external_group_team.update_sync_status
    end
  end

  def instrument_mismatch_event(external_group_team:, businesses_available_licenses:)
    external_group = external_group_team.external_group
    team = external_group_team.team
    business = external_group&.provider&.business
    organization = team&.organization
    business ||= organization&.business
    GitHub.logger.info(
      "info.message" =>  "Mismatched EMU External Group Team",
      "code.namespace" => self.class.name,
      "code.function" => "perform",
      "gh.business.slug" => business&.slug,
      "gh.business.id" => business&.id,
      "gh.organization.name" => organization&.name,
      "gh.organization.id" => organization&.id,
      "gh.external_group.name" => external_group&.display_name,
      "gh.external_group.id" => external_group&.id,
      "gh.team.name" => team&.name,
      "gh.team.id" => team&.id,
      "gh.external_group_team.id" => external_group_team.id,
      "gh.external_group.size" => external_group&.active_user_ids.count,
      "gh.team.size" => team&.member_ids.count,
      "gh.business.available_licenses" => businesses_available_licenses[business&.id],
    )
  end

  def instrument_delete_event(external_group_team:, businesses_available_licenses:)
    external_group = external_group_team.external_group
    business = external_group&.provider&.business
    business ||= external_group_team.team&.organization&.business
    GitHub.logger.info(
      "info.message" => "Orphaned EMU External Group Team",
      "code.namespace" => self.class.name,
      "code.function" => "perform",
      "gh.business.slug" => business&.slug,
      "gh.business.id" => business&.id,
      "gh.external_group.name" => external_group&.display_name,
      "gh.external_group.id" => external_group&.id,
      "gh.external_group.size" => external_group&.active_user_ids.count,
      "gh.external_group_team.id" => external_group_team.id,
      "gh.team.id" => external_group_team.team_id,
      "gh.business.available_licenses" => businesses_available_licenses[business&.id],
    )
  end

  def businesses_available_licenses(external_group_teams:)
    businesses_available_licenses = {}
    external_group_teams.each do |egt|
      business = egt.external_group&.provider&.business
      business ||= egt.team&.organization&.business
      next unless business
      businesses_available_licenses[business.id] ||= business.available_invitable_licenses
    end
    businesses_available_licenses
  end
end
