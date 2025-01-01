# typed: true
# frozen_string_literal: true

module User::RepositoryForkingDependency
  extend T::Helpers

  requires_ancestor { User }

  def fork(repository)
    return [false, :organization] if organization?
    repository.fork(forker: self)
  end

  # Finds this user's fork of a given repository, if one exists.
  #
  # repository - The Repository whose fork you want to find.
  #
  # Returns a Repository if the fork is found.
  # Returns nil if nothing found.
  def my_fork_of(repository)
    repo = repository.find_fork_in_network_for_user(self)
    repo.owner = self if repo
    repo
  end

  def has_forked?(repository)
    !!repository.find_fork_in_network_for_user(self)
  end

  # Public: Can this user fork a specific repository?
  #
  # repository - The repo you want to check
  #  new_owner - The User or Organization who will own the new fork. Defaults
  #              to this user, but if you're trying to fork TO an organization
  #              you'll want to pass that in.
  #
  # Returns a Boolean.
  def can_fork?(repository, new_owner = self)
    # this feels wrong, but we don't want forks from blocked users to show in
    # the fork queue or network graphs
    return false if repository.owner_blocking?(self)
    return false if repository.owner_id == new_owner.id && !new_owner.organization?
    return false if !repository.pullable_by?(self) && !(self.try(:can_have_granular_permissions?) && repository.resources.contents.readable_by?(self))
    return false unless new_owner.can_create_repository?(self, visibility: repository.visibility)

    repository.allows_forking?
  end

  # Public: Can this user fork the specified repository into their account based on configurable policies?
  #         Behaviors in a similar fashion to Organization#fork_allowed?
  #
  # Returns a boolean
  def fork_allowed?(repository)
    return true if repository.public?
    return true unless subject_to_enterprise_fork_policies?(repository)

    repository.allow_private_repository_forking_to_user_accounts?
  end

  def subject_to_enterprise_fork_policies?(repo)
    return false unless repo.in_organization?

    repo.organization&.business.present?
  end

end
