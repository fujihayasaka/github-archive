# typed: true
# frozen_string_literal: true

class DeleteRepositoryOrchestration < RepositoryOrchestration
  include GitHub::Memoizer

  validate :can_delete_repository?, on: :create

  def can_delete_repository?
    can_delete = !GitHub.never_delete_ids.include?(repository.id)
    if repository.member_privilege_rulesets_enabled? && deleter &&
      !RulesEngine::RepositoryActionEvaluator.can_delete_repository?(repository, T.must(deleter))
      return false
    end
    can_delete
  end

  step :ensure_active do
    return :skipped unless repository.active?
  end

  step :hide_repo do
    return if repository.deleted?

    deleter_id = data[:deleter_id]
    repository.deleted_by_user_id = deleter_id if deleter_id.present?
    repository.deleted_at = Time.now
    repository.active = nil

    unlink_parent_advisory = false
    parent_advisory = repository.parent_advisory
    if parent_advisory &&
      (GitHub.flipper[:advisory_db_unrestorable_repositories].enabled?(parent_advisory.repository) ||
      GitHub.flipper[:advisory_db_unrestorable_repositories].enabled?(deleter))
      unlink_parent_advisory = true
      data[:advisory_id] = parent_advisory.id
      if repository.restorable?
        repository.restorable = false
      end
    end

    Repository.transaction do
      repository.save!

      data[:auth_version] = repository.increment_auth_version
    end

    if unlink_parent_advisory
      parent_advisory.workspace_repository_id = nil
      parent_advisory.save!
    end
  end

  job_start

  step :delete_private_forks do
    # if this is the root of a private network, we need to delete all child forks
    return if data[:ignore_forks] || repository.public? || repository.network&.root_id != repository.id

    ids_to_delete = Repository.active.private_scope.where(source_id: repository.network_id).where.not(id: repository.id).pluck(:id)

    if ids_to_delete.present?
      # Queue orchestrations to delete the child forks of the repository we are deleting.
      # Those orchestrations should ignore the child forks since they are already identified in this list
      Repository.active.where(id: ids_to_delete).each do |repo|
        o = RepositoryOrchestration.delete(repo, actor: deleter, ignore_forks: true, send_email: data[:send_email], staff: data[:staff])
        o.execute(synchronous: data[:synchronous])
      end
      repository.reload
    end
  end

  step :delete_inaccessible_forks do
    ids_inaccessible = inaccessible_forks_ids
    if ids_inaccessible.present?
      # delete inaccessible forks and look for child forks of theirs that also need to be deleted
      Repository.active.where(id: ids_inaccessible).each do |repo|
        o = RepositoryOrchestration.delete(repo, actor: deleter, delete_forks_inaccessible_to: data[:delete_forks_inaccessible_to], send_email: data[:send_email], staff: data[:staff])
        o.execute(synchronous: data[:synchronous])
      end
    end

    # This is necessary for future steps to have up-to-date data
    repository.reload
  end

  # Annoint a new network root if we have repos that need reparented and we don't have a parent already
  step :elect_network_root do
    ids_to_reparent = fork_ids_to_reparent
    return if ids_to_reparent.blank?

    if repository.parent.present?
      # make sure this repo's parent is active and can be the parent of these child forks
      # if not, keep looking up the tree until we find one that is
      new_parent = T.let(T.cast(repository.parent, T.nilable(Repository)), T.nilable(Repository)) # rubocop:todo GitHub/AvoidCast
      loop do
        break if new_parent.nil?
        if new_parent.active?
          data[:reparent_to_id] = new_parent.id
          break
        end
        new_parent = T.cast(new_parent.parent, T.nilable(Repository)) # rubocop:todo GitHub/AvoidCast
      end

      return if data[:reparent_to_id].present?
    end

    reparent_to_id = ids_to_reparent.first
    new_parent = Repositories::Public.find_active!(reparent_to_id)
    new_parent.network&.make_root!(new_parent)
    data[:reparent_to_id] = reparent_to_id
  end

  step :reparent_forks do
    ids_to_reparent = fork_ids_to_reparent
    return if ids_to_reparent.blank?

    # validate that the parent we selected is still active and still in the network
    reparent_to_id = data[:reparent_to_id]
    loop do
      parent = Repositories::Public.find_active(reparent_to_id) if reparent_to_id.present?

      if parent.nil?
        log_error "reparent repo #{reparent_to_id} does not exist"
        data[:reparent_to_id] = nil
        set_next_step(:elect_network_root)
        return
      elsif parent.deleted? || parent.network_id != repository.network_id
        log_error "Repo #{reparent_to_id} is no longer active or not in the network"
        # try the parent's parent
        reparent_to_id = parent.parent&.id
        data[:reparent_to_id] = reparent_to_id
      else
        break
      end
    end

    # reparent the remaining forks
    Repository.active.where(id: ids_to_reparent).each do |repo|
      Repository.transaction do
        repo.update(parent_id: reparent_to_id)
        repo.update_organization
      end
    end
  end

  step :hide_advisories do
    # Set owner_id nil for all the repo's advisories. This hides them from
    # repo counts but retains them in the Advisory Database.
    # https://github.com/github/github/pull/129699#issuecomment-562643203
    repository.hide_repository_advisories_on_delete

    # find all the workspace repositories that depend on repository and perform
    # their removal process
    Repository::AdvisoryAbilityManager.hide_and_remove_all(deleter, repository: repository)
  end

  step :update_repository do
    repository.calculate_network_counts! unless repository.network.nil?
    repository.owner&.update_locked_repositories if repository.owner.present?
    repository.owner&.synchronize_search_index
    repository.enable_or_disable_owner! if repository.private? && repository.owner&.plan&.per_repository?
  end

  step :publish_deleted do
    message = build_hydro_event_message.merge({
      actor_id: data[:deleter_id]
    })

    publish_hydro_event(message: message, schema: "github.repositories.v1.Deleted")
  end

  step :instrument_removed do
    GlobalInstrumenter.instrument("repository.deleted",
    {
      deleted_repository: repository,
      actor: deleter,
    })

    actor_payload = if data[:staff]
      GitHub.guarded_audit_log_staff_actor_entry(deleter)
    else
      { actor: deleter }
    end

    repository.instrument :destroy, actor_payload
  end

  step :queue_jobs do
    repository.enqueue_background_dependent_jobs(deletion_stage: GitHub::BackgroundDeletes::DeletionStage::RepositorySoftDelete)

    CodeqlDatabaseCleanupJob.perform_later(repository_id: repository.id)
  end

  step :publish_workspace_deleted do
    if data[:advisory_id].present?
      actor_id = data[:actor_id]
      advisory = RepositoryAdvisory.find_by(id: data[:advisory_id])
      if GitHub.flipper[:advisory_db_unrestorable_repositories].enabled?(advisory&.repository) || GitHub.flipper[:advisory_db_unrestorable_repositories].enabled?(actor)
        message = build_hydro_event_message.merge({
          actor_id: actor_id,
          advisory_id: advisory&.id,
        })

        publish_hydro_event(message: message, schema: "github.repositories.v1.WorkspaceDeleted")
      end
    end
  end

  step :publish_search_removed do
    payload = {
      change: :DELETED,
      repository: repository,
      owner_name: repository.owner&.name,
      updated_at: Time.now.utc,
      ref: "refs/heads/#{repository.default_branch}",
      auth_version: data[:auth_version],
    }

    GlobalInstrumenter.instrument("search_indexing.repository_deleted", payload)
    GitHub.dogstats.increment("geyser.repo_changed_event.published", tags: ["change_type:deleted"])
  end

  step :delete_blobs do
    if repository.has_lfs_files?
      repository.reset_billed_lfs_storage_usage
      repository.delete_media_blobs
    end
  end

  step :send_email do
    if data[:send_email]
      parent_repo_name = repository.parent ? repository.parent&.name_with_owner : repository.name
      RepositoryMailer.private_fork_deleted(repo_nwo: repository.name_with_owner, parent_nwo: parent_repo_name, repo_owner: repository.owner).deliver_later
    end
  end

  step :instrument_finished do
    GlobalInstrumenter.instrument(GlobalEvents::Repository::REMOVED, {
      repository_id: repository.id,
    })
  end

  sig { returns(Repository) }
  def repository
    T.must(super)
  end

  private

  sig { returns(T.nilable(User)) }
  def deleter
    return nil if data[:deleter_id].blank?

    @deleter ||= User.find_by(id: data[:deleter_id])
  end

  sig { returns(T.nilable(User)) }
  memoize def actor
    User.find_by(id: data[:actor_id])
  end

  # identify child forks that will need a new parent
  def fork_ids_to_reparent
    return nil if data[:ignore_forks]

    ids_to_reparent = if repository.parent.present?
      all_forks.map(&:id) - Array(inaccessible_forks_ids)
    else
      public_forks.map(&:id)
    end

    return ids_to_reparent if data[:reparent_to_id].blank?

    ids_to_reparent - [data[:reparent_to_id]]
  end

  def inaccessible_forks_ids
    return nil if data[:ignore_forks]
    return nil unless repository.parent.present?
    return nil unless ancestor_id = data[:delete_forks_inaccessible_to]

    ancestor = Repositories::Public.get_active_or_deleted!(ancestor_id)

    # find the direct private child forks and delete them if they lost their accessibility
    result = []
    forks = Repository.active.private_scope
    .where(source_id: repository.network_id, parent_id: repository.id)

    # Use Promise.all to handle the asynchronous calls
    inaccessible_forks = Promise.all(forks.map { |repo| ancestor.async_pullable_by?(repo.owner) }).then do |results|
      forks.each_with_index do |repo, index|
        unless results[index]
          result << repo.id
        end
      end

      # Return the array of inaccessible fork IDs
      result
    end.sync

    inaccessible_forks
  end

  def public_forks
    all_forks.where(public: true)
  end

  def all_forks
    conditions = {
      parent_id: repository.id,
      source_id: repository.network_id,
      active: true,
    }
    Repository.where(conditions).order(:id)
  end
end
