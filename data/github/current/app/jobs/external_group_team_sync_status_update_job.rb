# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class ExternalGroupTeamSyncStatusUpdateJob < ApplicationJob
  include FeatureFlagHelper

  queue_as :external_group_team_sync_status_update

  retry_on_dirty_exit

  # Public: Updates the sync status of an ExternalGroupTeam.
  #
  # external_group_team_id - The ID of the ExternalGroupTeam to update.
  # out_of_seats - A boolean indicating whether an out of seats error was encountered when adding members to the team.
  def perform(external_group_team_id, out_of_seats = false)
    return unless ExternalGroupTeam.exists?(external_group_team_id)
    external_group_team = ExternalGroupTeam.find(external_group_team_id)
    business = T.must(external_group_team.external_group).provider&.business

    log_info("Starting external_group_team_sync_status_update job", external_group_team_id, external_group_team, business)

    external_group_team.update_sync_status(out_of_seats: out_of_seats)

    log_info("Finished external_group_team_sync_status_update job", external_group_team_id, external_group_team, business)
  end

  private

  def log_info(message, external_group_team_id, external_group_team, business)
    GitHub.logger.info(
      "info.message" => message,
      "code.namespace" => self.class.name,
      "code.function" => "perform",
      "gh.external_group_team.id" => external_group_team_id,
      "gh.external_group.id" => external_group_team.external_group.id,
      "gh.business.id" => business&.id,
      "gh.business.slug" => business&.slug,
      "gh.caller" => caller.to_s
    )
  end
end
