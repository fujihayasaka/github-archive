# typed: true
# frozen_string_literal: true

class VisibilityRepositoryOrchestration < RepositoryOrchestration
  include GitHub::CacheLock

  validate :validate_orchestration, on: :create

  step :record_data do
    data[:old_visibility] = repository.visibility
    data[:security_settings] = SecurityProduct::ServiceManager.new(repository).enabled_non_ghas_services.keys
    data[:detach] = detach_repo?
    data[:extract_forks] = repository.network_root? && new_visibility == Repository::PUBLIC_VISIBILITY
  end

  step :set_visibility, transaction: true do
    case new_visibility
    when Repository::PRIVATE_VISIBILITY
      repository.public = false
      repository.internal_repository&.destroy
    when Repository::INTERNAL_VISIBILITY
      repository.internal_repository ||= InternalRepository.new(repository: repository, business: owner&.business)
      repository.internal_repository&.business = owner&.business
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

  step :ensure_restorable_started do
    return unless repository.feature_flag_enabled_or_raise?(:visibility_change_recovery_storage) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
    return unless repository.private?

    data[:restorable_id] = Restorables.domain.visibility_changed_repositories.ensure_started(repository).id
  end

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
      owner_name: owner&.name,
      updated_at: Time.now.utc,
      ref: "refs/heads/#{repository.default_branch}",
      actor: actor,
      auth_version: data[:auth_version],
    }

    GlobalInstrumenter.instrument("search_indexing.repository_changed", payload)
    GitHub.dogstats.increment("geyser.repo_changed_event.published", tags: ["change_type:visibility_changed"])
  end

  step :clear_user_cache_in_background do
    Contribution.clear_caches_for_user(repository.user, context: "visibility_repository_orchestration")
  end

  step :lock_repo do
    repository.lock_excluding_descendants!(Repository::LockDependency::MOVING)
  end

  step :lock_forks do
    # lock forks when toggling from private to public
    if data[:extract_forks]
      repository.forks.select(&:private?).each(&:lock_for_move)
    end
  end

  step :drop_advisory_collaborators do
    if repository.private?
      Repository::AdvisoryAbilityManager.change_visibility(repository: repository)
    end
  end

  step :lock_repo_to_set_permissions do
    # obtain a lock on manipulating the repo on disk or bail out. then perform the heavy operations.
    cache_lock_obtain("lock:toggle-perm:#{repository.id}", 1.hour)
  end

  step :extract, max_attempts: 1 do
    network = T.must(repository.network)
    if data[:detach]
      block_on_orchestration(RepositoryOrchestration.extract(repository, actor:, include_forks: false, parent: self))
    elsif data[:extract_forks]
      forks = repository.forks.select(&:private?)
      forks.each do |fork|
        block_on_orchestration(RepositoryOrchestration.extract(fork, actor:, parent: self))
      end
    end
  end

  step :wait_for_extract do
    # Make sure that the user hasn't changed visibility since we started, and if they have, abort.
    # it's possible the Extract orchestrations above failed, so we failed. Then someone tried to restart us days later.
    if newer_orchestration?
      return :abandoned, "Newer orchestration exists"
    end
  end

  # this step was formerly most of the ToggleRepoPermission class
  step :toggle_permission do
    repository.reload_network
    repository.enable_or_disable_shared_storage if repository.public?
    repository.network&.enable_or_disable_shared_storage_for_private_repositories

    repository.update_organization

    # close any pull requests sent from this repo on public repositories
    if repository.private?
      repository.pull_requests_as_head.open_pulls.each do |pull| # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        next if pull.repository.private?
        pull.close(owner)
      end
    end

    # now check to see if the repo permission was toggled into some other
    # state while we were working. if so, abort. We don't want to queue up another toggle job.
    if FeatureFlag.vexi.enabled?(:repos_domain_reload, default: false)
      Repositories.domain.reload(repository)
    else
      repository.reload
    end
    if repository.visibility != new_visibility
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
    repository.network&.sync_org_owned_private_network_with_forks
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

  step :cancel_exemption_requests do
    return unless repository.feature_flag_enabled_or_raise?(:repo_policy_bypass) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
    Exemptions::ExemptionRequest.pending_bypass_requests_for_operation(repository, "change_visibility").each { |request| request.cancelled! }
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
      repository.tag_protection_states.destroy_all
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
    page = repository.page
    page.restore_deleted if repository.plan_supports?(:pages) && page && page.deleted_at

    if !repository.private?

      if repository.org_members_can_create_public_pages?
        repository.rebuild_pages(actor) if page&.update(public: true)
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

    repository.async_purge_subscribers(restorable_id: data[:restorable_id])
    repository.enqueue_set_license_job
    repository.instrument :access, access: new_visibility.to_sym, actor: actor, previous_visibility: data[:old_visibility]
  end

  step :invalidate_caches do
    repository.invalidate_nwo_cache(Repositories::Cache::InvalidateOn::Visibility)
  end

  ##########################################################
  ### steps end
  ##########################################################

  attr_writer :actor

  def actor
    return @actor if defined?(@actor)

    @actor = User.find_by(id: data[:actor_id])
  end

  sig { returns(Repository) }
  def repository
    T.must(super)
  end

  # The owner could be deleted after the orchestration is queued
  sig { returns(T.nilable(User)) }
  def owner
    repository.owner
  end

  def new_visibility
    @new_visibility ||= data[:new_visibility] || repository.toggled_visibility
  end

  # this method is here so tests can stub/mock it
  def detach_repo?
    repository.public? && repository.root.public? && T.must(repository.network).active_and_deleted_repositories.count > 1
  end

  sig { returns(T::Boolean) }
  def can_retry_failed_orchestration?
    # call the base class method to do common checks
    return false unless base_can_retry_failed_orchestration?

    if repository.visibility != new_visibility
      # If repo visibility has not changed, there's no reason to rerun this orchestration, versus starting a new one.
      # We shouldn't be changing the repo's visibility without their consent. Maybe they changed their mind.
      # Instead, the user should try again to change the visibility at a time convenient to them.
      end_orchestration(:abandoned, "visibility unchanged")
      return false
    end
    true
  end

  sig { returns(T::Boolean) }
  def retry_failed_orchestration
    return false unless can_retry_failed_orchestration?

    if self.step_name == "wait_for_extract"
      # If there are any failed or skipped child orchestrations, see if they are retryable
      failed = child_orchestrations(self.id).where(state: %w[failed skipped])

      # check if the extracts are retryable. If they are not retryable, they'll be set to :abandoned
      retryable = failed.select { |e| e.can_retry_failed_orchestration? }

      # NOTE: It's odd/wrong that we ignore the non-retryable failed children here.
      # But the reality is the damage is already done. This repo's visibility has already been changed.
      # So the best we can do is fix the extracts that are fixable. That's better than leaving the fixable ones in a bad state too.

      if retryable.any?
        # Reset our state to waiting. Our children will kick us when they're done
        self.update!(attempts: 0, state: "waiting", error_message: nil)

        retryable.each do |orchestration|
          orchestration.retry_failed_orchestration
        end
        return true
      end
    end

    self.update!(attempts: 0, state: "running", error_message: nil)
    RepositoryOrchestration.restart_stuck_orchestration(self)
    true
  end

  def stop_after_waiting?(unsuccessful_children)
    # Ignore abandoned children. We don't need to fail because of them
    unsuccessful_children = unsuccessful_children.reject { |c| c.abandoned? }

    unsuccessful_children.any?
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
      if owner&.at_private_repo_limit?
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

    if owner&.emu_creating_public_repo?(new_visibility)
      repository.errors.add(:visibility, "Enterprise managed resources can't have #{Repository::PUBLIC_VISIBILITY} visibility")
    end

    if new_visibility == Repository::INTERNAL_VISIBILITY
      if !owner&.organization?
        repository.errors.add(:visibility, "Only organization-owned repositories can have #{Repository::INTERNAL_VISIBILITY} visibility")
      end
      if !owner&.business
        repository.errors.add(:visibility, "Only organizations associated with an enterprise can set visibility to #{Repository::INTERNAL_VISIBILITY}")
      end
    end

    if repository.errors.any?
      errors.add(:base, :visibility, message: repository.errors.full_messages)
    end

    if repository.lock_on_transferring_ownership?
      errors.add(:base, :visibility, message: "The repository is locked due to an ownership transfer.")
    end

    if namespace = RetiredNamespace.for(owner: owner&.name, name: repository.name)
      errors.add(:visibility, "Repository namespace has been retired.") unless namespace.claimable_by?(owner)
    end
  end

  def visibility_change_restricted_by_trade_controls?
    # `restriction_tier_allows_feature?`is true for:
    # - the owner doesn't have any trade restrictions
    # - when the type of trade restriction allow free private repos (Tier 0)
    owner_has_restrictions = !owner&.restriction_tier_allows_feature?(type: :repository)

    actor_is_restricted = actor&.has_any_trade_restrictions?
    org_sdn_restricted = owner&.organization? && owner&.has_commercial_interaction_restriction?(feature_type: :repository_visibility_change)
    paid_org_actor_is_restricted = actor_is_restricted && owner&.organization? && owner&.charged_account?
    non_org_actor_is_restricted = actor_is_restricted && owner&.user?

    owner_has_restrictions || paid_org_actor_is_restricted || non_org_actor_is_restricted || org_sdn_restricted
  end

  sig { returns(T::Array[T.nilable(String)]) }
  def logged_disallowed_concurrent_orchestration_types
    COMMON_DISALLOWED_CONCURRENT_ORCHESTRATIONS
  end

  # These orchestrations are allowed to run concurrently with VisibilityRepositoryOrchestration because they can
  # all be triggered from the single endpoint to edit a repo.
  ALLOWED_CONCURRENT_ORCHESTRATIONS = %w[
    ArchiveRepositoryOrchestration
    UnarchiveRepositoryOrchestration
    RenameRepositoryOrchestration
  ].freeze

  sig { returns(T::Array[T.nilable(String)]) }
  def disallowed_concurrent_orchestration_types
    COMMON_DISALLOWED_CONCURRENT_ORCHESTRATIONS - ALLOWED_CONCURRENT_ORCHESTRATIONS
  end
end
