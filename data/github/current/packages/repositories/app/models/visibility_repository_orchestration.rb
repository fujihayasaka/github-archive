# typed: false
# frozen_string_literal: true
class VisibilityRepositoryOrchestration < RepositoryOrchestration
  include GitHub::CacheLock

  validate :validate_orchestration, on: :create

  step :record_data do
    data[:old_visibility] = repository.visibility
    data[:security_settings] = SecurityProduct::ServiceManager.new(repository).enabled_non_ghas_services.keys || []
    data[:detach] = repository.detach_on_visibility_change?
  end

  step :set_visibility, transaction: true do
    case new_visibility
    when Repository::PRIVATE_VISIBILITY
      repository.public = false
      repository.internal_repository&.destroy
    when Repository::INTERNAL_VISIBILITY
      repository.internal_repository ||= InternalRepository.new(repository: repository, business: owner.business)
      repository.internal_repository.business = owner.business
      repository.public = false
    when Repository::PUBLIC_VISIBILITY
      repository.public = true
      repository.internal_repository&.destroy
    end

    repository.save!
    data[:auth_version] = repository.increment_auth_version
    repository.reload_internal_repository
  end

  job_start

  step :publish_visibility_change do
    GlobalInstrumenter.instrument("repository.visibility_changed", {
      name_with_owner: repository.name_with_owner,
      repository_id: repository.id,
      is_private: repository.private?,
      is_fork: repository.fork?,
      visibility: repository.visibility,
      feature_flags: SecretScanning::Instrumentation::RepositoryServiceFlags.new(repository).visibility_change_service_flags,
    })

    if repository.user_configuration_repository? && repository.public? && repository.has_readme?
      GlobalInstrumenter.instrument("user.profile_readme_action", {
        repository: repository,
        owner: owner,
        actor: actor,
        change_type: :REPO_VISIBILITY_CHANGED_TO_PUBLIC,
        readme_body: repository.preferred_readme&.data
      })
    end

    if repository.is_org_profile_repository? && repository.public? && repository.has_org_profile_readme?
      GlobalInstrumenter.instrument("organization.profile_readme_action", {
        repository: repository,
        owner: owner,
        actor: actor,
        change_type: :REPO_VISIBILITY_CHANGED_TO_PUBLIC,
        readme_body: repository.preferred_readme&.data
      })
    end

    payload = {
      change: :VISIBILITY_CHANGED,
      repository: repository,
      owner_name: repository.owner.name,
      updated_at: Time.now.utc,
      ref: "refs/heads/#{repository.default_branch}",
      actor: actor,
      auth_version: data[:auth_version],
    }

    GlobalInstrumenter.instrument("search_indexing.repository_changed", payload)
    GitHub.dogstats.increment("geyser.repo_changed_event.published", tags: ["change_type:visibility_changed"])
  end

  step :clear_user_cache_in_background do
    Contribution.clear_caches_for_user(repository.user)
  end

  step :lock_repo do
    repository.lock_excluding_descendants!(Repository::LockDependency::MOVING)
  end

  step :lock_forks do
    # lock forks when toggling from private to public
    if repository.public? && repository.network_root?
      repository.forks.select(&:private?).each(&:lock_for_move)
    end
  end

  step :drop_stargazers do
    if repository.private?
      stargazer_ids = Star.where(starrable_id: repository.id, starrable_type: "Repository").pluck(:user_id)

      stargazer_ids.each_slice(1000) do |stargazer_ids_slice|
        stargazers = User.where(id: stargazer_ids_slice)

        Promise.all(
          stargazers.map do |user|
            repository.async_readable_by?(user).then do |readable|
              user.unstar(repository) unless readable
            end
          end).sync
      end
    end
  end

  step :drop_advisory_collaborators do
    if repository.private?
      Repository::AdvisoryAbilityManager.change_visibility(repository: repository)
    end
  end

  step :extract_forks, max_attempts: 1 do
    if repository.public? && repository.network_root?
      forks = repository.forks.select(&:private?)
      forks.each do |fork|
        block_on_orchestration(RepositoryOrchestration.extract(fork))
      end
    end
  end

  step :lock_repo_to_set_permissions do
    # obtain a lock on manipulating the repo on disk or bail out. then perform the heavy operations.
    cache_lock_obtain("lock:toggle-perm:#{repository.id}", 1.hour)
  end

  # this step was formerly part of the ToggleRepoPermission class
  step :detach, max_attempts: 1 do
    if data[:detach] && repository.network.repositories.count + repository.network.deleted_repositories.count > 1
      block_on_orchestration(RepositoryOrchestration.detach(repository))
    end
  end

  # this step was formerly most of the ToggleRepoPermission class
  step :toggle_permission do
    repository.reload_network
    repository.enable_or_disable_shared_storage if repository.public?
    repository.network.enable_or_disable_shared_storage_for_private_repositories

    repository.update_organization

    # close any pull requests sent from this repo on public repositories
    if repository.private?
      repository.pull_requests_as_head.open_pulls.each do |pull|
        next if pull.repository.private?
        pull.close(owner)
      end
    end

    # now check to see if the repo permission was toggled into some other
    # state while we were working. if so, abort. We don't want to queue up another toggle job.
    if repository.reload.visibility != new_visibility
      return :failed, "Visibility changed while toggling permissions"
    end

    # check if this repo or any of the owner's other repos should be
    # unlocked as a result of this visibility change
    owner&.update_locked_repositories

    # update visibility in the search indexes
    repository.reindex_all

    # update the public repository count for the owner in the search index
    owner&.synchronize_search_index

    repository.calculate_network_counts!
  end

  step :sync_org_owned_private_network_with_forks do
    repository.network.sync_org_owned_private_network_with_forks
  end

  step :unlock_repo_to_set_permissions do
    cache_lock_release("lock:toggle-perm:#{repository.id}")
  end

  step :disable_push_rules do
    if repository.public?
      # public repos cannot have repo-level push rules. So disable them
      RepositoryRuleset.load_for(source: repository, include_parents: false, targets: ["push"]).each do |ruleset|
        ruleset.enforcement = :disabled
        ruleset.save(validate: false)
      end
    end
  end

  step :update_security_product_settings do
    if !GitHub.enterprise? && exists_on_disk?
      SecurityProduct::ServiceManager.new(repository).toggle_services_on_repository_state_changed(actor: actor, services_to_enable: data[:security_settings])
    end
  end

  step :publish_visibility_changed do
    message = build_hydro_event_message.merge({
      actor_id: data[:actor_id],
      old_visibility: data[:old_visibility],
      new_visibility: new_visibility
    })
    publish_hydro_event(message: message, schema: "github.repositories.v1.VisibilityChanged")
  end

  step :unlock_repo do
    repository.unlock_excluding_descendants!
  end

  step :enable_owner do
    repository.enable_or_disable_owner!
  end

  step :delete_unsupported_artifacts do
    if repository.private?
      repository.unpublish_page unless repository.plan_supports_pages?
      repository.destroy_protected_branches unless repository.plan_supports?(:protected_branches)
      repository.tag_protection_states.destroy_all unless repository.tag_protections_availability == :enabled
      repository.disable_tiered_reporting(actor: actor)
    end
  end

  step :unlock_access do
    if repository.private? && !repository.fork?
      # unlock anonymous git access setting before disabling
      repository.unlock_anonymous_git_access(actor)
      repository.disable_anonymous_git_access(actor)
    end
  end

  step :update_pages do
    repository.page.restore_deleted if repository.plan_supports?(:pages) && repository.page && repository.page.deleted_at

    if !repository.private?

      if repository.org_members_can_create_public_pages?
        repository.rebuild_pages(actor) if repository.page&.update(public: true)
      else
        repository.unpublish_page
      end
    end
  end

  step :queue_jobs do
    if repository.private_network_root? && data[:old_visibility] == Repository::INTERNAL_VISIBILITY
      RemoveInvalidUserForksJob.perform_later(network_id: repository.network_id)
    end

    if repository.private?
      CodeqlDatabaseCleanupJob.perform_later(repository_id: repository.id)
    end

    repository.async_purge_subscribers
    repository.enqueue_set_license_job
    repository.instrument :access, access: new_visibility.to_sym, actor: actor, previous_visibility: data[:old_visibility]
  end

  ##########################################################
  ### steps end
  ##########################################################

  attr_writer :actor

  def actor
    return @actor if defined?(@actor)

    @actor = User.find_by_id(data[:actor_id])
  end

  def owner
    repository.owner
  end

  def new_visibility
    @new_visibility ||= data[:new_visibility] || repository.toggled_visibility
  end

  def exists_on_disk?
    return @exists_on_disk if defined?(@exists_on_disk)
    @exists_on_disk = repository.exists_on_disk?
  end

  def validate_no_duplicates
    existing = self.class.active.where(type: self.class, repository_id: repository_id).first
    if existing.present?
      errors.add(:base, :duplicate, message: "orchestration in progress #{existing.id}")
      raise Repositories::Error::VisibilityLocked, "Failed to update visibility. A previous visibility change is still in progress."
    end
  end

  def validate_orchestration
    if !repository.feature_enabled?(:prevent_visibility_change_on_invalid_repos)
      repository.errors.clear
    end

    if !repository.can_change_repo_visibility?(actor)
      repository.errors.add(:visibility, "can't be changed by this user.")
    end

    if !repository.can_change_repo_visibility_with_rules?(actor, new_visibility)
      repository.errors.add(:visibility, "can't be changed by this user because of rulesets.")
    end

    unless %w[public private internal].include?(new_visibility)
      repository.errors.add(:visibility, "can't be changed to unknown visibility #{new_visibility}.")
    end

    if new_visibility == repository.visibility
      repository.errors.add(:visibility, "is already #{repository.visibility}.")
    end

    if %w[private internal].include?(new_visibility) && (repository.matches_root_visibility? || repository.sole_repo_in_network?)
      if repository.owner.at_private_repo_limit?
        repository.errors.add(:visibility, "can't be private. Please upgrade your subscription to make this repository private.")
      elsif !repository.owner_has_seats_for_collaborators?
        repository.errors.add(:visibility, "can't be private. Please add seats for collaborators to make this repository private.")
      elsif !repository.owner_has_seats_for_collaborators?(pending_cycle: true)
        repository.errors.add(:visibility, "can't be private. Please cancel the pending seat downgrade to ensure there are seats for collaborators to make this repository private.")
      end

      if visibility_change_restricted_by_trade_controls?
        repository.errors.add(:visibility, "can't be private. We are unable to provide this feature for one of the collaborators or invitees in this repository.")
      end
    end

    if repository.trade_controls_read_only?(new_visibility: Repository::PUBLIC_VISIBILITY)
      # Using the admin based messaging, as they are the only people with the permission to toggle the repo visibility
      repository.errors.add(:visibility_restricted, ::TradeControls::Notices.notice_as_plaintext(:organization_owned_repo_disabled))
    end

    if !GitHub.public_repositories_available? && new_visibility == Repository::PUBLIC_VISIBILITY
      repository.errors.add(:visibility, "Public repositories are not available.")
    end

    if repository.owner.emu_creating_public_repo?(new_visibility)
      repository.errors.add(:visibility, "Enterprise managed resources can't have #{Repository::PUBLIC_VISIBILITY} visibility")
    end

    if new_visibility == Repository::INTERNAL_VISIBILITY
      if !owner.organization?
        repository.errors.add(:visibility, "Only organization-owned repositories can have #{Repository::INTERNAL_VISIBILITY} visibility")
      end
      if !owner.business
        repository.errors.add(:visibility, "Only organizations associated with an enterprise can set visibility to #{Repository::INTERNAL_VISIBILITY}")
      end
    end

    if repository.errors.any?
      errors.add(:base, :visibility, message: repository.errors.full_messages)
    end

    if repository.lock_on_transferring_ownership?
      errors.add(:base, :visibility, message: "The repository is locked due to an ownership transfer.")
    end

    if namespace = RetiredNamespace.for(owner: owner.name, name: repository.name)
      errors.add(:visibility, "Repository namespace has been retired.") unless namespace.claimable_by?(owner)
    end
  end

  def visibility_change_restricted_by_trade_controls?
    # `restriction_tier_allows_feature?`is true for:
    # - the owner doesn't have any trade restrictions
    # - when the type of trade restriction allow free private repos (Tier 0)
    owner_has_restrictions = !owner.restriction_tier_allows_feature?(type: :repository)

    actor_is_restricted = actor&.has_any_trade_restrictions?
    org_sdn_restricted = owner.organization? && owner.has_commercial_interaction_restriction?(feature_type: :repository_visibility_change)
    paid_org_actor_is_restricted = actor_is_restricted && owner.organization? && owner.charged_account?
    non_org_actor_is_restricted = actor_is_restricted && owner.user?

    owner_has_restrictions || paid_org_actor_is_restricted || non_org_actor_is_restricted || org_sdn_restricted
  end
end
