# typed: strict
# frozen_string_literal: true

class HydroCodeScanningOnPushJob < Repositories::PushHydroMessageJob
  queue_as :hydro_code_scanning_on_push

  sig { returns(T.nilable(T::Boolean)) }
  def perform
    return if repository.nil? || repository.deleted?
    return unless repository.code_scanning_usable?

    default_branch_update = push_includes_default_branch?

    unless default_branch_update.present?
      GitHub.logger.info(
        "HydroCodeScanningOnPushJob: no default branch update found",
        "gh.repo.id": repository.id,
        "gh.request_id": request_id,
      )
      return
    end

    if default_branch_update.deleted?
      GitHub.logger.info(
        "HydroCodeScanningOnPushJob: default branch update is deleted",
        "gh.repo.id": repository.id,
        "gh.request_id": request_id,
      )
      return
    end

    has_actions_key = "code_scanning.#{repository.id}.has_actions"
    has_workflows = repository.workflows.map(&:present_in_default_branch).any?
    actions = T.let(nil, T.nilable(String))
    actions = CodeScanning::KV.store.get(has_actions_key).value!
    if actions.present? && actions == has_workflows.to_s
      GitHub.logger.info(
        "HydroCodeScanningOnPushJob: has actions key kv hit",
        "gh.repo.id": repository.id,
        "gh.request_id": request_id,
        "has_actions": actions,
        "has_workflows": has_workflows,
      )
      return
    end

    inserted_languages = []
    removed_languages = []

    if has_workflows
      inserted_languages << "actions"
    else
      removed_languages << "actions"
    end
    CodeScanning::AutoCodeqlLanguageUpdateJob.enqueue_if_necessary(repository:, inserted_languages:, removed_languages:)

    ActiveRecord::Base.connected_to(role: :writing) do
      CodeScanning::KV.store.set(has_actions_key, has_workflows.to_s, expires: 7.days.from_now)
    end
  end
end
