# typed: false
# frozen_string_literal: true
class ForkRepositoryOrchestration < RepositoryOrchestration
  include Repository::ForkerMethods
  include GitHub::Memoizer

  validate :can_fork_repository?, on: :create

  def skip_repository_id_validation
    true
  end

  def can_fork_repository?
    # Users can't be too new
    # To avoid hitting this on every CI fork test, only check in production
    # rubocop:disable GitHub/DoNotBranchOnRailsEnv
    return set_fork_error(reason: :new_user) if Rails.env.production? && (forker.created_at + 5.seconds) > DateTime.now.utc

    # Prevent spammy users from creating spammy forks
    return set_fork_error(reason: :spammy_user) if forker.spammy?

    # disable secondary forks for internal repositories
    return set_fork_error(reason: :fork_of_internal) if parent_repository.internal_fork?

    # is forking disabled all together?
    return set_fork_error(reason: :disabled) if parent_repository.forking_disabled?

    # Forker is EMU or GH[ES|AE] user trying to fork the repository into their account which is not allowed.
    return set_fork_error(reason: :policy) if violating_enterprise_policy?

    return set_fork_error(reason: :deleted_owner) if owner.deleted?

    if owner.organization?
      # Forker is trying to fork the repository into an org. We need to make sure the org is a valid target based on the policies set.
      unless owner.fork_allowed?(repo: parent_repository, user: forker) && owner.can_create_repository?(forker, visibility: parent_repository.visibility)
        reason = :policy
        return set_fork_error(reason: reason)
      end
    else
      # Forker is trying to fork the repository into their account. We need to check policies to determine if that should be allowed.
      return set_fork_error(reason: :policy) if !owner.fork_allowed?(parent_repository)
    end

    if !allowed_request_for_intra_org_fork? && !allowed_multi_fork_request_for_org?
      if @existing_repository = parent_repository.find_fork_in_network_for_user(owner)
        unless existing_repository.active?
          # XXX repo is marked as deleted in DB but not cleaned up yet. can't
          # fork. not much we can do about this.
          fail "can't refork deleted repo"
        end
        data[:existing_repository_id] = existing_repository.id
        return set_fork_error(reason: :exists)
      end
    end

    return set_fork_error(reason: :account) if !forker.can_fork?(parent_repository, owner)

    return set_fork_error(reason: :locked) if parent_repository.locked?

    @built_repository = build_new_repository
    @built_repository.active = nil

    if !built_repository.valid?
      data[:fork_repository_errors] = built_repository.errors.messages
      @repository_errors = data[:fork_repository_errors]
      set_fork_error(reason: :invalid, fork_repository_errors: built_repository.errors)
    end
  end

  step :create_fork, max_attempts: 2 do
    # It will only happen when retrying a failed orchestration
    return :skipped, "Failed to build fork." if @built_repository.nil?

    # If the repository was already created, we are in an uncertain state, and so
    # should just fail the forking.
    return :failed, "Failed to create fork." if @built_repository.persisted?

    if @duplicate_repo_for_retry.nil?
      # On the first attempt, we need to save the original state of the repo, so that we can retry saving it using
      # that original state if the first attempt fails.
      @duplicate_repo_for_retry = @built_repository.dup
    else
      # On attempts beyond the first, we need to reset the built_repository to its original state, to avoid
      # saving the repo using state which was modified on the @built_repository instance, but not committed to the
      # database.
      @built_repository = @duplicate_repo_for_retry.dup
    end

    # create with a cache lock to ensure the repo isn't forked twice at the same
    # time by the same user.
    #
    # XXX: This should be a unique constraint on repos (owner_id, source_id)
    # but we need to clean up all existing dupe forks in order to add it.
    mutex = GitHub::Redis::Mutex.new("repo-fork-lock:#{owner.id}:#{parent_repository.network_id}", timeout: 15.seconds)
    begin
      mutex.lock do
        @built_repository.expected_creation = true
        @built_repository.save!
      end
    rescue GitHub::Redis::Mutex::LockError
      return [:skipped, :duplicate_of_existing_fork]
    rescue ActiveRecord::RecordInvalid => e
      self.repository = nil
      return [:skipped, :duplicate_of_existing_fork]
    end

    # make sure orchestration.repository_id is persisted in the DB
    # In case of a second try, the repository_id is set in the orchestration
    # and this existing_repository will be returned
    self.update!(repository: @built_repository)
  end

  step :sync_org_owned_private_network_with_forks do
    repository.network.sync_org_owned_private_network_with_forks
  end

  step :initialize_replicas do
    repository.initialize_replicas_from_network
  end

  step :activate_repository do
    if owner.reload.deleted?
      repository.errors.add :owner, "is deleted"
      return :skipped, "Failed to create fork."
    end

    begin
      # Activate the repository now that we know it has been created successfully in spokes
      repository.update!(active: true)
    rescue ActiveRecord::RecordNotUnique => e
      return [:skipped, :duplicate_of_existing_fork]
    end
  end

  step :calculate_network_counts do
    repository.calculate_network_counts!
  end

  step :enqueue_repo_sponsorables_job_for_sponsorable_owner do
    return unless GitHub.sponsors_enabled?

    repository.enqueue_repo_sponsorables_job_for_sponsorable_owner
  end

  step :auto_subscribe_owners do
    # https://github.com/github/github/blob/c67bd5ea94e6d0a19bdd4586688e399005ed93b4/lib/newsies/service.rb#L195
    # By this short circuit logic, auto subscribe owners is not perfomed if the repo is a fork and GitHub Enterprise
    # this It will prevent several calls to the DB, as well some Jobs to be enqueued
    return if !GitHub.enterprise?

    repository.auto_subscribe_owners
  end

  step :synchronize_search_index do
    repository.synchronize_search_index
  end

  step :instrument_repo_added_to_installations_across_all_repositories do
    repository.instrument_repo_added_to_installations_across_all_repositories
  end

  step :add_repository_to_team do
    repository.add_repository_to_team
  end

  step :setup_security_products do
    repository.setup_security_products_on_creation(forker, true)
  end

  step :instrument_creation do
    repository.instrument_creation
  end

  step :reset_memoized_attributes do
    repository.reset_memoized_attributes
  end

  step :set_internal_visibility do
    return unless should_set_new_repo_to_internal?

    repository.set_permission(Repository::INTERNAL_VISIBILITY)
  end

  step :copy_members_and_permissions do
    if parent_repository.fork_inherits_teams?(repository)
      # The parent's owner is an org and the new owner is a member of
      # that org, or is the same org (intra-org forks) - add the new repo to the same teams the parent is
      # on.
      repository.add_teams_of(parent_repository)

      if should_set_forker_as_admin?
        repository.add_member(forker, action: :admin)
      end
    elsif owner.organization? && forker
      # We're forking the new repo into an org
      if should_set_forker_as_admin?
        repository.add_member(forker, action: :admin)
      end
    elsif !parent_repository.in_organization? && parent_repository.private?
      # All collaborators on a private repo should be added to private
      # forks.
      repository.copy_permissions_of(parent_repository)
    end
  end

  step :enable_dco_signoff do
    return unless parent_repository.dco_signoff_enabled?

    # If commit signoff is enabled on the parent repo, enable it on the fork. The network root setting is ignored.
    repository.enable_dco_signoff(actor: forker)
  end

  step :instrument_forked do
    GitHub.dogstats.increment("repository", tags: ["action:internal-repo-fork", "orchestrated:true"]) if repository.internal?
    GitHub.dogstats.increment("repository", tags: ["action:private-fork-fork", "orchestrated:true"]) if repository.private_fork?
  end

  job_start

  step :populate_labels do
    repository.populate_labels
  end

  step :create_license do
    return unless parent_repository.repository_license.present?
    return if repository.repository_license.present?

    RepositoryLicense.create!(
      repository: repository,
      license_id: parent_repository.repository_license.license_id
    )
  end

  step :clone_repository do
    if repository.exists_on_disk?
      # If this is a retry, validate the disk file system.
      # See https://github.com/github/repos/issues/7472
      if repository.rpc.all_replicas_exist?
        # nothing to do here
        return
      else
        # Delete it and start over.
        repository.rpc.remove
      end
    end

    repository.clone_fork(one_branch: data[:one_branch])
  end

  step :publish_created do
    message = CreateRepositoryOrchestration.build_hydro_event_message_from_repository(repository)
    publish_hydro_event(message: message, schema: "github.repositories.v1.Created")
  end

  step :enqueue_copy_language_stats_job do
    RepositoryCopyLanguageStatsJob.perform_later(repository.id, copy_from_repo_id: repository.parent_id)
  end

  def only_save_on_orchestration_end?
    true
  end

  attr_writer :owner
  attr_writer :existing_repository
  attr_writer :fork_repository_errors
  attr_writer :parent_repository

  attr_accessor :description
  attr_writer :forker

  def fork_repository_errors
    return @fork_repository_errors if defined?(@fork_repository_errors)

    @fork_repository_errors = data[:fork_repository_errors]
  end

  def existing_repository
    return @existing_repository if defined?(@existing_repository)

    return nil unless data[:existing_repository_id].present?

    @existing_repository = Repository.find_by(id: data[:existing_repository_id])
  end

  protected

  def target_uniqueness_condition_on_start
    # We can't evaluate uniqueness when starting the orchestration as the fork repository is not created yet
  end

  private

  attr_reader :built_repository
  attr_reader :forker
  attr_reader :owner

  def parent_repository
    return @parent_repository if defined?(@parent_repository)

    @parent_repository = Repository.find_by(id: data[:parent_repository_id])
  end
end
