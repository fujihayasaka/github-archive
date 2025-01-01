# typed: true
# frozen_string_literal: true

class ExternalGroupTeamUnlinkJob < ApplicationJob
  default_to_write_connection! # rubocop:todo GitHub/JobsDoNotDefaultToWriteConnection

  queue_as :external_group_team_unlink
  retry_on_dirty_exit

  def perform(team_id, external_group_id, caller:)
    team = Team.find_by(id: team_id)
    external_group = ExternalGroup.find_by(id: external_group_id)

    # If this job is executed from ExternalGroupTeam and external_group has already been deleted
    # still need to perform the unlink operation
    if external_group.nil? && caller == ExternalGroupTeam.name
      unless team
        GitHub.dogstats.increment("external_identities.external_group_team_unlink_job.no_team")
        return
      end

      business = team.organization&.business
    else
      unless team && external_group
        GitHub.dogstats.increment("external_identities.external_group_team_unlink_job.no_external_group_and_team")
        return
      end

      business = external_group.provider&.business
    end

    GitHub.logger.info(
      "info.message" => "Starting external_group_team_unlink job",
      "gh.business.id" => business&.id,
      "gh.caller" => caller,
      "gh.business.slug" => business&.slug,
    )

    # Removing an external-group-team will remove all members from the team without deleting the team,
    # External group members will not be impacted by this operation.
    ExternalGroupTeam.remove_all_team_members_from_team(team)

    if team.members.present?
      GitHub.dogstats.increment("external_identities.external_group_team_unlink_job.external_group_team_unlink_failed")
      GitHub.logger.error({ "exception.message" => "Team membership deletion failed", "gh.business.id" => business&.id })
    end

    external_group&.instrument_event(:unlink, team)

    external_group&.provider&.business&.update_license_usage

    GitHub.logger.info(
      "info.message" => "Finished external_group_team_unlink job",
      "gh.business.id" => business&.id,
      "gh.caller" => caller,
      "gh.business.slug" => business&.slug,
    )
  rescue ActiveRecord::RecordNotFound => e
    # We see ActiveRecord::RecordNotFound when there's a race condition on the team and the team is already destroyed.
    # Log the error and allow the Team#destroy cleanup jobs to handle the unlinking.
    if e.model == "Team"
      options = {
        "info.message" => "external_group_team_unlink job team already destroyed",
        "gh.business.id" => business&.id,
        "gh.business.slug" => business&.slug,
        "gh.external_group.name" => external_group&.display_name,
        "gh.external_group.id" => external_group&.id,
        "gh.team.name" => team&.name,
        "gh.team.id" => team&.id,
        "exception.message" => e.message,
        "gh.backtrace" => e.backtrace&.join("\n"),
      }

      GitHub.logger.error(options)
    else
      raise e
    end
  end
end
