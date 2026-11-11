# typed: strict
# frozen_string_literal: true

# Represents the feature of issue fields as a whole.
module IssueFieldsFeature
  extend T::Helpers

  ISSUE_FIELDS_FLAG = :issue_fields
  DISABLE_PROJECT_ISSUE_FIELDS_FLAG = :disable_project_issue_fields
  ISSUE_FIELDS_IN_PUBLIC_PROJECTS_FLAG = :issue_fields_in_public_projects
  ISSUE_FIELDS_MULTI_SELECT_FLAG = :issue_fields_multi_select

  # Feature flag gating repository.issueFields and the associated option-wrapping /
  # parent-field-loading changes introduced in this PR. Rolled out per-org or per-viewer;
  # can also be enabled globally as a kill switch. Disable to revert to pre-launch behaviour
  # if performance regressions are observed.
  REPO_ISSUE_FIELDS_FLAG = :repo_issue_fields

  sig { params(org: T.nilable(Organization), actor: T.nilable(User)).returns(T::Boolean) }
  def self.repo_issue_fields_enabled?(org: nil, actor: nil)
    return true if FeatureFlag.vexi.enabled?(REPO_ISSUE_FIELDS_FLAG, default: false)
    return true if org && FeatureFlag.vexi.enabled?(REPO_ISSUE_FIELDS_FLAG, org, default: false)
    return true if actor && FeatureFlag.vexi.enabled?(REPO_ISSUE_FIELDS_FLAG, actor, default: false)
    false
  end

  sig { params(entity: T.any(Repository, Organization, MemexProject, User), actor: T.nilable(User), context: T.nilable(Context)).returns(T::Boolean) }
  def self.enabled?(entity, actor: nil, context: Context::WebRequest)
    if entity.is_a?(Organization)
      return true if FeatureFlag.vexi.enabled?(ISSUE_FIELDS_FLAG, default: false)

      enabled_for_organization?(entity)
    elsif entity.is_a?(Repository)
      # issue fields are not enabled in user-owned repo
      return false unless entity.owner.is_a?(Organization)
      org_owner = T.cast(entity.owner, Organization)

      return true if FeatureFlag.vexi.enabled?(ISSUE_FIELDS_FLAG, default: false)

      enabled_for_organization?(org_owner)
    elsif entity.is_a?(MemexProject)
      enabled_for_project?(entity, actor: actor)
    elsif entity.is_a?(User)
      true
    else
      T.absurd(entity)
    end
  end

  # Check if the multi-select data type is enabled for the given org.
  # Requires the base issue_fields feature to be enabled first.
  sig { params(org: Organization).returns(T::Boolean) }
  def self.multi_select_enabled?(org)
    return false unless enabled_for_organization?(org)
    org.feature_flag_enabled?(ISSUE_FIELDS_MULTI_SELECT_FLAG, default: false)
  end

  sig { params(current_user: User).returns(T::Boolean) }
  def self.issue_fields_global_search_enabled?(current_user)
    current_user.organizations.any? do |org|
      enabled_for_organization?(org)
    end
  end

  sig { params(org: Organization).returns(T::Boolean) }
  private_class_method def self.enabled_for_organization?(org)
    org.feature_flag_enabled_or_raise?(ISSUE_FIELDS_FLAG) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
  end

  sig { params(project: MemexProject, actor: T.nilable(User)).returns(T::Boolean) }
  private_class_method def self.enabled_for_project?(project, actor: nil)
    return false unless project.owner.is_a?(Organization)

    if project.private?
      return false unless actor
    else
      return false unless FeatureFlag.vexi.enabled?(ISSUE_FIELDS_IN_PUBLIC_PROJECTS_FLAG, project.owner, default: false)
    end

    return false unless self.enabled?(project.owner, actor: actor)
    return false if actor && FeatureFlag.vexi.enabled?(DISABLE_PROJECT_ISSUE_FIELDS_FLAG, actor, default: false)
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
