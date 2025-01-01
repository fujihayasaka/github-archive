# typed: true
# frozen_string_literal: true

module Issue::PermissionsDependency
  extend T::Helpers

  requires_ancestor { Issue }

  TRIAGEABLE_ROLES = [:triage, :write, :maintain, :admin].freeze

  # Public: Can the user set the issue milestone?
  #
  # Returns Boolean
  def can_set_milestone?(user)
    async_can_set_milestone?(user).sync
  end

  # Public: Can the user set the issue milestone?
  #
  # actor - The User to check permissions for.
  #
  # Returns a Promise<Boolean>.
  def async_can_set_milestone?(user)
    return Promise.resolve(false) unless user

    async_pull_request.then do |pull|
      subject = pull.present? ? pull : self
      Platform::Loaders::Permissions::BatchAuthorize.load(
        action: :set_milestone,
        actor: user,
        subject: subject,
      ).then do |decision|
        decision.allow?
      end
    end
  end

  # Public: Can the user mark/unmark an issue as duplicated?
  #
  # Returns Boolean
  def can_mark_as_duplicate?(user)
    return false unless user

    ::Permissions::Enforcer.authorize(
      action: :mark_as_duplicate,
      actor: user,
      subject: self,
    ).allow?
  end

  # Public: Can transfer issue?
  #
  # Returns Boolean
  def can_transfer_issue?(user, repo)
    return false unless user
    return false unless repo

    ::Permissions::Enforcer.authorize(
      action: :transfer_issue,
      actor: user,
      subject: repo,
    ).allow?
  end

  # Public: Determines if a user can delete the issue
  #
  # Returns Promise(Boolean) - true if allowed, false otherwise
  def async_deleteable_by?(user)
    return Promise.resolve(false) unless user
    return Promise.resolve(false) if pull_request?

    async_fgp_deleteable_by?(user)
  end

  # Public: Determines if a user can delete the issue
  #
  # Returns Boolean true if allowed, false otherwise
  def deleteable_by?(user)
    async_deleteable_by?(user).sync
  end

  def async_fgp_deleteable_by_result(user)
    Platform::Loaders::Permissions::BatchAuthorize.load(
      action: :delete_issue,
      actor: user,
      subject: self,
    )
  end

  def async_fgp_deleteable_by?(user)
    async_fgp_deleteable_by_result(user).then do |decision|
      decision.allow?
    end
  end

  # Public: Can a user label this issue?
  #
  # actor - The User to check permissions for.
  #
  # Returns a Boolean.
  def labelable_by?(actor:)
    async_labelable_by?(actor: actor).sync
  end

  # Public: Can a user label this issue?
  #
  # actor - The User to check permissions for.
  #
  # Returns a Promise<Boolean>.
  def async_labelable_by?(actor:)
    return Promise.resolve(false) unless actor

    async_pull_request.then do |pull|
      subject = pull.present? ? pull : self
      Platform::Loaders::Permissions::BatchAuthorize.load(
        action: :add_label,
        actor: actor,
        subject: subject,
      ).then do |decision|
        decision.allow?
      end
    end
  end

  # Public: Can a user set an issue type for this issue?
  #
  # actor - The User to check permissions for.
  #
  # Returns a Boolean.
  def can_set_type?(actor:)
    async_can_set_type?(actor: actor).sync
  end

  # Public: Can a user set an issue type for this issue?
  #
  # actor - The User to check permissions for.
  #
  # Returns a Promise<Boolean>.
  def async_can_set_type?(actor:)
    return Promise.resolve(false) unless actor

    Platform::Loaders::Permissions::BatchAuthorize.load(
      action: :set_issue_type,
      actor: actor,
      subject: self,
    ).then(&:allow?)
  end

  # Public: Can a user assign this issue to a user?
  #
  # actor - The User to check permissions for.
  #
  # Returns a Boolean.
  def assignable_by?(actor:)
    async_assignable_by?(actor: actor).sync
  end

  # Public: Can a user assign this issue to a user?
  #
  # actor - The User to check permissions for.
  #
  # Returns a Promise<Boolean>.
  def async_assignable_by?(actor:)
    return Promise.resolve(false) unless actor

    async_pull_request.then do |pull|
      subject = pull.present? ? pull : self
      Platform::Loaders::Permissions::BatchAuthorize.load(
        action: :add_assignee,
        actor: actor,
        subject: subject,
      ).then do |decision|
        decision.allow?
      end
    end
  end

  def self.repo_triageable_by?(actor, repo)
    if actor.is_a?(User)
      Issue::PermissionsDependency::triageable_by_user?(actor, repo)
    elsif actor.is_a?(Team)
      Issue::PermissionsDependency::triageable_by_team?(actor, repo)
    else
      false
    end
  end

  # Public: Can a user or team triage this issue?
  #
  # actor - The User or Team to check permissions for.
  #
  # Returns a Boolean.
  def triageable_by?(actor)
    Issue::PermissionsDependency::repo_triageable_by?(actor, repository)
  end

  def self.triageable_by_user?(user, repo)
    return false if user.nil? || repo.locked?
    repo.pushable_by?(user) || repo.role_based_access_level(user).in?(TRIAGEABLE_ROLES)
  end

  def self.triageable_by_team?(team, repo)
    return false if repo.locked?
    team.present? && repo.role_based_access_level(team).in?(TRIAGEABLE_ROLES)
  end

  # Public: Can the user set tracked by for issue?
  #
  # actor - The User to check permissions for.
  # parent_issues - The Issues the User is trying to set tracked by for.
  #
  # Returns Boolean
  def can_set_tracked_by?(actor:, parent_issues:)
    return false if actor.nil? || T.must(repository).locked?
    return false unless T.must(repository).pushable_by?(actor)
    !parent_issues.find do |parent_issue|
      !parent_issue.repository.pushable_by?(actor)
    end
  end

  # Public: Can the user add sub-issues to an issue?
  #
  # actor - The User to check permissions for.
  # parent_issue_id - The id  of the Issue the User is trying to add sub-issues to
  #
  # Returns Boolean
  def can_add_sub_issue?(actor:, parent_issue_id:)
    return false if actor.nil? || T.must(repository).locked?
    return false unless T.must(repository).pushable_by?(actor)

    parent_issue = Issue.find_by(id: parent_issue_id)
    return unless parent_issue

    parent_issue.repository&.pushable_by?(actor)
  end
end
