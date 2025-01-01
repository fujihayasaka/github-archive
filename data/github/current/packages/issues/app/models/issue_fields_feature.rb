# typed: strict
# frozen_string_literal: true

# Represents the feature of issue fields as a whole.
module IssueFieldsFeature
  extend T::Helpers

  ISSUE_FIELDS_FLAG = :issue_fields
  ISSUE_FIELDS_USER_FLAG = :issue_fields_actor_can_see
  PROJECT_ISSUE_FIELDS_FLAG = :project_issue_fields

  sig { params(entity: T.any(Repository, Organization, MemexProject, User), actor: T.nilable(User), context: T.nilable(Context)).returns(T::Boolean) }
  def self.enabled?(entity, actor: nil, context: Context::WebRequest)
    if entity.is_a?(Organization)
      return true if FeatureFlag.vexi.enabled?(ISSUE_FIELDS_FLAG, default: false)

      if context&.requires_actor? && actor.nil?
        return false
      end

      if enabled_for_organization?(entity)
        (actor ? enabled_for_user?(actor) : true)
      else
        false
      end
    elsif entity.is_a?(Repository)
      # issue fields are not enabled in user-owned repo
      return false unless entity.owner.is_a?(Organization)
      return true if FeatureFlag.vexi.enabled?(ISSUE_FIELDS_FLAG, default: false)

      if context&.requires_actor? && actor.nil?
        return false
      end

      if enabled_for_repository?(entity)
        actor ? enabled_for_user?(actor) : true
      else
        false
      end
    elsif entity.is_a?(MemexProject)
      enabled_for_project?(entity, actor: actor)
    elsif entity.is_a?(User)
      enabled_for_user?(entity)
    else
      T.absurd(entity)
    end
  end

  sig { params(org: Organization).returns(T::Boolean) }
  private_class_method def self.enabled_for_organization?(org)
    org.feature_flag_enabled_or_raise?(ISSUE_FIELDS_FLAG) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
  end

  sig { params(repo: Repository).returns(T::Boolean) }
  private_class_method def self.enabled_for_repository?(repo)
    return false unless repo.owner.is_a?(Organization)
    repo.feature_flag_enabled_or_raise?(ISSUE_FIELDS_FLAG) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
  end

  sig { params(user: User).returns(T::Boolean) }
  private_class_method def self.enabled_for_user?(user)
    user.feature_flag_enabled_or_raise?(ISSUE_FIELDS_USER_FLAG) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
  end

  sig { params(project: MemexProject, actor: T.nilable(User)).returns(T::Boolean) }
  private_class_method def self.enabled_for_project?(project, actor: nil)
    return false unless actor
    return false unless project.owner.is_a?(Organization)
    return false unless project.private?
    return false unless self.enabled?(project.owner, actor: actor)
    return true if FeatureFlag.vexi.enabled?(PROJECT_ISSUE_FIELDS_FLAG, actor, default: false)
    FeatureFlag.vexi.enabled?(PROJECT_ISSUE_FIELDS_FLAG, project.owner, default: false)
  end

  class Context < T::Enum
    enums do
      # Contexts where actor can be missing for the feature check
      ElasticSearch = new("elasticsearch")
      WebRequest = new("web_request")
    end

    sig { returns(T::Boolean) }
    def requires_actor?
      case self
      when ElasticSearch
        false
      when WebRequest
        true
      else
        T.absurd(self)
      end
    end
  end
end
