# typed: true
# frozen_string_literal: true

# Network Dependency
#
# Holds convenience methods on Repository to deal with manipulating the
# associated RepositoryNetwork.
module Repository::NetworkDependency
  extend T::Sig
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { Repository }

  # the max depth to which we will recurse when checking for ancestry loops
  MAX_PARENT_DEPTH = 1000

  MAX_HIERARCHY_DEPTH = 20

  class_methods do
    def public_fork_counts_for_public_roots_for(network_ids:)
      root_ids = RepositoryNetwork.where(id: network_ids).pluck(:root_id)
      Repository.where(id: root_ids, public: true).pluck(:id, :public_fork_count).to_h
    end

    def full_network_counts_for(source_ids:)
      Repository.
        where(source_id: source_ids, active: true).
        group(:source_id).
        count.
        transform_values! { |value| value - 1 }
    end
  end

  # Used to report failed fork attempts.
  class ForkFailure < StandardError; end
  class DetachFailure < StandardError; end
  class ExtractFailure < StandardError; end

  # Exception raised when an attempt is made to access the root repository but
  # no corresponding network record exists for this repository. This is a
  # serious data integrity error.
  class NetworkMissingError < RuntimeError
    def initialize(repo_id)
      super "Repository ##{repo_id} doesn't have a network"
    end
  end

  class InvalidAncestryError < StandardError
    attr_reader :failbot_context

    def initialize(message, repo_id:, new_parent_id: nil)
      super(message)
      @failbot_context = { "gh.repo.id": repo_id, "gh.repo.parent.id": new_parent_id }
    end
  end

  def set_network(network)
    self.network_id = network.id
    reset_git_cache
    if has_wiki?
      unsullied_wiki(true)
    end
  end

  def update_network(network)
    set_network(network)
    save

    sync_routes_from_network
  end

  def sync_routes_from_network
    # The new network is probably not on the same hosts as the old one.
    # So update the moved repo (and optional wiki) to match its new
    # network.
    nw_reader = GitHub::DGit::Routing.preferred_reader_for_network(network&.id)

    GitHub::DGit::Maintenance.delete_repo_replicas_and_checksums(network&.id, id)

    GitHub::DGit::Maintenance.insert_placeholder_replicas_and_checksums(
      GitHub::DGit::RepoType::REPO, id, network&.id)

    repo_rr = GitHub::DGit::Routing.repo_replica_for_host(id, nw_reader)
    unless repo_rr.nil?
      repo_rr_rpc = repo_rr.to_route(original_shard_path).build_maint_rpc
      if repo_rr_rpc.exist?
        GitHub::DGit::Maintenance.recompute_checksums(self, nw_reader)
      end
    end

    refresh_wiki = !RepositoryWiki.find_by(repository: self).nil?
    if refresh_wiki
      GitHub::DGit::Maintenance.insert_placeholder_replicas_and_checksums(
        GitHub::DGit::RepoType::WIKI, id, network&.id)

      wiki_rr = GitHub::DGit::Routing.wiki_replica_for_host(id, nw_reader)
      unless wiki_rr.nil?
        wiki_rr_rpc = wiki_rr.to_route(wiki_shard_path).build_maint_rpc
        if wiki_rr_rpc.exist?
          GitHub::DGit::Maintenance.recompute_checksums(self, nw_reader, is_wiki: true)
        end
      end
    end

    dgit_reload_routes!
  end

  def same_business?(repo)
    owner&.organization? &&
    repo.owner.organization? &&
    owner&.business &&
    repo.owner.business == owner&.business
  end

  # Extract this repository and all forks into a new or existing network. This
  # method is fragile. If it fails, repositories may be left in a weird state.
  #
  # network_id - The integer id of the network to transfer all repositories to.
  #              This defaults to nil for a new network.
  #
  # Returns nothing.
  def extract!(network_id: nil, reindex: true, synchronous: false, new_extract: false)
    orchestration = RepositoryOrchestration.extract(T.cast(self, Repository), new_network_id: network_id, reindex: reindex, new_extract: new_extract) # rubocop:todo GitHub/AvoidCast
    orchestration.execute(synchronous: synchronous)

    raise ExtractFailure.new(orchestration.error_message) if orchestration.failed?
    orchestration
  end

  def new_extract!(network_id: nil, synchronous: false)
    extract!(network_id:, reindex: true, synchronous:, new_extract: true)
  end

  def enough_space_to_extract?
    network&.enough_space_to_extract?(self)
  end

  def enough_space_to_detach?
    network&.enough_space_to_extract?(self, 1)
  end

  # Detach a repository, by pulling it and only it out into a whole new
  # network. The detached repository's child repositories remain in the original
  # network, but reparented under some other repository. The repository is moved
  # to a new location on disk (possibly over the network).
  def detach!(synchronous: false)
    orchestration = RepositoryOrchestration.detach(T.cast(self, Repository)) # rubocop:todo GitHub/AvoidCast
    orchestration.execute(synchronous: synchronous)

    raise DetachFailure.new(orchestration.error_message) if orchestration.failed?
    orchestration
  end

  # Reattach a repository to its parent network, if it exists
  def reattach!
    network&.reattach!
  end

  def can_attach_to?(repo)
    network&.can_attach_to?(repo.network)
  end

  def attach_to!(repo)
    network&.attach_to!(repo.network)
  end

  # Makes this repository the root of the network. This makes the existing
  # root repository a fork of this repository and moves the old root's forks
  # onto this repository. The plan owner for the network is also adjusted to
  # this repository's owner.
  #
  # Returns true if the operation was completed; false if the repo is already
  # root or the owner is at the private repo limit.
  def make_network_root!
    network&.make_root!(self)
  end

  # Is this repository the only repository in the network?
  def sole_repo_in_network?
    network&.repositories&.count == 1
  end

  # The repository at the root of this network. The root repository is
  # maintained on the RepositoryNetwork this repository belongs to. Root
  # repositories don't have a parent and are typically the first repository in
  # the network.
  #
  # Returns a Repository instance.
  def root
    if network.nil?
      raise NetworkMissingError.new(self.id)
    elsif network&.root_id == id
      self
    else
      network&.root
    end
  end

  def async_root
    return @async_root if defined?(@async_root)

    @async_root = async_network.then do |network|
      next unless network
      next self if network.root_id == id
      network.async_root
    end
  end

  # Determine if this is the network root repo.
  def network_root?
    id == network&.root_id
  end

  def network_broken?
    async_network_broken?.sync
  end

  def async_network_broken?
    async_network.then do |network|
      raise NetworkMissingError.new(self.id) if network.nil?
      network.maintenance_status == "broken"
    end
  end

  # Run "git janitor --fix" on this repository and its wiki (if it
  # exists). This cleans up obsolete files and some other kinds of
  # problems in the repository, raising a Repository::CommandFailed
  # exception if there are any problems in the repo that cannot be
  # fixed. Used before network extraction so that "git copy-fork"
  # never has to deal with obsolete files.
  def janitor_fix
    res = rpc.janitor(fix: true, type: "fork", ignore_hooks: !Rails.env.production?, no_check_ownership: !Rails.env.production?)
    if !res["ok"]
      raise Repository::CommandFailed.new("janitor", res["status"], res["out"] + res["err"])
    end

    if wiki_exists_on_disk?
      res = unsullied_wiki.rpc.janitor(fix: true, type: "wiki", no_check_ownership: !Rails.env.production?)
      if !res["ok"]
        raise Repository::CommandFailed.new("janitor", res["status"], res["out"] + res["err"])
      end
    end
  end

  # This performs the common search re-indexing logic when a repo moves to a different network.
  def reindex_after_network_operation(was_root, was_fork, old_network)
    reload

    if network != old_network
      repository_and_descendants.each do |repo|
        repo.reindex_issues(true)
        repo.reindex_discussions(true)
        repo.reindex_pull_requests(true)
      end
    end

    if !was_fork && fork?
      # the Repository#synchronize_search_index hook will purge the code from the search index
      CommitContribution.clear_contributions(self)
    elsif was_fork && !fork?
      reindex_code
      reindex_commits
      CommitContribution.backfill(self)
    end
  end

  # Public: Whether or not a fork's visibility matches its root repo.
  #
  # Returns true if its visibility matches its source, if it's a fork.
  def matches_root_visibility?
    public? == root.public?
  end

  ##
  # Repository visibility management

  # Internal - should this repository be detached from the network when
  # it attempts to change visibility?
  # This can be cleaned up once there are no longer mixed networks.
  def detach_on_visibility_change?
    (public? && (sole_repo_in_network? || matches_root_visibility?))
  end

  # Internal: remove all inaccessible forks of this repository for the given user ids.
  #
  # When a fork is removed, its children have their parent set to the parent of the removed fork.
  # The array of these reparented repos is returned.
  def remove_inaccessible_forks_for(user_ids)
    scope = forks.includes(:owner).batched_scope(:owner_id, values: user_ids)
    scope.each do |user_fork|
      if !pullable_by? user_fork.owner
        remove_user_fork(user_fork)
      end
    end
  end

  # Internal: remove the given user's fork of this repository including their children.
  def remove_fork_for(user, remover = owner)
    if forked_repo = find_fork_for_user(user)
      forked_repo.descendants.each do |child_repo|
        remove_user_fork(child_repo, remover)
      end

      remove_user_fork(forked_repo, remover)
      update_collaborator_cache
    end
  end

  # Remove a user's fork when they've lost access to it.
  #
  # This includes sending a nice email explaining what happened.
  #
  # When a fork is removed, its children have their parent set to the parent of the removed fork.
  # The array of these reparented repos is returned.
  def remove_user_fork(forked_repo, remover = owner)
    forked_repo.remove(remover, delete_forks_inaccessible_to: forked_repo.parent&.id, send_email: true)
  end

  def fork_inherits_teams?(fork)
    private? && in_organization? && (organization&.same_org_as_repo?(fork) || organization&.member?(fork.owner))
  end

  # A user may not have more than one fork of a repository within the same
  # network. Verify that an existing fork doesn't exist for the user before
  # creating.
  def ensure_uniqueness_of_fork_in_network
    return if network.nil?

    if repo = T.must(network).repositories.where(owner_id: owner_id).first
      return true if repo.owner&.organization?

      errors.add(:base, "Fork already exists: #{repo.name_with_owner}")
      false
    else
      true
    end
  end

  # Set the network on this Repository and all decendent forks.
  #
  # network - A RepositoryNetwork object.
  #
  # Returns self.
  def recursive_set_network(network = self.network)
    self.network = network
    forks.each { |repo| repo.recursive_set_network(network) }
    save!
  end

  # Callback that creates the RepositoryNetwork record when this is the
  # first repository in a network, or associates the new repository with an
  # existing network when this is a fork. This is run after_create within the
  # same transaction as creating the repositories record to maintain
  # integrity between application tables.
  #
  # Spokes tables are instantiated with `initialize_replicas_from_network`
  # via after_commit callbacks, because those rely on performing inserts
  # into the Spokes database only after the initial application queries
  # have been committed to the main database.
  #
  # Returns nothing.
  def initialize_repository_network
    raise "Cannot initialize network on unsaved record" if id.nil? && parent.nil?

    if fork?
      update_attribute :network_id, parent&.network_id if network_id.nil?
    elsif network.nil?
      network = create_network(root: self)
      network.needs_dgit_initialization_after_commit = false
      network.repositories << T.cast(self, Repository) # rubocop:todo GitHub/AvoidCast
    end
  end

  # Public: Check whether a particular repo is part of this repo's network
  #
  # Returns Boolean
  def in_network?(repo)
    network_id && repo && network_id == repo.network_id
  end

  # Calculates the public_fork_count counter column value. The name is a little
  # misleading. This value is set differently based on the type of repository.
  # When the repository is the root repository, the value is set to the
  # total number of repositories in the whole network. When the repository is a
  # fork, the value is set to the number of immediate child repository forks.
  # When the repository is private, the value is set to zero no matter what.
  #
  # Returns the calculated count value.
  def calculate_public_fork_count!
    if public?
      if network_root?
        update_column :public_fork_count,
          # Ensure public_fork_count does not drop below 0
          [network_repositories.public_scope.not_spammy.count - 1, 0].max
      else
        update_column :public_fork_count, forks.public_scope.not_spammy.count
      end
    else
      update_column :public_fork_count, 0
    end
    public_fork_count
  end

  # Recursively recalculate network repository counts for this repository and all
  # parents.
  #
  # Returns the value returned from calculate_public_fork_count!
  def calculate_network_counts!
    my_public_fork_count = T.let(0, Integer)
    parents = Set.new

    repo = T.let(self, T.nilable(Repository::NetworkDependency))
    while repo
      break if repo.id == repo.parent_id

      public_fork_count = repo.calculate_public_fork_count! if !repo.frozen?
      my_public_fork_count = public_fork_count if repo == self

      if repo.parent
        break if parents.include?(repo.parent_id)
        parents.add(repo.parent_id)
      end

      repo = T.cast(repo.parent, T.nilable(Repository::NetworkDependency)) # rubocop:todo GitHub/AvoidCast
    end

    my_public_fork_count
  end

  # Public: Returns an Integer number of direct forks for this Repository.
  def forks_count
    if public?
      public_fork_count
    else
      all_forks_count
    end
  end

  included do
    T.bind(self, T.class_of(Repository))

    batch_method(:all_forks_count) do |repos|
      repo_ids = repos.map(&:id)
      counts = Repository.where(parent_id: repo_ids, active: true).group(:parent_id).count

      repos.index_with do |repo|
        counts[repo.id] || 0
      end
    end

    # Private: Counts the number of repositories in this repository's network.
    # Doesn't include the root repository.
    #
    # Returns an Integer.
    batch_method(:full_network_count) do |repos|
      network_ids = repos.map(&:source_id)
      counts = Repository.where(source_id: network_ids, active: true).group(:source_id).count

      repos.index_with do |repo|
        counts.fetch(repo.source_id, 1) - 1
      end
    end
  end

  # Public: Returns an Integer number of Repositories in this network.
  def network_count
    if root.public?
      root.public_fork_count
    else
      full_network_count
    end
  rescue Object => boom # rubocop:todo Lint/GenericRescue
    # This is helpful in reporting networks with bad roots. Report these to github-user.
    Failbot.push(app: "github-user", "gh.repo.network_id": network_id, "gh.repo.parent.id": parent_id)
    report_error(boom)
    full_network_count
  end

  # Find a repository owned by the given user in this repository's network.
  #
  # user - a String login name or User object. If no user can be found, nil is
  #        returned.
  #
  # Returns a Repository instance or nil if the user does not have a fork in
  # this repository's network.
  def find_fork_in_network_for_user(user)
    return self if user == owner
    network&.find_fork_for(user)
  end

  # Find repositories in the same network as this repository
  # that the user has push access to.
  def find_pushable_forks_in_network_for_user(user)
    # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
    repo_ids = user.associated_repository_ids(min_action: :write)
    # rubocop:enable GitHub/DontCallAssociatedRepositoryIdsUnbounded

    # Embedding the list of ids into the query is faster, but
    # only if the list of ids is rather small. If the list of ids
    # gets too big, the time spent on serializing the ids is most likely
    # higher than just getting all repos in the network and
    # performing the filtering on the app side.
    if repo_ids.size < 100
      Repository.in_same_network_as(self).where(id: repo_ids)
    else
      Repository.where(id: repo_ids & Repository.in_same_network_as(self).ids)
    end
  end

  # Find a *direct* fork of this repository owned by the given user.
  # This does not include forks of forks. If you need to look through
  # all possible descendants, use repository_and_descendants.
  #
  # user - User object to find a fork for.
  #
  # Returns a Repository instance or nil if the user does not have a fork of
  # this repository.
  def find_fork_for_user(user)
    forks.owned_by(user).first
  end

  # Public: Fork this repository
  # See ForkRepositoryOrchestration for details
  #
  # options - Hash options that determine fork behavior. Default: {}
  #   :forker - The User performing the fork.
  #   :owner  - Deprecated alias of `:forker`.
  #   :org    - Optional. The Organization who should own the fork.
  #   :new_name   - Optional. A Name for the newly created fork
  #   :one_branch - Optional. Whether to fork only the default branch.
  # Returns [false, Symbol reason, errors] if the fork cannot be created.
  # Returns [Repository fork, Symbol reason] if it worked.
  def fork(options = {})
    owner = options[:owner] || options[:org] || options[:forker]
    forker = options[:forker] || owner

    GitHub.dogstats.distribution_time("github.dist.repository.fork") do
      name = options[:new_name]
      description = options[:description]
      one_branch = options[:one_branch]
      synchronous = options[:synchronous] || false

      orchestration = nil

      begin
        orchestration = RepositoryOrchestration.fork(
          parent_repository: T.cast(self, Repository), # rubocop:todo GitHub/AvoidCast
          actor: forker,
          owner: owner,
          name: name,
          description: description,
          one_branch: one_branch
        )
      rescue => e # rubocop:disable Lint/GenericRescue
        GitHub.logger.error(
          "Failed to create fork orchestration",
          :exception => e,
          "code.namespace" => self.class.name,
          "code.function" => __method__,
          "gh.request_id" => GitHub.context[:request_id],
          "gh.repo.orchestration.id" => orchestration&.id,
          "gh.repo.orchestration.state" => orchestration&.state,
          "gh.repo.orchestration.errors" => orchestration&.errors&.full_messages&.to_sentence,
          "gh.actor.id" => forker.id,
          "gh.repo.owner.id" => owner.id,
          "gh.repo.fork.name" => name,
          "gh.repo.fork.description" => description,
          "gh.repo.fork.one_branch" => one_branch,
          "gh.installation.id" => forker.bot? ? forker.ability_delegate&.id : nil,
          "gh.repo.id" => self.id
        )

        raise
      end

      if orchestration.valid?
        orchestration.execute(synchronous: synchronous)

        if orchestration.failed? || (orchestration.skipped? && orchestration.error_message&.to_sym == :duplicate_of_existing_fork)
          return [false, T.must(orchestration.error_message).to_sym]
        end

        return [orchestration.repository, :created]
      else
        fork_repository_error = orchestration.errors.where(:fork_repository).first

        if fork_repository_error
          reason = fork_repository_error.type

          return [orchestration.existing_repository, reason] if reason == :exists

          failed_result = [false, reason]

          if orchestration.fork_repository_errors.present?
            failed_result << orchestration.fork_repository_errors
          end

          return failed_result
        end
      end

      GitHub.logger.info(
        "Unknown orchestration failure",
        "code.namespace" => self.class.name,
        "code.function" => __method__,
        "gh.request_id" => GitHub.context[:request_id],
        "gh.repo.orchestration.id" => orchestration.id,
        "gh.repo.orchestration.state" => orchestration.state,
        "gh.repo.orchestration.errors" => orchestration.errors.full_messages.to_sentence,
        "gh.repo.id" => self.id
      )

      [false, :invalid, orchestration.errors]
    end
  end

  def network_has_fork_for?(user)
    find_fork_in_network_for_user(user).present?
  end

  def forked_by?(user)
    find_fork_for_user(user).present?
  end

  # The long running side of #fork, called from a background job. Uses the
  # git-nw-clone utility to create the new repository from the parent at the
  # new location on disk. If the parent repository is linked to a shared
  # network.git repository, the new clone will also linked.
  #
  # Returns nothing.
  def clone_fork(one_branch: false)
    T.cast(parent, T.nilable(Repository))&.enable_or_disable_shared_storage # rubocop:todo GitHub/AvoidCast

    GitHub.dogstats.distribution_time "repository.dist.fork.nw_clone" do
      T.cast(T.must(parent), Repository).rpc.nw_clone(parent&.default_branch, GitHub.repository_template, id, one_branch) # rubocop:todo GitHub/AvoidCast
    end

    # rubocop:disable GitHub/DoNotBranchOnRailsEnv
    if Rails.env.development? || Rails.env.test?
      overwrite_origin_for_tests!
    end

    # Do this after all other hard-state and git-state updates updates,
    # because it recomputes the DGit checksum.
    write_nwo_file_unsafe
    async_backup(opts: { pushed_at: Time.now })
  end

  # Does this fork have unique code and more stargazers than its root?
  def popular_fork?
    return false if !fork?
    return false if untouched_fork?
    return false if stargazer_count == 0
    return false if T.must(stargazer_count) < root.stargazer_count
    true
  end

  # Has this fork ever been pushed to?
  def untouched_fork?
    fork? && T.must(created_at) >= pushed_at
  rescue # rubocop:todo Lint/GenericRescue
    false
  end

  def fork?
    !parent_id.nil?
  end

  def private_fork?
    private? && fork?
  end

  # Public: Is this repository a fork of an internal repository?
  #
  # Returns a boolean
  def internal_fork?
    fork? && root.internal? && private?
  end

  # Public: Does this repository allow forking?
  #
  # Returns a Boolean.
  def allows_forking?
    public? || allow_private_repository_forking?
  end

  # Finds all the parents for a forked repository. First item is the
  # most recent parent, last item is the root. If there are no
  # parents, returns an empty list. The list will never include this
  # repo - always distinct repos.
  #
  # Returns an Array of Repository objects or an empty Array.
  def parents
    r = self
    list = []

    while r.parent_id && r.parent_id != r.id
      r = T.cast(T.must(r.parent), Repository::NetworkDependency) # rubocop:todo GitHub/AvoidCast
      list << r

      raise "Too many parents for repo #{id}!" if list.size > MAX_HIERARCHY_DEPTH
    end

    list
  end

  def descendant_ids
    repository_and_child_pairs = Repository.
      in_same_network_as(self).
      joins(:children).
      pluck(:id, Arel.sql("children_repositories.id AS child_id"))

    children_ids_by_repository_id = Hash.new { |h, k| h[k] = [] }
    repository_and_child_pairs.each_with_object(children_ids_by_repository_id) do |(repository_id, child_id), result|
      result[repository_id] << child_id
    end

    descendant_ids = []
    forks_to_be_visited = [id]

    while next_fork_id = forks_to_be_visited.pop
      children_ids = children_ids_by_repository_id[next_fork_id]
      next if children_ids.empty?

      forks_to_be_visited.concat(children_ids)
      descendant_ids.concat(children_ids)
    end

    descendant_ids
  end

  # Finds all descendants, incl. children, grand children, great grand children, etc.
  def descendants
    Repository.where(id: descendant_ids)
  end

  # Find all repositories that are forks of this repository recursively. This
  # isn't very efficient. It'd probably be better to grab all repositories in
  # the network in a single query and figure out the parentage instead.
  def repository_and_descendants(repositories = [])
    repositories << self
    forks.each { |repo| repo.repository_and_descendants(repositories) }
    repositories
  end

  # Moves this repository and all forks to a different parent, within the same
  # network.
  #
  # parent - The new parent repository for this repository. The new parent must
  #          be in the same network the repository is currently in.
  #
  # Returns self
  def reparent!(new_parent)
    raise ArgumentError, "cannot find new parent repository" unless new_parent
    raise InvalidAncestryError.new("cannot reparent across networks", repo_id: id) if new_parent.network_id != network_id

    if network&.root == self
      new_parent.make_network_root!
      return self
    end

    validate_ancestry!(new_parent)

    transaction do
      update!(parent: new_parent)
      update_organization
    end

    calculate_network_counts!
    self
  end

  # internal: `self` cannot be its own parent or its own ancestor. Recurse through the ancestry
  # to ensure this is not the case.
  #
  # raises InvalidAncestryError
  # returns nothing
  def validate_ancestry!(new_parent)
    candidate = new_parent
    (0..MAX_PARENT_DEPTH).each do |level_counter|
      break if candidate.nil?
      if level_counter >= MAX_PARENT_DEPTH
        raise InvalidAncestryError.new("exceeded max depth when reparenting", repo_id: id)
      elsif candidate == self
        raise InvalidAncestryError.new("cannot set repo as its own descendant", repo_id: id, new_parent_id: new_parent.id)
      end
      candidate = candidate.parent
    end
  end

  # Fetch this repository into its network repository, but only when there
  # are other repositories in the network or the network repository already
  # exists.
  #
  # force - Causes the repository's pushed_at timestamp to be updated before
  #         updating the network repository, which invalidates the
  #         has-been-fetched and ref caches.
  #
  # Returns true when a job was queued to sync the repository, nil otherwise.
  def update_network_repository(force = false)
    update_attribute :pushed_at, Time.now if force
    synchronize_shared_storage
  end

  # A most-recently cached NetworkGraph for the repository. Use NetworkGraph.new
  # for historical nethash support.
  def network_graph
    @network_graph ||= Repository::NetworkGraph.for_repository(self)
  end

  def should_remove_for_inacessible_parent?
    private? && owner&.user? && parent&.private? && !T.cast(parent, T.nilable(Repository))&.pullable_by?(owner) # rubocop:todo GitHub/AvoidCast
  end

  def async_ip_restricted_private_fork?
    return @async_ip_restricted_private_fork if defined?(@async_ip_restricted_private_fork)

    if GitHub.enterprise?
      @async_ip_restricted_private_fork = Promise.resolve(false)
      return @async_ip_restricted_private_fork
    end
    unless private_fork?
      @async_ip_restricted_private_fork = Promise.resolve(false)
      return @async_ip_restricted_private_fork
    end

    @async_ip_restricted_private_fork = async_root.then do |root|
      next false unless root.present?

      root.async_owner.then do |owner|
        GitHub.flipper[:intel_fork_ip_allowlist_org].enabled?(owner)
      end
    end
  end

  def ip_restricted_private_fork?
    async_ip_restricted_private_fork?.sync
  end
end
