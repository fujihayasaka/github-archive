# typed: true
# frozen_string_literal: true

# RepositoryNetwork - Models a network of repositories.
#
# All repositories belong to a "network". The network is the set of repositories
# created by forking a repository within the network. Repositories in the same
# network share a network_id, fs host and disk location.
#
# The RepositoryNetwork model is used to store information that's applicable to
# the network as a whole, such as the fs host and partition location of git
# repositories, the root repository, push and access times, etc.
#
# == Examples
#
# The most common way of accessing a RepositoryNetwork is via the
# Repository#network association:
#
#   repository = Repository.with_name_with_owner("defunkt/dotjs")
#   repository.network
#
# The network can be used to determine the root repository as well as all other
# repositories in the network.
#
# == Backfill status
#
# The repository_networks table was added way after the concept of repository
# networks existed on the site and is not yet used in all of the places that
# you'd expect. Network records have been backfilled for all existing networks
# but we're still moving various bits of logic to this model.
#
# The table includes a number of columns that are not yet being maintained. This
# includes the owner_id, repository_count, backup_host, accessed_at,
# disabled_at, disabled_by, and disabling_reason columns. These attributes will
# always be nil and should not be used.
#
# See the initial pull request for more information on the schema and plans for
# columns that are not yet being maintained:
#
# https://github.com/github/github/pull/12418
#
class RepositoryNetwork < ApplicationRecord::Domain::Repositories
  include Repositories::IRepositoryNetwork

  include Configurable
  include Configurable::ArchiveResourceBlocking
  include RepositoryNetwork::Backfill
  include RepositoryNetwork::Storage
  include RepositoryNetwork::Maintenance

  include GitHub::FlipperActor
  include GitHub::VexiActor
  include Instrumentation::Model
  include GH::Domain::Cache::Cachable::Dirtyable

  # The root repository for this network. All other repositories with the same
  # network id should descend from this object.
  belongs_to  :root, class_name: "Repository"

  # rubocop:todo Rails/InverseOf
  belongs_to :parent,
    foreign_key: "owner_id",
    class_name: "RepositoryNetwork"
  # rubocop:enable Rails/InverseOf

  # rubocop:todo Rails/InverseOf
  has_many :children,
    foreign_key: "owner_id",
    class_name: "RepositoryNetwork"
  # rubocop:enable Rails/InverseOf

  # All active repositories in the network.
  # rubocop:todo Rails/InverseOf
  has_many :repositories,
    -> { where(active: true) },
    foreign_key: "source_id"
  # rubocop:enable Rails/InverseOf

  # All repositories in the network that are marked as deleted.
  # rubocop:todo Rails/InverseOf
  has_many :deleted_repositories,
    -> { where(active: nil) },
    class_name: "Repository",
    foreign_key: "source_id"

  has_many :active_and_deleted_repositories, class_name: "Repository", foreign_key: "source_id"
  # rubocop:enable Rails/InverseOf

  # All repositories in the network except the root.
  scope :forks, -> (network) { network.repositories.where.not(parent_id: nil) }

  # The root repository of each network in the network family
  scope :family_root_repositories,
    -> (network) { Repository.active.network_roots.where(source_id: network.family_ids) }

  scope :family_networks,
    -> (network) { RepositoryNetwork.default_scoped.where(id: network.family_ids) }

  # Set default attribute values when creating new network records
  before_create :set_default_values # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_create  :set_storage_attributes # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  after_commit :owner_disable_check, # rubocop:todo GitHub/AvoidActiveRecordCallbacks
               on: :create

  after_commit :initialize_placeholder_network_replicas, # rubocop:todo GitHub/AvoidActiveRecordCallbacks
               if: :needs_dgit_initialization_after_commit?,
               on: :create

  after_commit :delete_media_blobs, # rubocop:todo GitHub/AvoidActiveRecordCallbacks
               on: :destroy

  after_commit :delete_replicas_after_commit_on_destroy, # rubocop:todo GitHub/AvoidActiveRecordCallbacks
               unless: :skip_replica_deletion_after_commit?,
               on: :destroy

  def delete_replicas_after_commit_on_destroy
    GitHub::DGit::Maintenance.delete_network_replicas(self.id)
  end

  before_validation :set_initial_maintenance_status, on: :create

  # Alternative for setting the primary key id value. Modeled as a separate
  # attribute to work around AR limitations setting the id attribute at
  # initialization time.
  def network_id=(value)
    self.id = value
  end

  def network_id
    id
  end

  def set_initial_maintenance_status
    # The DB columns are `not null` but they don't provide a default value. Sorbet thinks they can't be nil when they initially are.
    T.unsafe(self).maintenance_status  ||= "complete"
    T.unsafe(self).last_maintenance_at ||= Time.now
    self.last_maintenance_attempted_at ||= Time.current
  end

  # Increment the pushed_count and pushed_count_since_maintenance columns by 1.
  # This increments the values within a single SQL query which handles multiple
  # concurrent increments properly. Using an AR load, app increment, and save is
  # prone to concurrent processes stomping on each other.
  # Note: The newly incremented values are not written into this instances
  # attributes as they're typically not used at increment time.
  def increment_pushed_counts
    self.class.where(id: id).update_all(
      "pushed_count = pushed_count + 1,
       pushed_count_since_maintenance = pushed_count_since_maintenance + 1",
    )
  end

  # Similar to `#increment_pushed_counts` but additionally updates the `pushed_at`
  # and `#unpacked_size_in_mb` columns.
  def update_push_stats(pushed_at:, unpacked_size_in_mb:)
    self.class.where(id: id).update_all([
      %{
        pushed_at = ?,
        pushed_count = pushed_count + 1,
        pushed_count_since_maintenance = pushed_count_since_maintenance + 1,
        unpacked_size_in_mb = ?,
        updated_at = ?
      },
      pushed_at,
      unpacked_size_in_mb,
      Time.now
    ])
  end

  # The name of the repository network, taken from the name_with_owner of the
  # network's root repository.
  def name
    root&.name_with_owner
  end

  # dgit_spec is the canonical description for a repository entity within
  # dgit/spokes.
  def dgit_spec
    "network/#{id}"
  end

  # Internal: Before create callback used to set default attributes values for a
  # record that's about to be created.
  def set_default_values
    # The DB columns are `not null` but they don't provide a default value. Sorbet thinks they can't be nil when they initially are.
    T.unsafe(self).pushed_count ||= 0
    T.unsafe(self).pushed_count_since_maintenance ||= 0
  end

  # Whether network replicas need to be deleted during an
  # after_commit callback. Set from `destroy_repository_network`
  # during purging.
  def skip_replica_deletion_after_commit?
    @skip_replica_deletion_after_commit
  end
  attr_writer :skip_replica_deletion_after_commit

  # Whether placeholder network replicas need to be instantiated during a
  # the first after_commit callback.  Set from `set_storage_attributes`
  # during creation.  Unset upon `initialize_placeholder_network_replicas`.
  def needs_dgit_initialization_after_commit?
    @needs_dgit_initialization_after_commit
  end
  attr_writer :needs_dgit_initialization_after_commit

  # Internal: After create callback used to set whether we need to initialize
  # dgit data.
  def set_storage_attributes(insert_replicas = true)
    if !defined?(@needs_dgit_initialization_after_commit)
      @needs_dgit_initialization_after_commit = insert_replicas
    end
    save! if !new_record?
  end

  # Called from after_commit callbacks upon creation from one of either
  # the Repository or RepositoryNetwork classes.  Inserts new placeholder
  # network replica records for this network.
  def initialize_placeholder_network_replicas
    actor = root&.owner unless root.nil?

    fileservers = GitHub::Spokes.client.pick_fileservers(actor: actor)
    GitHub::DGit::Maintenance::insert_placeholder_network_replicas(self.id, fileservers)

    @needs_dgit_initialization_after_commit = false
  end

  # Exception raised when extracting is attempted and we refuse to do so for
  # availability or other reasons
  class UnsafeExtractionError < StandardError
  end

  class InvalidNetworkError < StandardError
  end

  # See if there is enough space for another repo of this size
  def enough_space_to_extract?(repository)
    available = calculate_free_space
    usage     = T.cast(self, RepositoryNetwork::Storage).disk_usage(true)

    T.must(usage) < available - GitHub.shard_slack_space
  end

  # See if we can run maintenance without running the disk out of space.
  # Maintenance copies objects in from forks and rewrites the main pack,
  # each of which can temporarily double the size of the objects being
  # copied or rewritten.  In the worst case, all objects from all forks
  # will get copied to network.git and then repacked.  So a decent upper
  # bound on space needed for maintenance is basically the size of all
  # .pack and .idx files in all forks and network.git.
  #
  # Fortunately, we have a script that calculates that.  Return true if
  # the estimated size is less than available space minus slack space.
  #
  # Returns Boolean
  def enough_space_to_run_maintenance?
    available = calculate_free_space   # in KB
    needed = rpc.get_maint_size << 10  # convert MB to KB
    needed < available - GitHub.shard_slack_space
  end

  # Grabs repo state before a network operation (e.g. attach, detach, extract)
  # needed to determine which search indexes need updating after the operation.
  #
  # You'd be correct to notice returning both `network_root?` and `fork? is
  # superfluous. They should always have inverse values and you should only need
  # one. But one is a value stored with the RepositoryNetwork and the other is
  # stored with the Repository, and we have some known bad data where they don't
  # always align. Sadly this is the most resilient way to handle it until/unless
  # that's identified and thoroughly fixed.
  private def get_initial_state_for_search_reindex(repo)
    [repo.network_root?, repo.fork?, repo.network]
  end

  # Reattach this network to its parent network.
  #
  # Returns nothing.
  def reattach!
    raise "No parent network to re-attach to" if parent.nil?
    raise "Cannot reattach to a network with different visibility" unless matches_parent_visibility?
    orchestration = perform_attach(parent)
    GitHub.instrument "staff.repo_reattach", repo: root
    orchestration
  end

  # Reattach this network to a related network.
  #
  # The intent is for this to be called from a controller with `async: true` to check for errors
  # that can be communicated to the user then schedule a job. The job should then call this with
  # `async: false` to actually perform the attach. We default `async: false` to make behavior
  # consistent with similar methods here, e.g. `detach!` and `reattach!`.
  #
  # Raises if the repository cannot be attached. Returns nothing.
  def attach_to!(dest_network)
    allowed, reason = can_attach_to?(dest_network)
    raise "Cannot attach to that repository: #{can_attach_to_failure_reason_description(reason)}." unless allowed
    orchestration = perform_attach(dest_network)
    GitHub.instrument "staff.repo_attach_to", repo: root, destination_root: dest_network.root
    orchestration
  end

  private def perform_attach(dest_network)
    root&.extract!(network_id: dest_network.id, reindex: false)
  end

  def reparent_child_networks(new_parent_network_id)
    # This network is about to be destroyed. So we're going to take all of our
    # children and set their parent to our _new_ parent.
    child_network_ids = children.map(&:id)

    # If the network we're attaching to was previously our child, we can't set
    # it to be its own parent. So we exclude that possibility here.
    child_network_ids_to_update = child_network_ids - [new_parent_network_id]
    RepositoryNetwork.where(id: child_network_ids_to_update).update_all(owner_id: new_parent_network_id)

    # If the network we're attaching to was previously our child, it was
    # excluded above so we handle it here. Its new parent should be our _old_
    # parent.
    new_parent_child_id = child_network_ids & [new_parent_network_id]
    RepositoryNetwork.where(id: new_parent_child_id).update_all(owner_id: owner_id) if new_parent_child_id.any?
  end

  # Makes the given repository the root of the network. This makes the existing
  # root repository a fork of the given repository and moves the old root's forks
  # onto the new root. The plan owner for the network is also adjusted to
  # the new root repository's owner.
  #
  # Returns true if the operation was completed.
  def make_root!(repo)
    old_root = root

    # verify this repo still exists and is part of our network
    new_root = Repository.find_by(id: repo.id, source_id: self.id)
    unless new_root
      raise "Invalid root repository"
    end

    if new_root == old_root
      raise "This repository is already the root"
    end

    if new_root.private? && new_root.active? && new_root.owner&.at_private_repo_limit?
      raise "New owner is at private repository limit"
    end

    if old_root.present?
      RebuildStorageUsageJob.perform_later(old_root.owner_id)
      if old_root.has_lfs_files?
        # this makes an http call, which is bad if we're running inside a transaction
        old_root.reset_billed_lfs_storage_usage
      end
    end

    # copy repo-level push rules from the old root to the new network root
    # do this before the repo is the root, to avoid a gap in push protection
    rules = RepositoryRuleset.copy_rules(old_root, new_root, ["push"], validate: false)
    old_rules = rules[0]
    new_rules = rules[1]

    begin
      Repository.transaction do
        # change the root on the RepositoryNetwork
        self.update_column(:root_id, new_root.id)

        # change the parent of the new root
        new_root.update_column(:parent_id, nil)
        sync_org_owned_private_network_with_forks
      end

      new_root.reload_parent
      self.reload_root

      # delete the push rules from the original root
      old_rules.each(&:destroy)
    rescue StandardError => e # rubocop:todo Lint/GenericRescue
      # if something went wrong, destroy the rules we copied
      new_rules.each(&:destroy)
      raise
    end

    # reparent forks that need to be reparented
    roots = self.active_and_deleted_repositories.reload.where("parent_id IS NULL").to_a
    forks = self.active_and_deleted_repositories.where("parent_id IN (?)", roots).to_a
    forks += roots
    forks.delete new_root

    Repository.where(id: forks.map(&:id)).update_all(parent_id: new_root.id)
    new_root.update_organization

    GitHub.dogstats.distribution_time "repository.dist.fork.update_root_repository_reload" do
      # find_in_batches used to implicitly reload relations, but that was updated in
      # https://github.com/rails/rails/pull/48876
      # to use the already-loaded relation when possible. We were relying on the implicit reload
      # previously to pick up the changes made above with `update_all`. Using the scope from the assocation
      # allows to bypass the already loaded records and reload in batches.
      active_and_deleted_repositories.scope.find_in_batches(batch_size: 1000) do |batch|
        batch.each { |repo| repo.update_organization }
      end
    end

    if old_root
      old_root.reload.calculate_network_counts!
    end

    new_root.reload.calculate_network_counts!
    new_root.reindex_after_network_operation(false, true, self)

    GitHub.instrument "staff.repo_make_root", repo: new_root, root_repo_was: old_root

    # refresh the original input object so callers don't have to
    repo.reload
  end

  # Reparent all forks of the given repository under another repository. When the
  # repository has a parent, forks are reparented under that guy. When the
  # repository is the root of a network, one of the forks is elected as the
  # new root and all other forks are reparented under it.
  def reparent_forks!(parent_repo)
    # get all forks of this repo in the network, including the deleted ones
    forks = Repository.where(source_id: parent_repo.source_id, parent_id: parent_repo.id).sort_by { |r| T.must(r.id) }

    if forks.any?
      # try to find a parent that is marked as active
      repo = parent_repo
      while new_parent = T.let(repo.parent, T.nilable(Repository))
        break if new_parent.active?
        repo = new_parent
      end

      if new_parent
        # We have to save descendants before updating the parent_id on the forks
        descendants = parent_repo.descendants

        Repository.where(id: forks.map(&:id)).update_all(parent_id: new_parent.id)
        new_parent.update_organization
        GitHub.logger.info(
          "Re-parented repo forks",
          "code.namespace" => self.class.name,
          "code.function" => __method__,
          "gh.repo.network_id" => self.id,
          "gh.repo.network_size" => repositories.size,
          "gh.repo.id" => parent_repo.id,
          "gh.request_id" => GitHub.context[:request_id]
        )
        GitHub.dogstats.distribution_time "repository.dist.fork.new_parent_repository_reload" do
          descendants.find_in_batches(batch_size: 1000) do |batch|
            batch.each do |repo|
              repo.update_organization
            end
          end
        end
      else
        # If there is no parent, we have to elect a new root. Prefer active and public repos.
        active = forks.select(&:active?)
        elected = active.find(&:public?) || active.first || forks.first
        make_root!(elected)
      end
    end
  end

  def sync_org_owned_private_network_with_forks
    if root&.private? && (root&.owner&.organization? || root&.organization_id == root&.owner_id) && has_active_or_deleted_forks?
      OrgOwnedPrivateNetworkWithForks.upsert({ network_id: id, owner_id: root&.owner_id })
    else
      OrgOwnedPrivateNetworkWithForks.destroy_by_network_id(id)
    end
  end

  def org_owned_private_network_with_forks?
    OrgOwnedPrivateNetworkWithForks.find_by(network_id: id).present?
  end

  def has_active_or_deleted_forks?
    active_and_deleted_repositories.limit(2).count > 1
  end

  # Public - The visibility of all repositories in this network.
  #
  # returns 'public' or 'private'
  def visibility
    root&.visibility
  end

  def matches_parent_visibility?
    parent && parent&.visibility == self.visibility
  end

  def network_owner
    root&.owner
  end
  alias_method :owner, :network_owner

  def shard_path
    fail "no shard_path for network without an id" unless id

    "#{storage_path}/network.git"
  end

  # Update permissions on the given repositories after
  # they have been extracted into a new network. Currently
  # only removes old collaborators who should no longer
  # have access.
  #
  # repos - the repositories in this network to be updated
  # former_organization - nil, or the repos' previous organization
  #                       if their permissions were managed via teams.
  #
  # Returns nothing.
  def update_permissions_on(repos, former_organization)
    repos.each do |repo|
      # never was involved in an org, only need to manage collabs, not teams
      if !former_organization && !repo.in_organization?
        repo.remove_member parent&.root&.owner if parent && parent&.root&.owner
      end
    end
  end

  def billing_unlock
    return unless root.present?
    root_repo = T.must(root)

    if root_repo.locked_on_billing? && (root_repo.public? || !root_repo.owner&.reload.at_private_repo_limit?)
      root_repo.unlock_including_descendants!
    end
  end

  def billing_lock
    root_repo = T.must(root)
    return if root_repo.public? || root_repo.locked_on_billing?

    root_repo.lock_for_billing if root_repo.owner&.at_private_repo_limit?
  end

  # Public: Finds a repository in the network owned by the specified owner, if any.
  #
  # owner    - The User/Organization to look up a repository for. If a String identifier is given (i.e. login)
  #            the User/Organization will be looked up.
  #
  # Returns a Respository.
  def find_fork_for(owner)
    owner = User.reify(owner)

    if owner == network_owner
      root
    elsif owner
      repositories.find_by(owner_id: owner.id)
    end
  end

  def read_only?
    moving?
  end

  # Returns a `full_network_tree` for each network in the family.
  def family_network_trees
    self.class.family_networks(self).map do |related_network|
      repo_map = related_network.full_network_tree
      next if repo_map.empty?

      network_roots = repo_map[nil]
      raise InvalidNetworkError, "Network #{related_network.id} has #{network_roots.count} roots" if network_roots.count != 1
      [network_roots.first, repo_map]
    end.compact
  end

  def full_network_tree
    repositories.includes(:owner).group_by(&:parent_id)
  end

  def broken?
    (maintenance_status =~ /\Abroken\Z/i) ? true : false
  end

  # Public: Does the network's root belong to another network?
  #
  # A failed detach or extract can cause a network's root to point to
  # a different network.
  def orphaned?
    root&.source_id != id
  end

  def increment_cache_version!
    ActiveRecord::Base.connected_to(role: :writing) do
      RepositoryNetwork.increment_counter(:cache_version_number, id)
      reload
    end
  end

  def event_context(prefix: :repository_network)
    {
      "#{prefix}_id".to_sym => id,
      prefix => name,
    }
  end

  def event_payload
    { repository_network: self, public_repo: root&.public? }
  end

  def restore
    return if repositories.count > 1
    Media::Transition.async_restore(self)
  end

  # Public: Removes network forks owned by individuals who do not have access to root repository.
  def remove_invalid_user_forks
    RepositoryNetwork.forks(self).find_in_batches do |batch|
      inaccessible = repos_with_inaccessible_root(batch)
      inaccessible.each do |user_fork|
        user_fork.throttle { user_fork.remove(user_fork.owner) }
      end
    end
  end

  # Prevent infinite recursion in the event of circular references in the network tree
  MAX_TREE_HEIGHT = 1000
  private_constant :MAX_TREE_HEIGHT

  def root_network
    @root_network ||= begin
      current_network = T.let(self, T.nilable(RepositoryNetwork))
      (0..MAX_TREE_HEIGHT).each do |height|
        break if current_network&.parent.nil?
        current_network = current_network&.parent
        raise "maximum network tree height exceeded: likely circular reference" if height >= MAX_TREE_HEIGHT
      end
      current_network
    end
  end

  # Prevent infinite recursion in the event of circular references in the network tree
  MAX_QUEUE_DEPTH = 10000
  private_constant :MAX_QUEUE_DEPTH

  # Returns the array of network IDs for all networks in the same "family."
  #
  # A network family is all networks descended from the same root. This method traverses the entire
  # network tree to retrieve all related networks. Note that this is not traversing repositories
  # within a network, it's traversing the networks themselves.
  def family_ids
    return @network_family_ids if defined?(@network_family_ids)

    tree_walker = lambda do |networks|
      networks.flat_map do |network|
        # Sorbet considers `tree_walker` to only be `nil`
        T.unsafe(tree_walker).call(network.children).unshift(network.id)
      end
    end

    ids = tree_walker.call([root_network])
    ids.uniq!
    @network_family_ids = ids
    @network_family_ids
  end

  # Determines whether attaching the current network to the provided network is valid.
  # Returns a 2-element array:
  # - Boolean whether the attach is allowed
  # - Symbol reason when not allowed, :valid when allowed. Valid symbols:
  #   - :visibility if the networks have differing visibility
  #   - :same_network if the networks are the same
  #   - :unrelated if the networks are not in the same family
  #   - :dangling_fork if attaching the network would create new dangling forks: forks whose owner
  #     has no permissions on the fork parent.
  #   - :oopf if attaching the network would create new org-owned private forks outside the business
  #   - :valid when the network can be safely attached
  def can_attach_to?(attach_to_network)
    GitHub.dogstats.time "repository_network.can_attach_to.time", tags: ["visibility:#{visibility}"] do
      return [false, :visibility] unless visibilities_match_for_attach?(attach_to_network)
      return [false, :same_network] if id == attach_to_network.id
      return [false, :unrelated] if root_network.id != attach_to_network.root_network.id

      # No permission or ownership checks are necessary in public networks.
      return [true, :valid] if root&.public?

      all_repos_valid = true
      reason = :valid
      all_repos_valid = repositories.all? do |repo|
        # The source network will be flattened and re-parented under the destination network root.
        # So to prevent new dangling forks, owners of all repos in the source network must have read
        # access to the destination network's root.
        if repo.owner&.user? && !attach_to_network.root.permit?(repo.owner, :read)
          reason = :dangling_fork
          next false
        end
        true
      end
      [all_repos_valid, reason]
    end
  end

  private def can_attach_to_failure_reason_description(reason)
    case reason
    when :visibility
      "the networks have different visibilities"
    when :same_network
      "the repositories are already in the same network"
    when :unrelated
      "the networks are unrelated"
    when :dangling_fork
      "a new dangling fork (whose owner has no access to the parent) would be created"
    when :oopf
      "a new organization-owned private fork would be created"
    else
      reason
    end
  end

  private def visibilities_match_for_attach?(attach_to_network)
    if attach_to_network.visibility == "internal"
      # An internal network is a network whose root is internal and all forks are private or internal. So if
      # we're joining an internal network, this network must be private, or have the same owner
      return true if visibility == "private"

      # an internal repo can be attached to an internal network if both networks have the same owner
      visibility == "internal" && root&.owner == attach_to_network.root.owner
    else
      # If the new parent network isn't internal, visibility must match.
      visibility == attach_to_network.visibility
    end
  end

  private def repos_with_inaccessible_root(batch)
    batch.reject do |fork|
      # Reject it, preventing removal, unless it's user-owned.
      # See https://github.com/github/github/issues/112160#issuecomment-497386928 and related issues.
      next true unless fork.owner.user?

      root&.pullable_by_user_or_no_plan_owner?(fork.owner)
    end
  end

  def delete_media_blobs
    Media::Transition.async_delete(self)
  end

  def tenant_id
    return unless GitHub.multi_tenant_enterprise?
    @tenant_id ||= root&.owner&.business_id
  end

  def resolve_tenant
    GitHub::CurrentTenant.unscope { Business.find_by(id: tenant_id) } if tenant_id
  end

  protected

  def owner_disable_check
    if network_owner
      if parent
        # just do a single-repo lock if this network was detached/extracted from another
        billing_lock
      else
        network_owner.enable_or_disable! if root&.private?
      end
    end
  end

  sig { override.returns(GH::Domain::Base) }
  def domain
    Repositories.domain.networks
  end
end
