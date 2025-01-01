# typed: false
# frozen_string_literal: true

module Repository::TransferDependency
  # Check if this repo can be transferred to a new owner.
  #
  # Returns a boolean indicating transferrability
  def can_transfer_ownership?
    return false if trade_controls_read_only?
    !private_fork?
  end

  def pending_transfer
    transfers.first
  end

  def pending_transfer?
    !pending_transfer.nil?
  end

  # Public: Transfer ownership of this repository to the given user.
  #
  # user              - the user or organization to transfer this repository to.
  # target_teams      - (optional) the teams to add this repository to during the
  #                     transfer when transferring into an organization.
  # actor             - the user who is initiating the transfer.
  # notify_target     - passing true will send the user an email letting them know that the repo was transferred
  #                     to them.
  # custom_properties - Custom properties to be set on the repository
  def async_transfer_ownership_to(user, target_teams: [], actor:, notify_target: false, new_name: nil, custom_properties: nil)
    return false unless can_transfer_ownership?

    # don't let people get free private repos via transfer
    return false if private? && user.at_private_repo_limit?

    # disallow transfer when user has blocked repo's owner
    return false if owner.blocked_by?(user)

    orchestration = RepositoryOrchestration.transfer(
      repository,
      actor_id: actor.id,
      new_owner_id: user.id,
      team_ids: target_teams.collect(&:id),
      notify_target: notify_target,
      new_name: new_name,
      custom_properties: custom_properties,
    )

    orchestration.execute
    true
  end

  # Internal: Dangerous! Changes the owner of this repository to the passed in
  # user. Should only be called from the TransferRepository job. Please use
  # the public #async_transfer_ownership_to method for all other calls.
  #
  # Example:
  #   We're moving olduser/reponame to newuser/reponame
  #
  #   irb$ repo = Repository.nwo("olduser/reponame")
  #   irb$ user = User.find_by_login("newuser")
  #   irb$ repo.transfer_ownership_to(user)
  #
  # Returns true if the transfer works; false if the new repo already exists or the
  # new owner already owns a fork in the same network.
  def transfer_ownership_to(new_owner, actor:, target_teams: [], new_name: nil)
    orchestration = RepositoryOrchestration.transfer(
      repository,
      actor_id: actor.id,
      new_owner_id: new_owner.id,
      team_ids: target_teams.collect(&:id),
      notify_target: false,
      new_name: new_name
    )

    orchestration.execute(synchronous: true)

    orchestration.succeeded?
  rescue StandardError # rubocop:todo Lint/GenericRescue
    GitHub.dogstats.increment("repository.transfer", tags: ["status:failed"])
    raise TransferFailedError
  end

  TransferFailedError = Class.new(StandardError)

  # Called from TransferRepositoryJob via self.async_transfer_ownership_to
  def instrument_search_transfer_ownership_to(old_owner, additional_payload = {})
    # Return if the new owner for this repo is not eligible for Geyser search
    return if GitHub.flipper[:geyser_denylist].enabled?(self)

    # We don't use eligible_for_geyser_ingest? here because we are checking a
    # subset of the criteria, and in a different order. Be aware of the
    # similarities.
    if !GitHub.flipper[:geyser_denylist].enabled?(self.owner)
      # new owner is eligible for Geyser search treatment, change ownership
      # (results in a "repair" job on backend, deleting old repo docs and
      # reindexing in full)
      payload = {
        change: :OWNER_CHANGED,
        repository: self,
        owner_name: self.owner.name,
        updated_at: Time.now.utc,
        ref: "refs/heads/#{self.default_branch}",
        old_owner_id: old_owner.id,
        publisher: :low_latency,
        actor: actor
      }.merge(additional_payload)
      GlobalInstrumenter.instrument("search_indexing.repository_changed", payload)
    else
      # the new owner isn't eligible for Geyser search - emit a delete for the
      # repo (should ignore "owner" and use "repository.id" on backend)
      payload = {
        change: :DELETED,
        repository: self,
        owner_name: self.owner.name,
        updated_at: Time.now.utc,
        ref: "refs/heads/#{self.default_branch}",
        old_owner_id: old_owner.id, # janky hint of why delete was emitted here
        publisher: :low_latency,
        actor: actor
      }.merge(additional_payload)
      GlobalInstrumenter.instrument("search_indexing.repository_deleted", payload)
    end

    GitHub.dogstats.increment("geyser.repo_changed_event.published", tags: ["change_type:deleted"])
  end

  def update_collaborators(new_owner)
    # Reset all collaborators, we'll rebuild them.
    collaborator_abilities = Authorization.service.direct_abilities_on_subject(subject: self, actor_type: User)
    # Since a role maps to an Ability these actor_ids should already be present in collaborator_abilities
    # we're just being extra careful here by querying user_roles as well
    user_role_ids = UserRole.where(actor_type: "User", target_id: self.id, target_type: "Repository").pluck(:actor_id)
    actor_ids = (collaborator_abilities.map(&:actor_id) + user_role_ids).uniq

    actors = User.where(id: actor_ids)
    actors = Hash[actors.map(&:id).zip(actors)]

    remove_all_members new_owner

    # Do the above member clean up and organization_id updates across the
    # repository network
    remove_members = new_owner.organization? && private?
    descendants.each do |child_repo|
      child_repo.remove_all_members(new_owner) if remove_members
      child_repo.update_organization
    end

    reload # refresh the various associations

    # Restore collaborators
    collaborator_abilities.each do |ability|
      # New owner can't be a collaborator too
      next if actors[ability.actor_id] == new_owner

      # We can't restore read collaborators if the new owner is a user, since
      # user-owned repositories can only have write collaborators and that
      # would increase their access.
      next if new_owner.user? && ability.read?

      # For now, organization-owned repos can grant collaborators any level of
      # access, but user-owned repos can only grant them write access. So, if
      # the new owner is a user, we drop read collaborators and add back the
      # rest of the collaborators as write collaborators (no matter what their
      # original permission was).
      action = new_owner.organization? ? ability.action : :write

      add_member(actors[ability.actor_id], new_owner, action: action, override_lock: true)
    end
  end

  # Checks if user can transfer the repository.
  #
  # Returns a reason if the user cannot, otherwise nil
  #
  # user - user attempting to transfer the repository
  #
  # Returns symbol or nil.
  def cannot_transfer_repository_reason(user)
    :prevented_by_ruleset unless RulesEngine::RepositoryActionEvaluator.can_transfer_repository?(self, user)
  end

  def transfer_in_progress?
    RepositoryOrchestration.transfer_type.where(repository: self).active.any?
  end
end
