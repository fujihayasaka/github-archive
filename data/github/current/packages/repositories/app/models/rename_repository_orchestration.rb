# typed: false # rubocop:disable Sorbet/TrueSigil
# frozen_string_literal: true

class RenameRepositoryOrchestration < RepositoryOrchestration
  include GitHub::Memoizer
  include GitHub::ResilienceMixin

  validate :renamable?, on: :create
  before_create :lock_retired_namespace # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  def renamable?
    if repository.owner.display_login != repository.owner.reload.display_login
      errors.add(:base, message: "change was unsuccessful. Please try again.")
    end

    # This check is necessary because the repository could have been transferred
    # to a different owner since the orchestration was created and before the
    # RepositoryOwnerLock was acquired. If the repository was transferred to a different owner,
    # the RenameRepositoryOrchestration would still have a reference to the old owner id
    # so we need to make sure that the repository is still owned by the same owner
    if GitHub.flipper[:repo_transfer_owner_lock].enabled?(repository.owner)
      current_repo_owner_id = Repository.find_by(id: repository.id)&.owner_id
      if repository.owner_id != current_repo_owner_id
        errors.add(:base, message: "the owner has changed.")
      end
    end

    if repository.blocks_repository_rename?(actor)
      errors.add(:base, message: "can't be changed on a repository protected by a ruleset")
    end

    if data[:normalized_name] == repository.name
      errors.add(:base, message: "same name")
    end

    old_name = repository.name
    repository.name = data[:normalized_name]
    unless repository.valid?
      errors.add(:base, repository.errors.full_messages.join(", "))
    end

    if !RulesEngine::RepositoryActionEvaluator.can_rename_repository?(repository, actor, false)
      errors.add(:base, message: "is prevented by rulesets.")
    end

    repository.name = old_name
  end

  step :rename do
    error = false

    Repository.transaction do
      repository.transfers.destroy_all

      unless repository.update(name: data[:normalized_name])
        error = true
        repository.name = data[:old_name]
        raise ActiveRecord::Rollback
      end

      data[:auth_version] = repository.increment_auth_version
    end

    return :skipped, repository.errors.full_messages.join(", ") if error
  end

  step :update_pages do
    repository.page&.set_subdomain_to_match_nwo

    # Renaming the user-page can change the URL for all project-pages
    # so force propagate_https_redirect if was or is cname_user_pages repo.
    repository.rebuild_pages(actor || owner, data[:was_cname_user_pages_repo] || repository.is_cname_user_pages_repo?)
  end

  step :update_public_keys do
    repository.public_keys.each(&:save)
  end

  step :setup_redirect do
    repository.redirect_from_previous_location(data[:old_nwo])
  end

  step :instrument_rename do
    repository.instrument_rename(old_name: data[:old_name], actor: actor)

    GlobalInstrumenter.instrument("repository.rename", {
      actor: actor,
      repository: repository,
      previous_name: data[:old_name],
      current_name: data[:new_name],
    })
  end

  step :unlock_retired_namespace do
    Repositories::RepositoryOwnerLock.release_rename_lock(owner_id: repository.owner.id) rescue nil
  end

  job_start

  step :update_spokes do
    return :failed, "repository no longer exists" if repository.nil?

    GitHub::Spokes.client.write_nwo_file(repository, repository.name_with_owner) # rubocop:disable GitHub/DoNotAllowNameWithOwner
  end

  step :unlock_descendants do
    return unless repository.locked
    repository.unlock_including_descendants! if repository.locked_on_rename?
  end

  step :trigger_code_search_indexing do
    GlobalInstrumenter.instrument("search_indexing.repository_changed", { change: :ADMIN_REPAIR, repository: repository, auth_version: data[:auth_version] })
  end

  memoize def actor
    User.find_by_id(data[:actor_id])
  end

  class FailedRenameLockError < StandardError; end

  def lock_retired_namespace
    unless Repositories::RepositoryOwnerLock.acquire_rename_lock(owner_id: repository.owner.id)
      raise FailedRenameLockError.new("retired namespace lock could not be acquired")
    end
  end
end
