# typed: true
# frozen_string_literal: true

# Destroys a team, its descendants, and their dependants in the background while
# retaining the enqueuing actor. Team#destroy soft-deletes the team synchronously
# and then enqueues this orchestration. Because the actor is persisted on the
# orchestration record, the heavy Team::Destruction::DestroyOperation runs (and
# retries) inside TeamOrchestrationJob with the original actor intact, so the
# team.destroy audit event is attributed to the real actor instead of falling back
# to the ghost user once the request context is gone.
class DestroyTeamOrchestration < TeamOrchestration
  job_start

  step :destroy_operation do
    # with_business_teams finds soft-deleted regular teams and business teams
    # (organization_id is nil). It returns nil once the row is hard-deleted, which
    # keeps the step idempotent if the team has already been destroyed (e.g. by a
    # prior run or the CleanUpDeletedTeamsJob sweeper).
    team = Team.with_business_teams.find_by(id: team_id)
    with_write { Team::Destruction::DestroyOperation.new(team, actor: actor).execute } if team
  end
end
