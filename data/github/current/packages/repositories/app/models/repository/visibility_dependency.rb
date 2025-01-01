# typed: true
# frozen_string_literal: true

module Repository::VisibilityDependency
  extend T::Helpers

  requires_ancestor { Repository }

  VISIBILITY_LOCK_TIMEOUT = 1.hour

  # Check if a repository is open source. github/github is never open source.
  def public?
    return false if GitHub.never_public_network_ids.include? network_id
    read_attribute :public
  end

  # Public: Check whether the repository is private.
  def private?
    !public?
  end

  # Public: Check whether the repository is internal.
  def internal?
    return false if public?
    visibility == Repository::INTERNAL_VISIBILITY
  end

  # Public: Returns a promise for whether or not the repository is internal.
  sig { returns(Promise[T::Boolean]) }
  def async_internal?
    return Promise.resolve(T.let(false, T::Boolean)) if public?
    async_visibility.then { |visibility| visibility == Repository::INTERNAL_VISIBILITY }
  end

  # Public: True if a repository is fully private (not internal) and the root of its network.
  def private_network_root?
    network_root? && visibility == Repository::PRIVATE_VISIBILITY
  end

  # Public: Set the repository access permission to private. This only modifies
  # the database state if the record already exists.
  #
  # value - Boolean specifying whether the repository should be considered
  # private.
  #
  # Returns opposite of value.
  def private=(value)
    self.public = !value
  end

  # Public: The repository's visibility.
  #
  # Returns 'public', 'private', or 'internal'.
  def visibility
    async_visibility.sync
  end

  def async_visibility
    return Promise.resolve(Repository::PUBLIC_VISIBILITY) if public?

    async_internal_repository.then do |internal_repository|
      internal_repository ? Repository::INTERNAL_VISIBILITY : Repository::PRIVATE_VISIBILITY
    end
  end

  # Public: The repository's public or private visibility.
  def public_or_private_visibility
    public? ? Repository::PUBLIC_VISIBILITY : Repository::PRIVATE_VISIBILITY
  end

  # Public: The repository's visibility once toggled.
  #
  # An enterprise-internal repository is considered private, so its toggled visibility is public.
  #
  # Returns 'public' or 'private'
  def toggled_visibility
    public? ? Repository::PRIVATE_VISIBILITY : Repository::PUBLIC_VISIBILITY
  end

  # Internal: Set the permission (public/private) bit to the given
  # value in the database. This should not be called directly because
  # there are no limit checks. Use the Repository#toggle_visibility
  # instead.
  #
  # visibility - :public, :private, or :internal
  #
  # Return true if the visibility was changed, false if the visibility was
  # already set appropriately.
  def set_permission(visibility)
    if owner&.emu_creating_public_repo?(visibility)
      raise ArgumentError, "Enterprise managed resources can't have #{Repository::PUBLIC_VISIBILITY} visibility"
    end

    visibility = visibility.to_s
    unless Repository::VISIBILITIES.include?(visibility)
      raise ArgumentError, "expected one of the following: #{Repository::VISIBILITIES.join(', ')}"
    end

    return false if self.visibility == visibility

    success = T.let(false, T::Boolean)
    transaction do
      case visibility
      when Repository::PRIVATE_VISIBILITY
        self.public = false
        self.internal_repository&.destroy
      when Repository::INTERNAL_VISIBILITY
        owner = T.must(self.owner)
        raise ArgumentError, "Only organization-owned repositories can have #{Repository::INTERNAL_VISIBILITY} visibility" unless owner.organization?
        raise ArgumentError, "Only organizations associated with an enterprise can set visibility to #{Repository::INTERNAL_VISIBILITY}" unless owner.business
        self.internal_repository ||= InternalRepository.new(repository: self, business: owner.business)
        self.internal_repository&.business = owner.business
        self.public = false
      when Repository::PUBLIC_VISIBILITY
        self.public = true
        self.internal_repository&.destroy
      end

      save!
      success = true
      reload_internal_repository # makes calls to Repository#visibility on this instance correct
    end

    success
  end

  def can_change_repo_visibility?(user)
    return false unless user
    return true if user.site_admin? && GitHub.enterprise?
    return false if owner.nil?
    owner = T.must(self.owner)
    return true if !owner.organization?
    return true if owner.adminable_by?(user)
    return true if user.try(:can_have_granular_permissions?) && self.resources.administration.writable_by?(user)
    return false if GitHub.single_business_environment? && !GitHub.global_business&.members_can_change_repo_visibility?
    T.cast(owner, Configurable::MembersCanChangeRepoVisibility).members_can_change_repo_visibility?(to_public: private?)
  end

  def can_change_repo_visibility_with_rules?(user, visibility)
    if self.member_privilege_rulesets_enabled?
      event = RuleEngine::Events::RepositoryOperationEvent.new(T.cast(self, Repository), user, { change_visibility: visibility }, persist_results: false) # rubocop:todo GitHub/AvoidCast
      result = RuleEngine::GenericEvaluator.evaluate_rules(event).first
      result.present? ? result.action_permitted? : true
    else
      true
    end
  end

  # Public: sets repository visibility.
  #
  # If visibility is not provided, visibility is toggled public/private. Repositories having
  # internal visibility are considered private and will have their visibility set to public.
  #
  # Will prevent making a public repository private if the owner paying for
  # the repository is at their private repo limit.
  #
  # Will also prevent changing visibility of forks.
  #
  # Pulls repository out into its own network. Any forks of this repo are
  # reparented according to the following scheme:
  #
  # public -> private/internal: the repo is detached from the network
  # private/internal -> public: the repo is detached from the network
  # and all forks are extracted into their own private networks
  # if repo was the root, or reparented in the network otherwise.
  #
  # actor - Required. the User attempting to change visibility of this repo.
  # Used for can_change_repo_visibility? check.
  # visibility - Optional: "public", "private", or "internal"
  # Returns nil if no change made, or true.
  def toggle_visibility(actor:, visibility: self.toggled_visibility)
    o = RepositoryOrchestration.set_visibility(T.cast(self, Repository), actor: actor, visibility: visibility) # rubocop:todo GitHub/AvoidCast
    o.execute
    o.errors.empty?
  end
  alias :set_visibility :toggle_visibility

  def made_private?
    saved_change_to_public? && private?
  end

  def private_or_deleted?
    made_private? || deleted?
  end

  def set_made_public_at
    self.made_public_at = public? ? Time.current : nil
  end

  # Public: check if the repo is private and shouldn't be
  #
  # Returns a boolean
  def disabled_private?
    private? && cant_be_private?
  end

  # Private: check if the root owners plan supports private repos
  #
  # Returns a Boolean
  private def cant_be_private?
    return false if advisory_workspace?
    user_to_check = T.must(network_root? ? owner : plan_owner)
    !user_to_check.plan_supports?(:repos, visibility: :private, fallback_to_free: user_to_check.disabled?)
  end
end
