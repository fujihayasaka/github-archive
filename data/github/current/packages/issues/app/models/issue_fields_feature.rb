# typed: strict
# frozen_string_literal: true

# Represents the feature of issue fields as a whole.
module IssueFieldsFeature
  extend T::Helpers

  ISSUE_FIELDS_FLAG = :issue_fields
  ISSUE_FIELDS_USER_FLAG = :issue_fields_actor_can_see
  DISABLE_PROJECT_ISSUE_FIELDS_FLAG = :disable_project_issue_fields
  ISSUE_FIELDS_GLOBAL_SEARCH_FLAG = :issue_fields_global_search
  ISSUE_FIELDS_VISIBILITY_SETTINGS_FLAG = :issue_fields_visibility_settings

  sig { params(entity: T.any(Repository, Organization, MemexProject, User), actor: T.nilable(User), context: T.nilable(Context)).returns(T::Boolean) }
  def self.enabled?(entity, actor: nil, context: Context::WebRequest)
    if entity.is_a?(Organization)
      return true if FeatureFlag.vexi.enabled?(ISSUE_FIELDS_FLAG, default: false)

      if context&.requires_actor? && actor.nil? && !visibility_settings_enabled?(entity)
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
      org_owner = T.cast(entity.owner, Organization)
      # issue fields are not enabled in public repositories when the visibility flag is off
      if !visibility_settings_enabled?(org_owner)
        return false unless entity.private?
      end

      return true if FeatureFlag.vexi.enabled?(ISSUE_FIELDS_FLAG, default: false)
      if context&.requires_actor? && actor.nil? && !visibility_settings_enabled?(org_owner)
        return false
      end


      return false unless enabled_for_organization?(org_owner)
      return true unless actor

      enabled_for_user?(actor)
    elsif entity.is_a?(MemexProject)
      enabled_for_project?(entity, actor: actor)
    elsif entity.is_a?(User)
      enabled_for_user?(entity)
    else
      T.absurd(entity)
    end
  end

  sig { params(current_user: User).returns(T::Boolean) }
  def self.issue_fields_global_search_enabled?(current_user)
    # Check if the user has both issue fields and global search flag enabled
    # AND at least one organization has issue fields enabled
    enabled_for_user?(current_user) &&
      current_user.feature_flag_enabled?(ISSUE_FIELDS_GLOBAL_SEARCH_FLAG, default: false) &&
      current_user.organizations.any? { |org| enabled_for_organization?(org) }
  end

  sig { params(org: Organization).returns(T::Boolean) }
  def self.visibility_settings_enabled?(org)
    org.feature_flag_enabled?(ISSUE_FIELDS_VISIBILITY_SETTINGS_FLAG, default: false)
  end

  sig { params(org: Organization).returns(T::Boolean) }
  private_class_method def self.enabled_for_organization?(org)
    org.feature_flag_enabled_or_raise?(ISSUE_FIELDS_FLAG) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
  end

  sig { params(user: User).returns(T::Boolean) }
  private_class_method def self.enabled_for_user?(user)
    user.feature_flag_enabled_or_raise?(ISSUE_FIELDS_USER_FLAG) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
  end

  sig { params(project: MemexProject, actor: T.nilable(User)).returns(T::Boolean) }
  private_class_method def self.enabled_for_project?(project, actor: nil)
    return false unless actor
    return false unless project.owner.is_a?(Organization)
    unless project.owner.enterprise_managed_user_enabled?
      return false unless project.private?
    end
    return false unless self.enabled?(project.owner, actor: actor)
    return false if FeatureFlag.vexi.enabled?(DISABLE_PROJECT_ISSUE_FIELDS_FLAG, actor, default: false)
    !FeatureFlag.vexi.enabled?(DISABLE_PROJECT_ISSUE_FIELDS_FLAG, project.owner, default: false)
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
