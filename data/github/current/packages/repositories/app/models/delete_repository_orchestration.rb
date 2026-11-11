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
      (FeatureFlag.vexi.enabled_or_raise?(:advisory_db_unrestorable_repositories, parent_advisory.repository) || # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
      FeatureFlag.vexi.enabled_or_raise?(:advisory_db_unrestorable_repositories, deleter)) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
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

  step :unset_custom_agent_source_org_repo do
    owner = repository.owner
    biz = owner&.business
    return unless biz.present?
    return unless biz&.feature_flag_enabled?(:enterprise_ai_controls_unset_custom_agent_source_org, default: false)

    if biz.subagent_definitions_source_repository_id == repository.id
      biz.unset_subagent_definitions_source_repository_id(actor: owner)
    end
  end

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
      Repositories.domain.reload(repository)
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
    Repositories.domain.reload(repository)
  end

  # Anoint a new parent for any child forks of the deleted repo.
  # This may involve electing a new root for the network if the deleted repo was the root
  step :elect_new_parent do
    # get a list of active forks that need to be reparented.
    ids_to_reparent = fork_ids_to_reparent

    # nothing to do here if there are no child forks to reparent
    return if ids_to_reparent.blank?

    network = repository.network
    network_id = network&.id

    # choose the repo's parent as the new parent for child forks, if it's active and in network.
    if repository.parent.present? && repository.parent&.active? && repository.parent&.network_id == network_id
      data[:reparent_to_id] = repository.parent&.id
      return
    end

    # choose the network root as the new parent for child forks, if it's active and in network.
    root = network&.root
    if root.present? && root.active? && root.network_id == network_id
      data[:reparent_to_id] = root.id
      return
    end

    # elect one of the child forks to be the network root and the parent of the others
    reparent_to_id = ids_to_reparent.first
    data[:reparent_to_id] = reparent_to_id
    new_parent = Repositories::Public.find_active!(reparent_to_id)
    if new_parent.present? && new_parent.network_id == network_id
      new_parent.network&.make_root!(new_parent)
    end
  end

  step :reparent_child_forks do
    ids_to_reparent = fork_ids_to_reparent
    return if ids_to_reparent.blank?

    reparent_to_id = data[:reparent_to_id]

    # if we don't have a new parent, there's nothing to do here.
    return if reparent_to_id.blank?

    # validate that the parent we selected is still active and still in the network
    parent = Repositories::Public.find_active(reparent_to_id)

    if parent.nil? || parent.deleted? || parent.network_id != repository.network_id
      log_error "invalid reparent repo #{reparent_to_id}"
      # try again to find a parent
      data[:reparent_to_id] = nil
      set_next_step(:elect_new_parent)
      return
    end

    # reparent the remaining forks
    ids_to_reparent.each_slice(100) do |id_batch|
      Repository.active.where(id: id_batch).each do |repo|
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
      if FeatureFlag.vexi.enabled_or_raise?(:advisory_db_unrestorable_repositories, advisory&.repository) || FeatureFlag.vexi.enabled_or_raise?(:advisory_db_unrestorable_repositories, actor) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
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

  sig { returns(T::Array[String]) }
  def logged_disallowed_concurrent_orchestration_types
    COMMON_DISALLOWED_CONCURRENT_ORCHESTRATIONS
  end

  # These orchestrations are allowed to run concurrently with DeleteRepositoryOrchestration because often
  # users create and then instantly delete a repo.
  ALLOWED_CONCURRENT_ORCHESTRATIONS = %w[
    CreateRepositoryOrchestration
    ForkRepositoryOrchestration
    CloneTemplateOrchestration
  ].freeze

  sig { returns(T::Array[T.nilable(String)]) }
  def disallowed_concurrent_orchestration_types
    if !data[:prevent_concurrency]
      COMMON_DISALLOWED_CONCURRENT_ORCHESTRATIONS - ALLOWED_CONCURRENT_ORCHESTRATIONS
    else
      []
    end
  end
end
