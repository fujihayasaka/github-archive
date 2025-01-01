# typed: true
# frozen_string_literal: true

class Hook::Event::TeamAddEvent < Hook::Event
  supports_targets *DEFAULT_TARGETS
  description "Team added or modified on a repository."

  event_attr :team_id, :repository_id, required: true

  def target_repository
    @repository ||= Repository.find_by(id: repository_id)
  end

  def team
    @team ||= Team.find(team_id)
  end

  # TODO: This should return the user that did the transfer
  def actor
    team.organization
  end

  def deliverable?
    target_repository.present?
  end
end
