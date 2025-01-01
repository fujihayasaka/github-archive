# typed: strict
# frozen_string_literal: true

# This job doesn't delete a workspace - that's still handled by
# DeleteRepositoryOrchestration. Instead, this job nullifies any association
# for the workspace on a repo advisory (similar to NullifyDependentRecordsJob)
# and then adds an event to the advisory timeline.
class HydroAdvisoryDatabaseWorkspaceDeletedJob < WorkspaceEventJob

  queue_as :hydro_advisory_database_workspace_deleted

  sig { void }
  def perform
    return unless GitHub.repository_advisories_enabled?

    workspace_repository = repository
    parent_advisory = T.must(RepositoryAdvisory.find_by(id: message[:advisory_id]))
    parent_repository = T.must(parent_advisory.repository)

    # Match the user lookup that User does, falling back to ghost if actor_id isn't present.
    actor = User.where(id: message[:actor_id]).first || User.ghost

    # Force the actor to nil if the action was performed by a staff member with
    # access to stafftools who does not otherwise have permissions on the
    # advisory, in which case we don't want to disclose their identity.
    actor = nil if actor.ghost? || (
      admin_frontend_accessible?(actor) &&
      !can_manage_advisories?(parent_repository, actor)
    )

    ActiveRecord::Base.connected_to(role: :writing) do
      parent_advisory.add_workspace_deleted_event(workspace_repository, actor)
    end
  end
end
