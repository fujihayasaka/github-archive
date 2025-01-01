# typed: strict
# frozen_string_literal: true

# Represents the feature of sub-issues as a whole. Can be used to check whether this feature is enabled
# on a "per-owner" basis, rather than per-user or per-viewer as typical features are checked.
#
# ## Example
#
# To check if sub-issues should be enabled for a user/repository/organization, you can use the `enabled?` method:
#
# ```ruby
# user = User.find(...)
# SubIssuesFeature.enabled?(user)
#
# repo = Repository.find(...)
# SubIssuesFeature.enabled?(repo)
#
# org = Organization.find(...)
# SubIssuesFeature.enabled?(org)
#
# project = MemexProject.find(...)
# SubIssuesFeature.enabled?(project)
# ```
#
# ### Actor checks
#
# If you need to check if the flag should be enabled for an actor within the context of another entity, you can
# pass the `actor` argument. For example, this is useful when checking if a user could add sub-issues to a repository
# which is owned by an organization that has the sub-issues feature enabled.
#
# ```ruby
# actor = User.find(...)
# repo = Repository.find(...)
#
# SubIssuesFeature.enabled?(repo, actor: actor)
# ```
module SubIssuesFeature
  extend T::Helpers

  SUB_ISSUES_FLAG = :sub_issues

  # Returns whether the sub-issues feature should be considered enabled for the given entity. Feature enablement
  # is checked hierarchically, such that if sub-issues are enabled for an organization, it should be considered
  # enabled for all repositories or projects owned by that organization.
  sig { params(entity: T.nilable(T.any(Repository, Organization, User, MemexProject)), actor: T.nilable(User)).returns(T::Boolean) }
  def self.enabled?(entity, actor: nil)
    return false unless entity
    return true if GitHub.issues_react_ghes_enabled?
    if entity.is_a?(Organization)
      enabled_for_organization?(entity, actor: actor)
    elsif entity.is_a?(Repository)
      enabled_for_repository?(entity, actor: actor)
    elsif entity.is_a?(User)
      # When a resource's owner is a user, we need to check if the user is opted into the new issues experience.
      # This is performed here, because we still want to honor the existing flag hierarchy.
      return false unless entity.feature_preview_enabled?(:issues_react_v2)
      enabled_for_user?(entity, actor: actor)
    elsif entity.is_a?(MemexProject)
      enabled_for_project?(entity, actor: actor)
    else
      T.absurd(entity)
    end
  end

  sig { params(org: Organization, actor: T.nilable(User)).returns(T::Boolean) }
  private_class_method def self.enabled_for_organization?(org, actor: nil)
    # Give us the ability to disable react for specific orgs
    # The check for `issues_react_ga` is a hack so we can avoid updating a million test when all flags are enabled
    return false if org.feature_enabled?(:issues_react_disabled) && !GitHub.flipper[:issues_react_ga].enabled?

    org.feature_enabled?(SUB_ISSUES_FLAG)
  end

  sig { params(user: User, actor: T.nilable(User)).returns(T::Boolean) }
  private_class_method def self.enabled_for_user?(user, actor: nil)
    user.feature_enabled?(SUB_ISSUES_FLAG)
  end

  sig { params(repo: Repository, actor: T.nilable(User)).returns(T::Boolean) }
  private_class_method def self.enabled_for_repository?(repo, actor: nil)
    return false unless (owner = repo.owner)
    return true if self.enabled?(owner, actor: actor)
    repo.feature_enabled?(SUB_ISSUES_FLAG)
  end

  sig { params(project: MemexProject, actor: T.nilable(User)).returns(T::Boolean) }
  private_class_method def self.enabled_for_project?(project, actor: nil)
    return false unless (owner = project.owner)
    return true if self.enabled?(owner, actor: actor)
    project.feature_enabled?(SUB_ISSUES_FLAG)
  end
end
