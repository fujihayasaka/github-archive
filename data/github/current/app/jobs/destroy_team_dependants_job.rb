# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class DestroyTeamDependantsJob < ApplicationJob
  queue_as :destroy_team_dependants

  retry_on_dirty_exit
  retry_on_recoverable_exceptions
  retry_on Freno::Throttler::Error, Freno::Error, Freno::Throttler::WaitedTooLong,
    wait: :polynomially_longer, attempts: 20

  def perform(org_ids, team_ids_to_info, member_ids = [], ancestor_team_ids = [], options = {})
    GitHub.logger.info(
      "Starting DestroyTeamDependantsJob",
      "gh.organization.ids" => org_ids[0..100],
      "gh.organization.ids.size" => org_ids.size,
      "gh.team.ids" => team_ids_to_info.keys[0..100],
      "gh.team.ids.size" => team_ids_to_info.size,
      "gh.ancestor_teams.ids" => ancestor_team_ids[0..100],
      "gh.ancestor_teams.ids.size" => ancestor_team_ids.size,
    )

    # Ensure org_ids is an array
    org_ids = Array(org_ids)

    # Convert associative array into hash.
    team_ids_to_info = Hash[team_ids_to_info] if team_ids_to_info.is_a?(Array)

    return if options[:business]&.kill_switch_enabled?("DestroyTeamDependantsJob", feature_flag: :enterprise_teams_killswitch, log_fields: {
      "gh.team.ids": team_ids_to_info.keys,
      "gh.business.id": options[:business].id
    })

    if BusinessTeam.enabled_for_enterprise?(business: options[:business])
      # this is superfluous until the feature flag is removed
      with_write { Team::Destruction::DestroyDependantsOperation.new(org_ids, team_ids_to_info, options).execute }
    else
      with_write { Team::Destruction::DestroyDependantsOperation.new(org_ids.first, team_ids_to_info).execute }
    end
  end
end
