# typed: true
# frozen_string_literal: true

class DestroyTeamJob < ApplicationJob
  queue_as :destroy_team

  retry_on_dirty_exit

  def perform(team_id)
    team = Team.find_by(id: team_id)

    return unless team.present?

    with_write { team.destroy }
  end
end
