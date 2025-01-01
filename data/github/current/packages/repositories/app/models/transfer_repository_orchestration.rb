# typed: false
# frozen_string_literal: true

class TransferRepositoryOrchestration < RepositoryOrchestration
  include GitHub::Memoizer

  # define a wrapper around RepositoryOrchestration#step
  # to ensure that certain transfer steps have these restrictions in place
  def self.transfer_step(name, &block)
    method_name = "#{name}_transfer_step"
    define_method(method_name, block)

    step(name) do
      GitHub.stratocaster.disable do
        public_send(method_name)
      end
    end
  end

  step :validate do
    # disallow transfer when user has blocked repo's owner
    return :skipped if repository.owner.blocked_by?(new_owner)

    # disallow transfer when user (not organization) owns a repo in the same network
    return :skipped if new_owner.user? && repository.network.find_fork_for(new_owner)

    # check if user already has repo with same name or new name (but not in the same network)
    if new_owner.find_repo_by_name(new_name.presence || repository.name)
      GitHub.dogstats.increment("repository.transfer.actual_or_potential_name_conflict", tags: ["location:orchestration"])
      return :skipped, "Repo with same name already exists"
    end

    # disallow transfer when blocked by a ruleset
    return :skipped, "Ruleset(s) are preventing this repository from being transferred." unless RulesEngine::RepositoryActionEvaluator.can_transfer_repository?(repository, actor)

    # Check if custom properties are valid
    if properties_values_manager.present?
      if new_owner.can_edit_organization_custom_properties_values?(actor)
        validation_errors = properties_values_manager.validate_properties(custom_properties)

        return :skipped, validation_errors.map(&:error_message).join("\n") if validation_errors.any?
      else
        return :skipped, "User does not have permission to set custom properties"
      end
    end
  end

  step :record_data do
    data[:old_nwo] = repository.nwo
    data[:old_nwo_with_display] = repository.name_with_display_owner
    data[:old_owner_id] = repository.owner.id
    data[:old_licensing_enabled] = repository.licensing_enabled?
    data[:installation_ids] = IntegrationInstallation.with_repository(repository).pluck(:id)
    data[:old_licensing_enabled] = repository.licensing_enabled?
    data[:old_name] = repository.name

    # Select Apps that should be reinstalled after the transfer
    data[:integration_ids_to_reinstall_after_transfer] = installations.select do |i|
      i.should_follow_moved_repo?(new_owner: new_owner)
    end.map(&:integration_id)
  end

  # Make sure the old owner can't change the repo name between the :check_for_retired_namespace
  # and :update_owner steps.
  #
  # See https://github.com/github/search-and-flywheel/issues/300 for more details.
  step :lock_owner_namespace do
    if GitHub.flipper[:repo_transfer_owner_lock].enabled?(repository.owner)
      Repositories::RepositoryOwnerLock.acquire_rename_lock(owner_id: data[:old_owner_id])
    end
  end

  step :lock_repo do
    repository.lock_excluding_descendants!(Repository::LockDependency::TRANSFERRING_OWNERSHIP)
  end

  job_start

  step :lock_repo_descendants do
    repository.lock_descendants!(Repository::LockDependency::TRANSFERRING_OWNERSHIP, postorder: true)
  end

  transfer_step :remove_installations do
    # Remove all of the IntegrationInstallations from the repository before transferring
    repository.remove_from_integration_installations(editor: old_owner, installations: installations, entry_point: :transfer_repository_orchestration_remove_installations)
  end

  transfer_step :remove_programmatic_fine_grained_permissions do
    # Remove all other Permission records
    repository.remove_programmatic_fine_grained_permissions(entry_point: :transfer_repository_orchestration_programmatic_fine_grained_permissions)
  end

  transfer_step :remove_linked_projects do
    # Remove all of the linked projects from the repository.
    # Do this before changing the owner of the repo.
    repository.project_repository_links.destroy_all
  end

  transfer_step :remove_custom_properties do
    # The relationship between repositories and custom properties is one to one right now.
    # Therefore batching is not necessary.
    CustomProperties::Public.destroy_all_properties(repository)
  end

  transfer_step :destroy_protected_branches_bypassers do
    # This must be done before updating the owner, because some operations are only allowed for org owned repositories.
    return if repository.protected_branches.empty?

    repository.protected_branches.each do |protected_branch|
      protected_branch.skip_branch_protection_enabled_check

      ProtectedBranch.transaction do
        protected_branch.clear_branch_actor_allowances(:force_push)

        if repository.in_organization?
          protected_branch.clear_branch_actor_allowances(:pull_request)
          protected_branch.clear_dismissal_restrictions
          protected_branch.replace_authorized_actors(user_ids: nil, team_ids: nil, integration_ids: nil) if protected_branch.has_authorized_actors?
        end

        protected_branch.save!
      end
    end
  end

  transfer_step :destroy_ruleset_bypassers do
    repository.rulesets.each do |ruleset|
      # Remove bypass actors to avoid leaking data to the new owner.
      ruleset.upsert_bypass_actors([])

      # Ignore validation errors. We don't want to fail the transfer because of this.
      # The rulesets may already be invalid, and deleting the bypass actors won't affect that.
      # Plus the existing validations are based on the current owner, not the new owner, so it's likely to be wrong.
      # Rulesets are validated when enforced and will be disabled if invalid. The user can clean them up later.
      ruleset.save!(validate: false)
    end
  end

  transfer_step :reset_billed_storage do
    if repository.has_lfs_files?
      repository.reset_billed_lfs_storage_usage
    end
  end

  # Run this as a last chance to catch retired namespace collisions before updating the owner,
  # to prevent race conditions where eg. an attacker renames the new_owner account after the
  # transfer request went through and started the orchestration.
  transfer_step :check_for_retired_namespace do
    if namespace = RetiredNamespace.for(owner: new_owner.reload.display_login, name: new_name || repository.reload.name)
      return :failed unless namespace.claimable_by?(new_owner)
    end
  end

  transfer_step :update_owner do
    Repository.transaction do
      if new_name.present?
        repository.update!(owner: new_owner, name: new_name)
      else
        repository.update!(owner: new_owner)
      end
      repository.network.reload # to make sure pullable_by checks pick up the change (via network.owner)
      repository.network.sync_org_owned_private_network_with_forks
      data[:auth_version] = repository.increment_auth_version
    end

    # Public keys are stored in a different DB cluster and can't be part of the same transaction
    repository.public_keys.each(&:save)
  end

  transfer_step :retire_original_namespace do
    if RetiredNamespace.should_retire?(repository, rescue_kv: true)
      RetiredNamespace.retire(owner: old_owner, name: repository.name)
    end
  end

  # After the owner has been updated, it's safe to release the lock - and needed in case later steps
  # need to create their own lock.
  transfer_step :unlock_owner_namespace do
    return unless GitHub.flipper[:repo_transfer_owner_lock].enabled?(repository.owner)
    Repositories::RepositoryOwnerLock.release_rename_lock(owner_id: data[:old_owner_id]) rescue nil
  end

  transfer_step :reinstall_integrations do
    IntegrationInstallation::Reinstall.on_repository(
      repository:,
      new_owner: new_owner,
      integrations: integrations_to_reinstall.to_a,
      entry_point: :transfer_repository_orchestration_reinstall_integrations
    )
  end

  transfer_step :setup_redirect do
    repository.redirect_from_previous_location(data[:old_nwo])
  end

  transfer_step :add_new_teams do
    # Add new teams before updating owning org, because updating owning org will remove
    # the repo from any teams it is on
    if new_owner.organization?
      # give access to the specified teams
      target_teams.each do |team|
        team.add_repository(repository, :pull, allow_different_owner: true)
      end
    end
  end

  transfer_step :update_owning_org do
    repository.update_organization(inline_fork_cleanup: true, remove_collaborators: false)
  end

  transfer_step :update_collaborators do
    # try to proceed anyway after hitting 5 attempts
    if attempts < 5
      # Transferring repos generates a lot of ability grants which can cause replication delay.
      # Ability::Grant throttles on Mysql1 so let's wait until that is in a good state before updating abilities.
      delay = Freno.client.replication_delay(store_name: ApplicationRecord::IamAbilities.cluster_name)
      raise Freno::Throttler::Error.new if delay > 0.5
    end

    repository.update_collaborators(new_owner)
  end

  transfer_step :move_packages do
    repository.packages.each do |package|
      package.transfer(old_owner: old_owner, new_owner: new_owner, actor: actor)
    end

    Packages::SyncPackagePermsOnRepoChangeJob.perform_later(repository: repository)
  end

  transfer_step :move_actions_artifacts do
    repository.actions_artifacts.find_each do |action_artifact|
      action_artifact.transfer(old_owner: old_owner, new_owner: new_owner)
    end
  end

  transfer_step :add_new_owner_as_member do
    if old_owner.user?
      # transferring user still has access, but the new owner can remove
      repository.add_member(old_owner, new_owner, override_lock: true)
    end
  end

  transfer_step :correct_project_cards do
    repository.correct_project_cards(old_owner: old_owner)
  end

  transfer_step :unpublish_page do
    if repository.feature_enabled?(:pages_soft_delete_on_repo_transfer)
      return unless repository.page
      repository.page.delete_or_restore_to_match_plan!
    else
      repository.unpublish_page unless repository.plan_supports_pages?
    end
  end

  transfer_step :reset_page_subdomain do
    repository.page&.set_subdomain_to_match_nwo if repository.plan_supports_pages?
  end

  transfer_step :destroy_protected_tags_and_branches do
    repository.destroy_protected_branches unless repository.plan_supports?(:protected_branches)
    repository.tag_protection_states.destroy_all unless repository.tag_protections_availability == :enabled
  end

  transfer_step :destroy_user_roles do
    UserRole.where(target_id: repository.id, target_type: "Repository").destroy_all
  end

  transfer_step :reassign_pr_owners do
    PullRequest.where(base_repository_id: repository.id).update_all(base_user_id: new_owner.id)
    PullRequest.where(head_repository_id: repository.id).update_all(head_user_id: new_owner.id)
  end

  transfer_step :unpin_profiles do
    # If the old owner is an org, remove the repo from the old owner's pinned repositories.
    # Orgs are only allowed to pin their own public repos.
    if old_owner.organization?
      ProfilePinner.unpin(repository, user: old_owner, viewer: actor)
    end
  end

  transfer_step :unfeature_from_sponsors_profile do
    # If the repository is featured on a Sponsors profile, remove it
    repository.unfeature_from_sponsors_profile
  end

  transfer_step :disassociate_from_org_level_discussions do
    # If the repository was a source repository for org level discussions, destroy that association
    repository.disassociate_from_org_level_discussions
  end

  transfer_step :clear_contribution_caches_for_user do
    # Only clear for the new owner, the old owner gets their cache cleared when being added
    # back as a normal user to the repository
    Contribution.clear_caches_for_user(new_owner)
  end

  transfer_step :instrument_transfer do
    repository.instrument_transfer(
      new_owner: new_owner,
      old_owner: old_owner,
      old_nwo: data[:old_nwo],
      actor: actor,
    )
  end

  transfer_step :update_nwo_file do
    # update the nwo file with new owner
    GitHub::Spokes.client.write_nwo_file(repository, repository.name_with_owner)
  end

  transfer_step :update_advisories do
    RepositoryAdvisory.where(repository_id: repository.id).update_all(owner_id: new_owner.id)

    # This part may require owner rename lock(s), so make sure we've released ours before we get here.
    Repository::AdvisoryAbilityManager.transfer_ownership(repository: repository)
  end

  transfer_step :update_security_products do
    SecurityProduct::ServiceManager.new(repository).toggle_services_on_repository_owner_changed(actor: actor, previous_owner: old_owner)
  end

  transfer_step :destroy_transfers do
    repository.transfers.destroy_all
  end

  transfer_step :queue_billing_jobs do
    if data[:old_licensing_enabled]
      Licensing::SnapshotLicensesJob.perform_later(old_owner.business)
    end

    if repository.licensing_enabled?
      Licensing::SnapshotLicensesJob.perform_later(new_owner.business)
    end
  end

  transfer_step :update_business_license_usage do
    old_owner.business&.update_license_usage
    new_owner.business&.update_license_usage if new_owner.business&.id != old_owner.business&.id
  end

  transfer_step :update_search_indices do
    # Update es index for listed actions if the repository has any listed action
    if repository.listed_action.present?
      repository.listed_action.synchronize_search_index
    end
  end

  transfer_step :transfer_actions_cache_owner do
    # Update owner of actions cache usage if it exists
    ActionsCacheUsageHelper.transfer_cache_owner(repository, new_owner)
  end

  transfer_step :add_custom_properties do
    if properties_values_manager.present? && new_owner.can_edit_organization_custom_properties_values?(actor)
      properties_values_manager.set_properties_for([repository], custom_properties, actor: actor)
    end
  end

  transfer_step :instrument_transfer_complete do
    GitHub.dogstats.increment("repository.transfer", tags: ["status:succeeded", new_name.present? ? "rename:true" : "rename:false"])

    GlobalInstrumenter.instrument(
      "repository_transfer.completed",
      { repository: repository, requester: actor, target: new_owner, previous_owner: old_owner }
    )
  end

  transfer_step :publish_transfer_orchestration_complete do
    message = {
      repository_id: repository.id,
      previous_owner: Hydro::EntitySerializer.user(old_owner),
      new_owner: Hydro::EntitySerializer.user(new_owner),
      previous_name: old_name,
      new_name: new_name || old_name,
      new_visibility: Hydro::EntitySerializer.enum_from_string(repository.reload.visibility)
    }

    publish_hydro_event(message: message, schema: "github.repositories.v1.Transferred")
  end

  transfer_step :instrument_repo_added_to_installations do
    # fire repo added to installation webhook
    repository.instrument_repo_added_to_installations_across_all_repositories(actor: actor)
  end

  transfer_step :instrument_search_transfer_ownership do
    # safe to trigger an update to the search index now
    repository.instrument_search_transfer_ownership_to(old_owner, { auth_version: data[:auth_version] })
  end

  step :unlock_from_transferring_ownership do
    if repository.lock_on_transferring_ownership? || repository.locked_on_nil?
      if repository.locked_on_nil?
        GitHub.dogstats.increment("repository.transfer.unlocking_from_nil_lock_reason")
        log_info("Unlocking repository from nil lock_reason.")
      end
      repository.unlock_including_descendants!(postorder: true)
    end
  end

  transfer_step :update_media_blob_status do
    Media::Blob.update_status_for_repository_transfer(repository, new_owner: new_owner, old_owner: old_owner)
  end

  transfer_step :notify_target do
    if data[:notify_target]
      AccountMailer.immediate_repository_transfer(repository, actor, new_owner, old_nwo_with_display).deliver_now
    end
  end

  transfer_step :queue_sponsorables_jobs do
    if GitHub.sponsors_enabled? && SponsorsListing.for_sponsorable_user_or_org([old_owner.id, new_owner.id]).any?
      UpdateOwnerRepositorySponsorablesJob.perform_later(sponsorable_id: old_owner.id)
      UpdateOwnerRepositorySponsorablesJob.perform_later(sponsorable_id: new_owner.id)
    end
  end

  step :instrument_rename do
    if new_name.present?
      repository.instrument :rename, old_name: old_name, actor: actor

      GlobalInstrumenter.instrument("repository.rename", {
        actor: actor,
        repository: repository,
        previous_name: old_name,
        current_name: new_name,
      })
    end
  end

  on_end_orchestration do |_, _|
    # Make sure that any owner namespace locks are released if the orchestration fails between
    # acquiring a lock and releasing it.
    return unless GitHub.flipper[:repo_transfer_owner_lock].enabled?(repository.owner)
    Repositories::RepositoryOwnerLock.release_rename_lock(owner_id: data[:old_owner_id]) rescue nil
  end

  memoize def old_owner
    User.find(data[:old_owner_id])
  end

  memoize def new_owner
    User.find(data[:new_owner_id])
  end

  memoize def target_teams
    new_owner.teams.where(id: data[:team_ids]) || []
  end

  memoize def installations
    IntegrationInstallation.where(id: data[:installation_ids])
  end

  memoize def integrations_to_reinstall
    Integration.where(id: data[:integration_ids_to_reinstall_after_transfer])
  end

  memoize def actor
    User.find(data[:actor_id])
  end

  memoize def old_nwo
    data[:old_nwo]
  end

  memoize def old_nwo_with_display
    data[:old_nwo_with_display]
  end

  memoize def old_name
    data[:old_name]
  end

  memoize def custom_properties
    data[:custom_properties]
  end

  memoize def properties_values_manager
    return unless new_owner.organization? && custom_properties.present?

    definitions_manager = CustomProperties::Public.definitions_manager(new_owner)
    CustomProperties::Public.values_manager(definitions_manager)
  end

  memoize def new_name
    return unless data[:new_name]
    normalized_name = EntityName.normalize(data[:new_name])
    return unless normalized_name != old_name

    normalized_name
  end
end
