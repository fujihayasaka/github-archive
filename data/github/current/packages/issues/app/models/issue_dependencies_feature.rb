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
# repo = Repository.find(...)
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
# repo = Repository.find(...) # doesn't have feature enabled
#
# IssueDependenciesFeature.enabled?(repo, actor: actor)
# ```
module IssueDependenciesFeature
  extend T::Helpers

  ISSUE_DEPENDENCIES_FLAG = :issue_dependencies
  # Flag used for internal development purposes only.
  INTERNAL_DEV_FLAG = :issue_dependencies_internal_dev

  sig { params(entity: T.nilable(T.any(Repository, Organization, User)), actor: T.nilable(User)).returns(T::Boolean) }
  def self.enabled?(entity, actor: nil)
    return false unless entity
    return true if actor && enabled_for_user?(actor)

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
    org.feature_enabled?(ISSUE_DEPENDENCIES_FLAG)
  end

  sig { params(user: User).returns(T::Boolean) }
  private_class_method def self.enabled_for_user?(user)
    user.feature_enabled?(ISSUE_DEPENDENCIES_FLAG)
  end

  sig { params(repo: Repository).returns(T::Boolean) }
  private_class_method def self.enabled_for_repository?(repo)
    return false unless (owner = repo.owner)
    return true if self.enabled?(owner)
    repo.feature_enabled?(ISSUE_DEPENDENCIES_FLAG)
  end

  # Returns `true` if the internal feature flag is enabled. Used for checking if
  # internal, currently in-development features should be enabled for a user.
  sig { params(user: T.nilable(User)).returns(T::Boolean) }
  def self.enabled_internally_for_user?(user)
    FeatureFlag.vexi.enabled?(INTERNAL_DEV_FLAG, user, default: false)
  end
end
