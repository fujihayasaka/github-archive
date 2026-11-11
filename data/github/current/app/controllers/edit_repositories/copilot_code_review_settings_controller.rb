# typed: strict
# frozen_string_literal: true

class EditRepositories::CopilotCodeReviewSettingsController < AbstractRepositoryController
  include ApplicationController::JsonDependency

  javascript_bundle :copilot

  before_action :ensure_admin_access

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Iam,
    ApplicationRecord::Memex,
    ApplicationRecord::Copilot,
    only: [:index]

  REACT_BUNDLE_NAME = "copilot-code-review-repo-settings"
  DEFAULT_QUALIFIED_APPROVAL_SCOPE_WHEN_ENABLED =
    PullRequests::Copilot::CodeReviewRepositoryApprovalSettings::QUALIFIED_APPROVAL_SCOPE_WHEN_ENABLED_ALL_FILES

  sig { returns(String) }
  def self.react_bundle_name
    REACT_BUNDLE_NAME
  end

  sig { void }
  def index
    render_react_app(
      payload: build_json_safe_react_settings_payload,
      title: "Settings · Copilot Code review · #{current_repository.name_with_display_owner}",
      page_data: {
        selected_link: :repo_settings_copilot_coding_guidelines,
      },
      layout: "layouts/repository/edit_repositories",
    )
  end

  private

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def build_json_safe_react_settings_payload
    payload = build_react_settings_payload
    assert_json_safe_react_payload!(payload)
    payload
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def build_react_settings_payload
    {
      endpoints: {
        settings: code_review_repository_settings_path(current_repository.owner, current_repository),
        qualifiedApproval: repo_code_review_repository_qualified_approval_settings_path(
          current_repository.owner,
          current_repository,
        ),
      },
      learnMoreUrl: "https://docs.github.com/en/copilot/how-tos/use-copilot-agents/" \
        "request-a-code-review/use-code-review",
      generalSettings: build_general_settings_payload,
      approvalSettings: build_approval_settings_payload,
      rulesets: build_rulesets_payload,
      codingGuidelines: build_removed_coding_guidelines_payload,
    }
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def build_general_settings_payload
    settings_row = PullRequests::Copilot::CodeReviewRepositorySettings.find_by(repository: current_repository)
    custom_instructions_default_on = settings_row.nil? || settings_row.repo_custom_instructions_enabled
    mcp_default_on = settings_row.nil? || settings_row.repo_mcp_enabled
    effort_level = settings_row&.repo_review_effort_level
    effort_level = "low" if effort_level.blank? || effort_level == "unknown"

    {
      customInstructionsEnabled: custom_instructions_default_on,
      customInstructionsFeatureEnabled: true,
      customInstructionsDocsUrl: helpers.docs_url("copilot/add-repo-custom-instructions"),

      autoApproveEnabled: !!settings_row&.repo_auto_approve_enabled,
      autoApproveFeatureEnabled: react_payload_auto_approve_feature_enabled?,

      mcpEnabled: mcp_default_on,
      mcpFeatureEnabled: react_payload_mcp_feature_enabled?,
      codingAgentSettingsUrl: react_payload_coding_agent_settings_url,
      codingAgentSettingsLabel: react_payload_coding_agent_settings_label,

      reviewEffortLevel: effort_level,
      reviewEffortLevelFeatureEnabled: react_payload_review_effort_level_feature_enabled?,
    }
  end

  sig { returns(T::Boolean) }
  def react_payload_auto_approve_feature_enabled?
    current_repository.feature_enabled_for_repo_or_owner?(:ccr_auto_approve_reviews)
  end

  sig { returns(T::Boolean) }
  def react_payload_qualified_approval_feature_enabled?
    current_repository.feature_enabled_for_repo_or_owner?(:ccr_copilot_qualified_approvals)
  end

  sig { returns(T::Boolean) }
  def react_payload_force_qualified_approval_feature_enabled?
    FeatureFlag.vexi.enabled?(
      :ccr_force_copilot_qualified_approvals,
      current_repository,
      current_repository.owner,
      default: false,
    )
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def build_approval_settings_payload
    {
      visible: react_payload_render_approval_settings?,
      approvalGenerationEnabled: react_payload_approval_generation_effectively_enabled?,
      organizationSettingsUrl: react_payload_org_code_review_approvals_url,
      autoApprove: {
        featureEnabled: react_payload_auto_approve_feature_enabled?,
        enabled: react_payload_approval_effectively_enabled?,
        delegatedEnabled: react_payload_repo_auto_approve_when_delegated?,
        toggleRendered: react_payload_auto_approve_toggle_rendered?,
        forcedByOrg: react_payload_approval_forced_enabled_by_org?,
        forcedByRollout: false,
        disabledByOrg: react_payload_approval_disabled_by_org?,
      },
      qualifiedApproval: {
        featureEnabled: react_payload_qualified_approval_feature_enabled?,
        enabled: react_payload_qualified_approval_effectively_enabled?,
        delegatedEnabled: react_payload_repo_qualified_approval_when_delegated?,
        toggleRendered: react_payload_qualified_approval_toggle_rendered?,
        forcedByOrg: react_payload_qualified_approval_forced_enabled_by_org?,
        forcedByRollout: react_payload_force_qualified_approval_feature_enabled?,
        disabledByOrg: react_payload_qualified_approval_disabled_by_org?,
        formRendered: react_payload_qualified_approval_form_rendered?,
        scopeWhenEnabled: react_payload_repo_qualified_approval_scope_when_enabled,
        filePatterns: react_payload_repo_qualified_approval_file_patterns_text,
        maxFilePatternCount: PullRequests::Copilot::CodeReviewRepositoryApprovalSettings::MAX_FILE_PATTERN_COUNT,
      },
    }
  end

  sig { returns(T::Boolean) }
  def react_payload_render_approval_settings?
    react_payload_auto_approve_feature_enabled? ||
      (react_payload_qualified_approval_feature_enabled? && react_payload_approval_generation_effectively_enabled?)
  end

  sig { returns(T::Boolean) }
  def react_payload_repo_auto_approve_when_delegated?
    react_payload_repo_approval_settings&.auto_approve_when_delegated? || false
  end

  sig { returns(T::Boolean) }
  def react_payload_repo_qualified_approval_when_delegated?
    react_payload_repo_approval_settings&.qualified_approval_when_delegated? || false
  end

  sig { returns(String) }
  def react_payload_repo_qualified_approval_scope_when_enabled
    settings = react_payload_repo_approval_settings
    return DEFAULT_QUALIFIED_APPROVAL_SCOPE_WHEN_ENABLED if settings.nil?

    settings.qualified_approval_scope_when_enabled.to_s
  end

  sig { returns(String) }
  def react_payload_repo_qualified_approval_file_patterns_text
    react_payload_repo_approval_settings&.qualified_approval_file_patterns_text || ""
  end

  sig { returns(PullRequests::Copilot::QualifiedApprovalPolicy) }
  memoize def react_payload_approval_policy
    PullRequests::Copilot::QualifiedApprovalPolicy.new(
      repository: current_repository,
      repo_approval_settings_resolver: -> { react_payload_repo_approval_settings },
    )
  end

  sig { returns(T::Boolean) }
  def react_payload_approval_forced_enabled_by_org?
    react_payload_approval_policy.approval_forced_enabled_by_org?
  end

  sig { returns(T::Boolean) }
  def react_payload_approval_delegated_to_repo?
    react_payload_approval_policy.approval_delegated_to_repo?
  end

  sig { returns(T::Boolean) }
  def react_payload_approval_disabled_by_org?
    !react_payload_approval_policy.approval_access_allowed?
  end

  sig { returns(T::Boolean) }
  def react_payload_approval_effectively_enabled?
    return false unless react_payload_auto_approve_feature_enabled?
    return true if react_payload_approval_forced_enabled_by_org?
    return false if react_payload_approval_disabled_by_org?
    return false unless react_payload_approval_delegated_to_repo?

    react_payload_repo_auto_approve_when_delegated?
  end

  sig { returns(T::Boolean) }
  def react_payload_approval_generation_effectively_enabled?
    react_payload_approval_effectively_enabled?
  end

  sig { returns(T::Boolean) }
  def react_payload_auto_approve_toggle_rendered?
    react_payload_approval_delegated_to_repo?
  end

  sig { returns(T::Boolean) }
  def react_payload_qualified_approval_forced_enabled_by_org?
    react_payload_approval_policy.qualified_approval_forced_enabled_by_org?
  end

  sig { returns(T::Boolean) }
  def react_payload_qualified_approval_delegated_to_repo?
    react_payload_approval_policy.qualified_approval_delegated_to_repo?
  end

  sig { returns(T::Boolean) }
  def react_payload_qualified_approval_disabled_by_org?
    !react_payload_approval_policy.qualified_approval_access_allowed?
  end

  sig { returns(T::Boolean) }
  def react_payload_qualified_approval_effectively_enabled?
    react_payload_approval_policy.qualified_approval_enabled?
  end

  sig { returns(T::Boolean) }
  def react_payload_qualified_approval_toggle_rendered?
    return false if react_payload_force_qualified_approval_feature_enabled?

    react_payload_qualified_approval_delegated_to_repo?
  end

  sig { returns(T::Boolean) }
  def react_payload_qualified_approval_form_rendered?
    return false if react_payload_force_qualified_approval_feature_enabled?

    !react_payload_qualified_approval_disabled_by_org?
  end

  sig { returns(T.nilable(String)) }
  def react_payload_org_code_review_approvals_url
    organization = current_repository.organization
    return nil unless organization
    return nil unless react_payload_show_org_code_review_approvals_link?(organization)

    settings_org_copilot_code_review_path(organization)
  end

  sig { params(organization: Organization).returns(T::Boolean) }
  def react_payload_show_org_code_review_approvals_link?(organization)
    user = current_user
    return false unless user

    !!(organization.adminable_by?(user) &&
      react_payload_org_code_review_settings_enabled?(organization) &&
      react_payload_org_has_copilot_code_review_settings_access?(organization))
  end

  sig { params(organization: Organization).returns(T::Boolean) }
  def react_payload_org_has_copilot_code_review_settings_access?(organization)
    return false if organization.plan.legacy?

    copilot_organization = ::Copilot::Organization.new(organization)
    copilot_organization.has_copilot_for_business? || copilot_organization.has_trial?
  end

  sig { params(organization: Organization).returns(T::Boolean) }
  def react_payload_org_code_review_settings_enabled?(organization)
    organization.feature_flag_enabled?(:ccr_auto_approve_reviews, default: false) ||
      organization.feature_flag_enabled?(:ccr_copilot_qualified_approvals, default: false)
  end

  sig { returns(T.nilable(PullRequests::Copilot::CodeReviewRepositoryApprovalSettings)) }
  memoize def react_payload_repo_approval_settings
    PullRequests::Copilot::CodeReviewRepositoryApprovalSettings.find_by(repository: current_repository)
  end

  sig { returns(T::Boolean) }
  def react_payload_mcp_feature_enabled?
    current_repository.feature_enabled_for_repo_or_owner?("copilot-code-reviews-enable-mcp-proxy") || react_payload_preview_mcp_skills_enabled?
  end

  sig { returns(T::Boolean) }
  def react_payload_preview_mcp_skills_enabled?
    return false unless FeatureFlag.vexi.enabled?("ccr-enable-preview-mcp-skills", [current_repository, current_repository.owner], default: false)

    if current_repository.in_organization?
      org = current_repository.organization
      return false unless org

      copilot_org = ::Copilot::Organization.new(org)
      copilot_org.code_review_beta_features_enabled?
    else
      copilot_user = current_copilot_user_v2
      return false unless copilot_user

      copilot_user.code_review_beta_features_enabled?
    end
  end

  sig { returns(String) }
  def react_payload_coding_agent_settings_url
    if react_payload_preview_mcp_skills_enabled?
      repo_repo_settings_copilot_mcp_path(current_repository.owner_display_login, current_repository.name)
    else
      repo_repo_settings_copilot_swe_agent_path(current_repository.owner, current_repository.name)
    end
  end

  sig { returns(String) }
  def react_payload_coding_agent_settings_label
    if react_payload_preview_mcp_skills_enabled?
      "MCP servers"
    else
      "Cloud agent settings"
    end
  end

  sig { returns(T::Boolean) }
  def react_payload_review_effort_level_feature_enabled?
    !!Copilot::CodeReview::Features.preview_features_enabled_for_repo?(current_repository)
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def build_rulesets_payload
    copilot_rule_types = ["copilot_code_review"]
    all_rule_types = copilot_rule_types + ["pull_request"]

    org_rulesets = if current_repository.owner.is_a?(Organization)
      potential_org_rulesets = current_repository.owner.rulesets
        .joins(:rule_configurations)
        .where(target: "branch")
        .where(repository_rule_configurations: { rule_type: all_rule_types })
        .where("repository_rule_configurations.rule_type IN (?)", copilot_rule_types)
        .includes(:rule_configurations, :conditions)

      potential_org_rulesets.select do |ruleset|
        ruleset.definition.applies_to_source?(ruleset, current_repository)
      end
    else
      []
    end

    repo_rulesets = current_repository.rulesets
      .joins(:rule_configurations)
      .where(target: "branch")
      .where(repository_rule_configurations: { rule_type: all_rule_types })
      .where("repository_rule_configurations.rule_type IN (?)", copilot_rule_types)
      .includes(:rule_configurations, :conditions)

    ruleset_to_hash = ->(ruleset, org_managed) do
      ccr_rule = ruleset.rule_configurations.find { |rc| rc.rule_type == "copilot_code_review" }
      url = if org_managed
        organization_ruleset_path(current_repository.owner, ruleset)
      else
        repository_ruleset_path(current_repository.owner, current_repository, ruleset)
      end
      rule_payload = if ccr_rule.present?
        {
          reviewOnPush: !!ccr_rule.param("review_on_push"),
          reviewDraftPullRequests: !!ccr_rule.param("review_draft_pull_requests"),
        }
      end
      {
        id: ruleset.id,
        name: ruleset.name,
        enforcement: ruleset.enforcement,
        url: url,
        ruleConfigurationsCount: ruleset.rule_configurations.size,
        conditionsCount: ruleset.conditions.size,
        rule: rule_payload,
      }
    end

    {
      orgRulesets: org_rulesets.map { |r| ruleset_to_hash.call(r, true) },
      repoRulesets: repo_rulesets.map { |r| ruleset_to_hash.call(r, false) },
      orgOwnerName: current_repository.owner.name,
      viewAllRulesetsUrl: repository_rulesets_path(current_repository.owner, current_repository),
      createRulesetUrl: repo_create_copilot_ruleset_repo_repo_settings_copilot_code_review_path(
        current_repository.owner,
        current_repository,
      ),
      deferredTargetCountsUrl: repository_ruleset_deferred_target_counts_path(
        current_repository.owner.display_login,
        current_repository.name,
      ),
      docsUrl: Copilot::CODE_REVIEW_CONFIGURING_AUTO_DOCS_URL,
    }
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def build_removed_coding_guidelines_payload
    {
      featureEnabled: false,
      featureDisabled: true,
      guidelines: [],
      enabledCount: 0,
      totalCount: 0,
      maxPerRepo: 0,
      newGuidelineUrl: "",
    }
  end

  sig { params(value: T.untyped).void }
  def assert_json_safe_react_payload!(value)
    case value
    when Hash
      value.each do |key, nested_value|
        unless key.is_a?(String) || key.is_a?(Symbol)
          raise TypeError, "React payload hash keys must be strings or symbols"
        end

        assert_json_safe_react_payload!(nested_value)
      end
    when Array
      value.each { |nested_value| assert_json_safe_react_payload!(nested_value) }
    when String, Integer, Float, TrueClass, FalseClass, NilClass
      true
    else
      raise TypeError, "React payload includes non-JSON-safe #{value.class.name}"
    end
  end
end
