# typed: true
# frozen_string_literal: true

class Dependabot::DependabotOrgRulesController < Orgs::Controller
  include DependabotAlerts::RulesControllerHelper

  MAX_RULES_COUNT = 20

  depends_on_clusters ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Notify,
    ApplicationRecord::Repositories,
    only: [:index, :new, :edit, :edit_global_rule]

  before_action :login_required
  before_action :check_dependabot_org_rules_feature_enabled
  before_action :manage_security_products_permission_required
  before_action :find_rule_with_authorization, only: [:edit, :update, :destroy]
  before_action :find_global_rule, only: [:edit_global_rule]

  rate_limit_requests \
    only: [:create, :destroy, :update, :update_global_rule],
    key: :rate_limit_key,
    max: 100,
    ttl: 1.hour,
    at_limit: :flash_rate_limit_error

  javascript_bundle :settings

  PAGE_SIZE = 10

  def index
    # This avoids a n+1 query when rendering status component for each rule
    current_organization.preload_vulnerability_alert_rule_overrides
    render "orgs/dependabot_rules/index", locals: {
      preset_rules: preset_rules,
      custom_rules: custom_rules.paginate(page: current_page, per_page: PAGE_SIZE),
      page_title:
    }
  end

  def new
    rule = VulnerabilityAlertRule.new(
      target: current_organization,
      conditions: {},
      enablement: VulnerabilityAlertRule::Enablement::EnabledByDefault,
      actions: {
        alert_actions: {
          auto_dismiss: "until_patch",
        },
        update_actions: {
          create_pr: false,
        },
      }
    )

    render "orgs/dependabot_rules/new", locals: locals_for_render.merge({
      rule: rule,
      rule_criteria: DependabotAlerts::RuleCriteriaHelper.new(rule).form_value,
      page_title:
    })
  end

  def create
    if has_maximum_rules?
      flash[:error] = "Maximum number (#{MAX_RULES_COUNT}) of rules have been created."
      redirect_to settings_org_dependabot_rules_path
    else
      rule = generate_rule_hash(params)
      rule = VulnerabilityAlertRule.create_rule(rule)

      if rule.errors.any?
        render "orgs/dependabot_rules/new", locals: locals_for_render.merge({
          rule: rule,
          rule_criteria: rule.query_string,
        })
      else
        flash[:notice] = "Rule saved. It may take a moment for this rule to be applied to matching alerts"
        redirect_to settings_org_dependabot_rules_path
      end
    end
  end

  def edit
    render "orgs/dependabot_rules/edit", locals: locals_for_render.merge(
      rule: @rule,
      rule_criteria: DependabotAlerts::RuleCriteriaHelper.new(@rule).form_value,
      page_title:
    )
  end

  def update
    if @rule.update_rule generate_rule_hash(params)
      flash[:notice] = "Rule saved."
      redirect_to settings_org_dependabot_rules_path
    else
      render "orgs/dependabot_rules/edit", locals: locals_for_render.merge({
        rule: @rule,
        rule_criteria: @rule.query_string,
        page_title:
      })
    end
  end

  def destroy
    if @rule.soft_delete_rule
      flash[:notice] = "Rule was successfully deleted."
    else
      flash[:error] = "Unable to delete rule."
    end
    redirect_to settings_org_dependabot_rules_path
  end

  def edit_global_rule # rubocop:todo GitHub/UseRestfulActions
    render "orgs/dependabot_rules/edit_global_rule", locals: { rule: @rule, page_title: }
  end

  def update_global_rule # rubocop:todo GitHub/UseRestfulActions
    # rule_behavior options that can be passed here are:
    # "enabled" -> enabled_by_default
    # "disabled" -> force_disabled
    # "enforced" -> force_enabled
    global_rule_id = VulnerabilityAlertRule.default_auto_dismissal_rule_id
    override = VulnerabilityAlertRuleOverride.find_or_initialize_by(
      rule_id: global_rule_id,
      target: current_organization,
    )

    case params[:rule_behavior]
    when VulnerabilityAlertRule::Enablement::EnabledByDefault.name
      override.enablement = VulnerabilityAlertRule::Enablement::EnabledByDefault
    when VulnerabilityAlertRule::Enablement::ForceEnabled.name
      override.enablement = VulnerabilityAlertRule::Enablement::ForceEnabled
    when VulnerabilityAlertRule::Enablement::ForceDisabled.name
      override.enablement = VulnerabilityAlertRule::Enablement::ForceDisabled
    end

    success = override.changed? ? override.save : false
    if success
      ReprocessOrganizationAlertRulesJob.perform_later(
        organization_id: current_organization.id,
        rule_id: T.must(global_rule_id),
        rule_target_type: "global",
        action: (override.disabled? ? :disabled : :enabled),
      )

      flash[:notice] = "Rule saved."
      redirect_to settings_org_dependabot_rules_path
    else
      flash[:error] = "Rule could not be saved."
      redirect_to settings_org_edit_global_dependabot_rule_path
    end
  end

  private

  memoize def page_title
    "Global settings"
  end

  def check_dependabot_org_rules_feature_enabled
    dependabot_rules_enabled = current_organization.present? && GitHub.dependabot_rules_enabled?

    render_404 unless dependabot_rules_enabled
  end

  def find_rule_with_authorization
    # Ensure the ID being passed in is a rule that belongs to the current organization.
    # We should not allow modifying repo or global rules here!
    @rule = VulnerabilityAlertRule.find_by!(
      target: current_organization,
      id: params.require(:id)
    )
  end

  def find_global_rule
    # Ensure the ID being passed in is a global rule type.
    # We should not allow modifying repo or custom rules here!
    @rule = VulnerabilityAlertRule.find_by!(
      target_type: "global",
      id: params.require(:id)
    )
    @rule.readonly!
    org_rule_override = VulnerabilityAlertRuleOverride.find_by(rule: @rule, target: current_organization)
    # enforcement of the global rule is done through overrides
    # update the rule before it is sent to the view so that
    # the view can show the correct state of the global rule
    if org_rule_override&.enforced_for_all?
      @rule.enablement_behavior = org_rule_override.enabled ? "force_enabled" : "force_disabled"
    end
  end

  memoize def organization_rules
    OrganizationVulnerabilityAlertRules.new(organization: current_organization)
  end

  memoize def preset_rules
    organization_rules.preset_rules
  end

  memoize def custom_rules
    organization_rules.custom_rules
  end

  def locals_for_render
    {
      dependabot_alert_cwe_suggestions: suggestions_for_cwes,
      dependabot_alert_scope_suggestions: suggestions_for_scopes,
      dependabot_alert_severity_suggestions: suggestions_for_severities,
      dependabot_alert_package_suggestions_path: security_center_alerts_dependabot_filter_input_suggestions_path(org: current_organization, suggestion: "package"),
      dependabot_alert_manifest_suggestions_path: nil,
      dependabot_alert_ecosystem_suggestions_path: security_center_alerts_dependabot_filter_input_suggestions_path(org: current_organization, suggestion: "ecosystem"),
      dependabot_alert_cve_id_suggestions_path: security_center_alerts_dependabot_filter_input_suggestions_path(org: current_organization, suggestion: "cve_id"),
      dependabot_alert_ghsa_id_suggestions_path: security_center_alerts_dependabot_filter_input_suggestions_path(org: current_organization, suggestion: "ghsa_id"),
      dependabot_alert_epss_suggestions_path: security_center_alerts_dependabot_filter_input_suggestions_path(org: current_organization, suggestion: "epss"),
    }
  end

  def generate_rule_hash(params)
    # This method is shared with Repo Rules and is defined in the DependabotAlerts::RulesControllerHelper,
    # here we override it and then call the actual method with the target params for org-level rules:
    super(target: current_organization, params:)
  end

  def has_maximum_rules?
    rule_count >= MAX_RULES_COUNT
  end

  memoize def rule_count
    VulnerabilityAlertRule.active.for_organization(current_organization).count
  end

  def rate_limit_key
    "dependabot-rule-updates:#{current_organization.id}"
  end

  def flash_rate_limit_error
    flash[:error] = "You have exceeded our rule change rate limit. Please wait an hour before you try again."
    redirect_to settings_org_dependabot_rules_path
  end
end
