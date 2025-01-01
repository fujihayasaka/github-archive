# typed: true
# frozen_string_literal: true

# Repository removal and destruction
#
# == How to delete a repository
#
# The preferred way to delete a repository in all cases is with the Repository#remove
# method.
#
#   deleter = repository.owner # or whoever
#   repository.remove(deleter)
#
# This method should be fully idempotent and may be called repeatedly in cases
# where a job fails. If removal fails reliably for a repository in any state
# it's a bug and the logic must be modified to handle removing repositories in
# that state.
#
# == Stages of removal
#
# Deleting repositories is complicated due to a variety of factors. The
# operation cascades into a large number of dependent tables. Parent/fork
# relationships must be maintained when intermediate repositories are removed.
# Private repository deletion may bring in financially dependent forks.
#
# Because deletion can be fairly time consuming and resource intense, the
# process happens over two stages. The methods defined in this file model
# these stages:
#
# - The #hide stage runs *within* a web/API request and is designed to be fast,
#   lightweight, and fully transactional. All dependent repositories table
#   records are marked deleted = 1 but no heavy moving of records into archive
#   tables is performed.
#
# - The #archive stage runs within the RepositoryDelete job. This purges git and
#   auxiliary data and then copies repositories table records along with a ton
#   of dependent table (issues, issue_comments, pull_requests, etc etc etc)
#   records into archive tables via SELECT INTO and then deletes the active table
#   records. The entire operation runs within a single transaction so records
#   are either fully moved or not moved at all.
#
# These methods should not typically be called outside of the main #remove
# method.
#
# == Dependent repositories and cascading deletes
#
# When a private repository is removed, it may be necessary to delete a number
# of other repositories in the same network that depend on the repository
# financially. This is determined based on the network root's owner. When a
# private network root is deleted, all forks that descend from that repository
# must also be deleted.
#
# Note that deleting public forks never cascades to child repositories, nor does
# deleting private repositories that are forks of a plan owning repository. Only
# the immediate repository is removed and any forks reparented in those cases.
#
# Since many of a repository's dependent relationships are deleted in the
# background rather than immediately during the initial #archive transaction,
# it's possible for a restore attempt to occur before a repository's related
# tables have been cleared of the associated data. If this occurs, since
# restores happen with transactions of their own, it's likely that an insert
# while restoring archived dependents will fail with a unique key violation. In
# that instance, the restore as a whole will fail.
#
# It's also possible that the dependent deletion jobs didn't succeed and have
# left orphaned data in the tables that is blocking a restore. If this occurs,
# the data-quality-scan script can help. Consult @github/data-quality if you
# have questions.
#
# == Transactions and network integrity
#
# The parent_id column is especially tricky to deal with when deleting
# repositories. A repository not marked as deleted must never refer to a
# repository marked as deleted, although the opposite is not true. There
# must be exactly one non deleted repository with a NULL parent_id in each
# network to act as the root. When deleting intermediate and root repositories,
# any remaining repositories must be reparented so that basic integrity is not
# broken.
#
# All of this is handled during the #hide stage, which marks all effected
# repositories as deleted and reparents remaining repositories within a single
# transaction.
module Repository::RemovalDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { Repository }

  PREVENT_DELETION_THRESHOLD = 5.minutes.freeze

  # Hide the repository and all dependent objects, and queue a job to perform
  #   the task of deletion.
  #
  # deleter - User that is initiating the deletion. Must be specified.
  # instrument - Publish removal event
  # force - Remove even if there is a pending deletion or the repo looks already deleted
  # synchronous - Complete removal synchronously rather than enqueuing a background job
  # delete_forks_inaccessible_to - the id of a repo in the network that forks should have access to
  #
  # When a fork is removed, its children have their parent set to the parent of the removed fork.
  # The array of these reparented repos is returned.
  def remove(deleter, instrument: true, force: false, synchronous: false, delete_forks_inaccessible_to: nil, send_email: false, prevent_concurrency: false, staff: false)
    o = RepositoryOrchestration.delete(T.cast(self, Repository), actor: deleter, delete_forks_inaccessible_to:, send_email:, prevent_concurrency:, staff:) # rubocop:todo GitHub/AvoidCast
    o.execute(synchronous: synchronous, force: force)
  end

  # Checks if user can delete the repository.
  #
  # Returns a reason if the user cannot, otherwise nil
  #
  # user - user attempting to delete the repository
  #
  # Returns symbol or nil.
  sig { params(user: User, persist_results: T::Boolean).returns(T.nilable(Symbol)) }
  def cannot_delete_repository_reason(user, persist_results: false)
    if !RulesEngine::RepositoryActionEvaluator.can_delete_repository?(repository, user, persist_results:)
      return :prevented_by_ruleset
    end
    cannot_delete_or_transfer_repository_reason(user)
  end

  # Checks if user can delete or transfer the repository.
  #
  # Returns a reason if the user cannot, otherwise nil
  #
  # user - user attempting to delete or transfer the repository
  #
  # Returns symbol or nil.
  sig { params(user: User).returns(T.nilable(Symbol)) }
  def cannot_delete_or_transfer_repository_reason(user)
    return :cant_administer unless self.adminable_by?(user)
    return :not_ready_for_writes if T.must(created_at) > PREVENT_DELETION_THRESHOLD.ago && !ready_for_writes?
    return if user.site_admin? && GitHub.enterprise?
    if owner&.organization?
      repo_owner = T.cast(owner, Organization)
      return :ofac_trade_restricted if repo_owner.has_full_trade_restrictions?

      # "Repository deletion and transfer" global business setting description:
      #
      # If enabled, members with admin permissions for the repository will be
      # able to delete or transfer public and private repositories. If disabled,
      # only organization owners can delete or transfer repositories.
      if GitHub.global_business&.members_can_delete_repositories_policy? &&
        !GitHub.global_business&.members_can_delete_repositories? &&
        !repo_owner.adminable_by?(user)

        return :cant_delete_repos_on_this_appliance
      end

      return :members_cant_delete_repositories unless repo_owner.members_can_delete_repositories? || repo_owner.adminable_by?(user)
    end

    :ofac_trade_restricted if private? && deletion_restricted_by_trade_controls?(owner)
  end

  # Private: Helper method while we transition between current restrictions and tiered restrictions.
  #
  # Returns Boolean
  def deletion_restricted_by_trade_controls?(owner)
    # Only organizations have tiered restriction for now
    if owner.organization?
      !owner.restriction_tier_allows_feature?(type: :repository)
    else
      owner.has_any_trade_restrictions?
    end
  end

  # Destroy the RepositoryNetwork record when the last repository in the network
  # is deleted. This also deletes the shared storage area from disk when
  # enabled. Called via after_destroy callback.
  def destroy_repository_network
    return if network.nil?
    repo_network = T.must(network)
    return if repo_network.repositories.count > 0
    return if repo_network.deleted_repositories.count > 0
    repo_network.skip_replica_deletion_after_commit = true
    repo_network.destroy
  end

  # All repositories in this network that "depend" on this repository financially.
  # Only private repositories whose owner is the network owner have dependents. The
  # repositories returned are all financed by this repository and thus must be
  # deleted when this repository is deleted.
  #
  # conditions - Hash of extra conditions to apply when querying for dependent
  #              repositories. This is typically used to select or filter out
  #              deleted repositories.
  #
  # Returns an Array of all Repository objects financed by the current
  # repository, including the current repository. This is always an array with
  # just this repository for public and private fork repositories.
  def repository_and_dependents(conditions = {})
    return [self] if public? || fork?

    conditions = {
      source_id: network_id,
      public: false,
    }.merge(conditions)

    repos = Repository.where("parent_id IS NOT NULL").where(conditions).to_a
    repos.unshift(T.cast(self, Repository)) # rubocop:todo GitHub/AvoidCast
    repos
  end

  # Delete any media blobs on the network if the repo is the last in the network
  # so that shared storage usage is correctly updated.
  def delete_media_blobs
    return if network.nil?
    repo_network = T.must(network)
    return if repo_network.repositories.count > 0
    repo_network.delete_media_blobs
  end

  # Internal: Intended to be called only by repository removal/archival jobs. Does the data-sanity checks they require.
  #           We only want the repos that we can confirm this user does not have access to, so we return true for those
  #           that are pullable or that throw a known exception.
  def pullable_by_user_or_no_plan_owner?(user)
    Failbot.push("gh.repo.network_id": network_id, "gh.repo.id": id)
    ActiveRecord::Base.connected_to(role: :reading) do
      return true if pullable_by?(user)

      if plan_owner.nil?
        Failbot.report("Repository network has no owner")
        true
      else
        false
      end
    end
  end

  # purge soft-deleted/hidden repositories from the production repositories table
  def purge(synchronous: false)
    RepositoryOrchestration.purge(T.cast(self, Repository)).execute(synchronous:) # rubocop:todo GitHub/AvoidCast
  end

  class RepositoryNotMarkedForDeletion < StandardError
    def initialize(repository_id)
      super("Attempt to archive and purge repository (#{repository_id}) not marked for deletion.")
    end
  end

  # Run the logic to check if any of the owner's repos need to
  # be unlocked.
  #
  # Returns nothing.
  def update_owner_repo_locks
    T.must(owner).update_locked_repositories if owner.present?
  end

  def repo_policy_bypass_enabled?
    self.repo_policy_bypass_enabled?
  end
end
