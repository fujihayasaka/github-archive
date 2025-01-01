# typed: strict
# frozen_string_literal: true

class HydroActionsOnPushJob < Repositories::PushHydroMessageJob
  queue_as :hydro_actions_on_push

  sig { returns(T.nilable(T::Array[Repositories::RefUpdate])) }
  def perform
    return if repository.nil? || repository.deleted?
    default_branch_update = push_includes_default_branch?

    unless default_branch_update.present?
      GitHub.logger.info(
        "HydroActionsOnPushJob: no default branch update found",
        "gh.repo.id": repository.id,
        "gh.request_id": request_id,
      )
      return
    end

    if default_branch_update.deleted?
      GitHub.logger.info(
        "HydroActionsOnPushJob: default branch update is deleted",
        "gh.repo.id": repository.id,
        "gh.request_id": request_id,
      )
      return
    end

    with_write do
      repository.update_repository_actions
      # Update when the repository is a fork with no workflows to avoid fork -> sync workflow from upstream scenarios
      # which can result in mismatched registered workflows in the fork (see https://github.com/github/github/pull/394748)
      if default_branch_update.large_push? || (repository.fork? && repository.workflows.empty?)
        repository.refresh_workflows
      else
        repository.update_repository_workflows(default_branch_update.ref, default_branch_update.before, default_branch_update.after)
      end
    end
  end
end
