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
      # Syncing workflows upon creation of a fork or repo from template can result in mismatched registered workflows (see https://github.com/github/github/pull/394748)
      should_refresh = if default_branch_update.large_push?
        true
      elsif repository.fork?
        repository.workflows.empty?
      # The :actions_refresh_workflows_for_templates feature flag is checked on the cloned template's owner
      # to avoid extra DB calls from repository.template_repository_clone for most cases.
      # For now, this flag is not meant to be broadly rolled out as we must first assess the performance impact of the additional queries.
      elsif repository.owner&.feature_flag_enabled?(:actions_refresh_workflows_for_templates, default: false) &&
            repository.workflows.empty?
        repository.template_repository_clone.present?
      else
        false
      end
      if should_refresh
        repository.refresh_workflows
      else
        repository.update_repository_workflows(default_branch_update.ref, default_branch_update.before, default_branch_update.after)
      end
    end
  end
end
