# typed: strict
# frozen_string_literal: true

# Represents the feature of issue fields as a whole.
module IssueFieldsFeature
  extend T::Helpers

  ISSUE_FIELDS_FLAG = :issue_fields
  ISSUE_FIELDS_USER_FLAG = :issue_fields_actor_can_see

  sig { params(entity: T.any(Repository, Organization), actor: T.nilable(User)).returns(T::Boolean) }
  def self.enabled?(entity, actor: nil)
    if entity.is_a?(Organization)
      return true if FeatureFlag.vexi.enabled?(ISSUE_FIELDS_FLAG, default: false)

      enabled_for_organization?(entity) && actor ? enabled_for_user?(actor) : false
    elsif entity.is_a?(Repository)
      # issue fields are not enabled in user-owned repo
      return false unless entity.owner.is_a?(Organization)
      return true if FeatureFlag.vexi.enabled?(ISSUE_FIELDS_FLAG, default: false)

      enabled_for_repository?(entity) && actor ? enabled_for_user?(actor) : false
    else
      T.absurd(entity)
    end
  end

  sig { params(org: Organization).returns(T::Boolean) }
  private_class_method def self.enabled_for_organization?(org)
    org.feature_enabled?(ISSUE_FIELDS_FLAG)
  end

  sig { params(repo: Repository).returns(T::Boolean) }
  private_class_method def self.enabled_for_repository?(repo)
    return false unless repo.owner.is_a?(Organization)
    repo.feature_enabled?(ISSUE_FIELDS_FLAG)
  end

  sig { params(user: User).returns(T::Boolean) }
  private_class_method def self.enabled_for_user?(user)
    user.feature_enabled?(ISSUE_FIELDS_USER_FLAG)
  end
end
