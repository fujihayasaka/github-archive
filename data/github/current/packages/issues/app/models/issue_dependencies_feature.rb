# typed: strict
# frozen_string_literal: true

# Represents the feature of issue dependencies as a whole. Can be used to check whether this feature is enabled
# on a "per-owner" basis, rather than per-user or per-viewer as typical features are checked.
#
# ## Example
#
# To check if issue dependencies should be enabled for a user/repository/organization, you can use the `enabled?` method:
#
# ```ruby
# user = User.find(...)
# IssueDependenciesFeature.enabled?(user)
#
# repo = RepositoryRepositories.domain.by_id(...)
# IssueDependenciesFeature.enabled?(repo)
#
# org = Organization.find(...)
# IssueDependenciesFeature.enabled?(org)
#
# project = MemexProject.find(...)
# IssueDependenciesFeature.enabled?(project)
# ```
#
# ### Actor checks
#
# If you need to check if the flag should be enabled for a specific actor (such as a user), you can
# pass the `actor` argument. If the feature is enabled for the given actor, `enabled?` will return true
# regardless of the entity's feature flag state.
#
# ```ruby
# actor = User.find(...) # has feature enabled
# repo = Repositories.domain.by_id(...) # doesn't have feature enabled
#
# IssueDependenciesFeature.enabled?(repo, actor: actor)
# ```
module IssueDependenciesFeature
  extend T::Helpers

  ISSUE_DEPENDENCIES_FLAG = :issue_dependencies

  sig { params(entity: T.nilable(T.any(Repository, Organization, User)), actor: T.nilable(User)).returns(T::Boolean) }
  def self.enabled?(entity, actor: nil)
    return true if actor && enabled_for_user?(actor)
    return false unless entity

    if entity.is_a?(Organization)
      enabled_for_organization?(entity)
    elsif entity.is_a?(Repository)
      enabled_for_repository?(entity)
    elsif entity.is_a?(User)
      enabled_for_user?(entity)
    else
      T.absurd(entity)
    end
  end

  sig { params(org: Organization).returns(T::Boolean) }
  private_class_method def self.enabled_for_organization?(org)
    return true if GitHub.enterprise?
    org.feature_flag_enabled?(ISSUE_DEPENDENCIES_FLAG, default: false)
  end

  sig { params(user: User).returns(T::Boolean) }
  private_class_method def self.enabled_for_user?(user)
    return true if GitHub.enterprise?
    user.feature_flag_enabled?(ISSUE_DEPENDENCIES_FLAG, default: false)
  end

  sig { params(repo: Repository).returns(T::Boolean) }
  private_class_method def self.enabled_for_repository?(repo)
    return true if GitHub.enterprise?
    return false unless (owner = repo.owner)
    return true if self.enabled?(owner)
    repo.feature_flag_enabled?(ISSUE_DEPENDENCIES_FLAG, default: false)
  end
end
