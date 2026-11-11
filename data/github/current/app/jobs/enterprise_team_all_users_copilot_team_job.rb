# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: strict
# frozen_string_literal: true

class EnterpriseTeamAllUsersCopilotTeamJob < ApplicationJob
  queue_as :enterprise_team_all_users_copilot_team

  BATCH_SIZE = 200

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  # This method is performed on all users in an enterprise, it is called
  #   when the administrator switches the enterprise team that is synced with the
  #   copilot in the all_users_copilot_team configurable.
  #
  # The method adds or removes all enterprise users from the enterprise team
  #   that is being switched to.  It also generates events for the copilot to
  #   pick up the changes.  2 events can be generated foe copilot "enterprise_team.copilot.assignment"
  #   when a team is assigned to the copilot and "enterprise_team.copilot.unassignment" when a team is
  #   unassigned from the copilot.
  #
  # @param enterprise_team_id_from [Integer] the enterprise team id that is being switched from, can be nil
  # @param enterprise_team_id_to [Integer] the enterprise team id that is being switched to, can be nil
  sig { params(enterprise_team_id_from: T.nilable(Integer), enterprise_team_id_to: T.nilable(Integer)).void }
  def perform(enterprise_team_id_from: nil, enterprise_team_id_to: nil)
    GitHub.logger.info(
      "info.message" => "Starting EnterpriseTeamAllUsersCopilotTeamJob",
      "gh.enterprise_team.enterprise_team_id_from" => enterprise_team_id_from,
      "gh.enterprise_team.enterprise_team_id_to" => enterprise_team_id_to,
    )

    enterprise_team_from = EnterpriseTeam.find_by(id: enterprise_team_id_from) if enterprise_team_id_from.present?
    enterprise_team_to = T.must(EnterpriseTeam.find_by(id: enterprise_team_id_to)) if enterprise_team_id_to.present?

    if enterprise_team_from
      with_write { enterprise_team_from.enterprise_team_assignments.where(assignment_type: :copilot).destroy_all }

      # delete all the users from the old enterprise team
      delete_users_from_enterprise_team(enterprise_team_from)
    end

    if enterprise_team_to
      # we are adding users to the enterprise team, so we can just perform a bulk insert, but
      # we still need to generate an event for a copilot to pick up the changes
      add_users_to_enterprise_team(enterprise_team_to)

      with_write { EnterpriseTeamAssignment.find_or_create_by!(enterprise_team: enterprise_team_to, assignment_type: :copilot) }
    end

    GitHub.logger.info(
      "info.message" => "Finished EnterpriseTeamAllUsersCopilotTeamJob",
      "gh.enterprise_team.enterprise_team_id_from" => enterprise_team_id_from,
      "gh.enterprise_team.enterprise_team_id_to" => enterprise_team_id_to,
    )
  end

  private

  sig { params(enterprise_team: T.nilable(EnterpriseTeam)).void }
  def add_users_to_enterprise_team(enterprise_team)
    return unless enterprise_team
    return unless enterprise_team.business

    provider = enterprise_team.business&.external_provider
    return unless provider.present?

    user_ids = ExternalIdentity.by_provider(provider).is_active.pluck(:user_id)

    enterprise_team.bulk_add_member_ids(user_ids: user_ids)

    instrument_event(enterprise_team, "enterprise_team.add_member", user_ids)
  end

  sig { params(enterprise_team: T.nilable(EnterpriseTeam)).void }
  def delete_users_from_enterprise_team(enterprise_team)
    return unless enterprise_team

    user_ids = enterprise_team.enterprise_team_memberships.pluck(:user_id)

    with_write do
      # delete all the users from the old enterprise team
      enterprise_team.enterprise_team_memberships.pluck(:id).each_slice(BATCH_SIZE) do |membership_ids|
        EnterpriseTeamMembership.where(id: membership_ids).delete_all
      end
    end

    instrument_event(enterprise_team, "enterprise_team.remove_member", user_ids)
  end

  sig { params(enterprise_team: EnterpriseTeam, event_name: String, user_ids: T::Array[Integer]).void }
  def instrument_event(enterprise_team, event_name, user_ids)
    user_ids.each_slice(BATCH_SIZE) do |user_id_slice|
      users = User.where(id: user_id_slice)
      users.each do |user|
        if event_name == "enterprise_team.add_member"
          enterprise_team.instrument_add_member(user)
        else
          enterprise_team.instrument_remove_member(user)
        end
      end
    end
  end
end
