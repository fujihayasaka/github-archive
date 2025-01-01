# typed: strict
# frozen_string_literal: true

# This job doesn't create a workspace or assign it to an advisory - that's
# still handled by RepositoryAdvisory::WorkspaceRepositoryBuilder. This job
# simply creates a timeline event that will be displayed on the advisory.
class HydroAdvisoryDatabaseWorkspaceCreatedJob < WorkspaceEventJob
  extend T::Sig

  queue_as :hydro_advisory_database_workspace_created

  sig { void }
  def perform
    return unless GitHub.repository_advisories_enabled?

    workspace_repository = repository
    parent_advisory = workspace_repository&.parent_advisory
    return unless parent_advisory && workspace_repository.active?

    # Match the user lookup that User does, falling back to ghost if actor_id isn't present.
    actor = User.find_by(id: message[:actor_id]) || User.ghost

    # Set the actor to nil if the action was performed by a staff member with
    # access to stafftools who does not otherwise have permissions on the
    # advisory, in which case we don't want to disclose their identity.
    actor = nil if actor.ghost? || (
      admin_frontend_accessible?(actor) &&
      !can_manage_advisories?(parent_advisory.repository, actor) &&
      !pvr_author?(parent_advisory, actor)
    )

    ActiveRecord::Base.connected_to(role: :writing) do
      parent_advisory.add_workspace_created_event(workspace_repository, actor)
    end
  end
end
