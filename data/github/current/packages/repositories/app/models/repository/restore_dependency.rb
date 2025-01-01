# typed: true
# frozen_string_literal: true

module Repository::RestoreDependency
  extend T::Helpers

  requires_ancestor { Repository }

  BATCH_SIZE = 100

  module ClassMethods
    extend T::Helpers

    requires_ancestor { T.class_of(Repository) }

    # Public: Restores the archived record.
    #
    # id    - Integer ID of the Repository.
    # actor - optional User who restored the repo
    # synchronous - whether to run the orchestration synchronously or not
    #
    # Returns the restored Repository.
    def restore(id, actor: nil, synchronous: true, override_restorable: false)
      repo = Repository.find_by(id: id)
      if repo.nil?
        raise ActiveRecord::RecordNotFound if synchronous
        return false
      end

      orchestration = RepositoryOrchestration.restore(repo, actor:, override_restorable:)
      return nil unless orchestration.valid?
      orchestration.execute(synchronous:)

      if orchestration.failed?
        if synchronous
          return repo if repo.active?
          return nil
        else
          return false
        end
      end

      repo
    rescue Repository::StorageAdapter::RemoteShardedStorageAdapter::RestoreError => exception
      Failbot.push "gh.repo.id": id
      GitHub.logger.error(
        :exception => exception,
        "code.namespace" => self.class.name,
        "code.function" => __method__,
        "gh.repo.restore.error.data" => exception.data,
        "gh.repo.id" => id
      )
      raise
    rescue => exception # rubocop:todo Lint/GenericRescue
      raise
    end

    def can_restore?(repo, override_restorable: false)
      # Return early if there is a RetiredNamespace matching this repo's name and owner,
      # and the owner has changed since the repo was retired.
      # https://github.com/github/communities/issues/1789
      if GitHub.flipper[:disallow_retired_namespace_restores].enabled?(repo.owner)
        if ns = RetiredNamespace.for(owner: repo.owner.login, name: repo.name)
          if !ns.claimable_by?(repo.owner)
            repo.errors.add(:retired_namespace, "Repository namespace has been retired.")
            return false
          end
        end
      end

      if repo.nil?
        return false
      elsif repo.owner.organization? && repo.owner&.soft_deleted?
        repo.errors.add(:deleted_owner, "Repository belongs to a deleted organization.")
        return false
      elsif !Repository.can_restore_soft_deleted_repo?(repo, override_restorable:)
        return false
      end

      limiter = RepositoryLimit.new(repo.owner)
      if limiter.hard_limited?
        repo.errors.add(:owner, "Owner is over repository limit.")
        return false
      end

      true
    end

    def can_restore_soft_deleted_repo?(repo, override_restorable: false)
      if Repository.find_by(id: repo.id, active: true)
        repo.errors.add(:repo_exists, "Repository already restored.")
        return false
      end

      if repo.network && repo.network.root
        fork = repo.network.find_fork_for(repo.owner)
        if fork && fork.id != repo.id && !repo.owner.organization?
          repo.errors.add(:fork_exists_in_network, "This account has an existing fork in the deleted repository's network.")
          return false
        end
      end

      if repo.owner.repositories.find_by_name(repo.name)
        repo.errors.add(:repo_with_same_name_exists, "Repository already exists on this account.")
        return false
      end

      if !repo.restorable? && !override_restorable
        repo.errors.add(:repo_not_restorable, "Repository has been marked as not restorable.")
        return false
      end

      true
    end
  end

  mixes_in_class_methods(ClassMethods)

  # Restore a repository currently marked as deleted to an active state. Ensures
  # that all related objects are present and valid and that parent relationships
  # are valid.
  #
  # The unhide operation performs all database operations within a transaction.
  # If the record cannot be returned to a good state, all changes are rolled
  # back and the record will still be marked as deleted.
  #
  # Returns nothing.
  # Raises RuntimeError if the record is not marked as deleted or if the owner
  # no longer exists.
  def unhide
    fail "Refusing to unhide repository not marked as deleted" if active?
    fail "Refusing to unhide repository with no owner" if owner.nil?
    # We intentionally *don't* check restorable? here, assuming nobody will
    # be calling unhide without going through restore first.

    transaction do
      # fix up attributes that may be stale since the repository was hidden
      unhide_parent
      unhide_network
      update_organization
      unhide_repository_advisories_on_restore

      # mark record as not deleted only after the record is in a good state
      update(active: true, deleted_by_user_id: nil, deleted_at: nil)

      # TODO re-enable validation when https://github.com/github/github/pull/141281 ships
      save!(validate: false)
    end
  end

  # Internal: ensure a valid parent attribute is set. This checks that the
  # existing parent_id points to a valid repository in the same network or
  # adjusts it to the root repo or nil if not. Called from #unhide within a
  # transaction.
  def unhide_parent
    if parent && parent&.active? && parent&.network_id == network_id
      # leave parent attribute alone, it looks good
    elsif network && network&.root && network&.root&.active? && network&.root != self
      # reparent to the network root since our original parent is gone/inactive
      self.parent = network&.root
    else
      self.parent = nil
    end
  end

  # Internal: ensure a valid repository_networks record exists for this record.
  # Called from #unhide within a transaction. The new network must be created
  # with the original network_id stored on the archived record or the repository
  # location on disk will change and mess with git restores.
  def unhide_network
    if network
      if self.parent.nil? && network&.root != self
        # reparent the network to ourselves, since we already determined we are the root in #unhide_parent
        network&.root = T.cast(self, Repository) # rubocop:disable GitHub/AvoidCast
        network&.save!
      end
      return
    end

    GitHub.dogstats.increment("repo_restore.unhide_network_create")

    # The network needs initialization in dotcom. In enterprise, the records are already
    # initialized since we just leave things on disk when we delete them.
    create_network(root: self, network_id: network_id, needs_dgit_initialization_after_commit: !GitHub.enterprise?)
  end

  def instrument_restore(initiated_by, actor)
    staff_action = !initiated_by.include?("repos/restore")
    payload = restore_payload(actor, staff: staff_action)
    action = staff_action ? "staff.repo_restore" : "repo.restore"

    limiter = RepositoryLimit.new(T.must(owner))
    if limiter.enabled?
      if limiter.soft_limited?
        limiter.instrument_limit_warning
      end
      if limiter.hard_limited?
        limiter.instrument_limit_reached
      end
    end

    GitHub.instrument action, payload

    # Instruments a push to kafka topic when a repository is restored
    GlobalInstrumenter.instrument("repository.restored", {
      restored_repository: self,
      actor: actor,
    })
  end

  # Instruments a restored repo as a RESTORED event for Blackbird code search indexing
  def instrument_search_restore(additional_payload = {})
    payload = {
      change: :RESTORED,
      repository: self,
      owner_name: self.owner&.name,
      updated_at: Time.now.utc,
      ref: "refs/heads/#{self.default_branch}",
    }.merge!(additional_payload)

    GlobalInstrumenter.instrument("search_indexing.repository_changed", payload)
    GitHub.dogstats.increment("geyser.repo_changed_event.published", tags: ["change_type:restored"])
  end

  def restore_payload(actor, staff: false)
    payload = { repo: self }
    payload.merge!(restore_actor_payload(actor, staff: staff))
    payload.merge!(owner&.event_context)
  end

  def restore_actor_payload(actor, staff:)
    if actor && !staff
      { actor: actor.display_login, actor_id: actor.id }
    else
      GitHub.guarded_audit_log_staff_actor_entry(actor)
    end
  end

  def restore_packages(actor, deleted_at: nil)
    packages.where("deleted_at >= ?", deleted_at || self.deleted_at).in_batches(of: BATCH_SIZE).each do |batch|
      batch.each do |package|
        package.restore(actor: actor)
      end
    end
  rescue StandardError => e # rubocop:todo Lint/GenericRescue
    # We never want a failure in package restoration to block repo restoration, so catch all errors
    Failbot.report(e)
    GitHub.logger.error(
      :exception => e,
      "code.namespace" => self.class.name,
      "code.function" => __method__,
      "gh.repo.id" => self.id,
    )
  end

  # Removes and outside collaborators from the repository which no longer meet the two
  # factor requirements. This can happen if either the collaborator disables two factor
  # while the repository is deleted, or the organization enables two factor while the repository
  # is deleted.
  #
  # actor - The actor restoring the repo.
  #
  # Returns nothing.
  def remove_outside_collaborators_with_two_factor_disabled(actor)
    return unless organization&.two_factor_requirement_enabled?
    # destroy function after https://github.com/github/authorization/issues/4526
    members.where(id: outside_collaborators_ids).in_batches(of: BATCH_SIZE).each do |batch|
      batch.reject { |member| member.two_factor_authentication_enabled? }.each do |member|
        remove_member(member, actor)
      end
    end
  end

  def safe_to_restore
    deleted? && deleted_at.present? && Time.at(deleted_at) < 10.minutes.ago
  end

  def has_current_restore_job?
    status = Restoration::RepositoryRestoreStatus.for(repository_id: self.id)
    status.message.present?
  end
end
