# typed: true
# frozen_string_literal: true
# rubocop:disable GitHub/RailsControllerRenderLiteral

class Repos::SecurityAndAnalysis::DependabotRulesController < AbstractRepositoryController
  include DependabotAlerts::RulesControllerHelper

  # Cluster dependency analysis will be enabled for these non-get requests:
  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = %W(
    Repos::SecurityAndAnalysis::DependabotRulesController#create
    Repos::SecurityAndAnalysis::DependabotRulesController#destroy
    Repos::SecurityAndAnalysis::DependabotRulesController#update
    Repos::SecurityAndAnalysis::DependabotRulesController#update_parent_rule
  )

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Notify,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes

  depends_on_clusters ApplicationRecord::Mysql2,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::NotificationsEntries,
    optional: true

  depends_on_clusters ApplicationRecord::Copilot,
    optional: true,
    only: [:index, :create, :new, :edit, :show, :update, :edit_parent_rule, :update_parent_rule, :destroy]

  before_action :login_required
  before_action :writable_repository_required
  before_action :check_feature_enablement
  before_action :check_custom_rules_writable, only: [:new, :create, :edit, :update, :destroy]
  before_action :manage_security_products_permission_required
  before_action :find_rule_with_authorization, only: [:edit, :update, :destroy]
  before_action :find_enforced_rule_with_authorization, only: [:show]
  before_action :find_parent_rule, only: [:edit_parent_rule, :update_parent_rule]

  rate_limit_requests \
    only: [:create, :destroy, :update, :update_parent_rule],
    key: :rate_limit_key,
    max: 100,
    ttl: 1.hour,
    at_limit: :flash_rate_limit_error

  layout "repository"
  javascript_bundle :settings
  stylesheet_bundle :settings

  PAGE_SIZE = 10

  def index
    # This avoids a n+1 query when rendering status component for each rule
    current_repository.preload_vulnerability_alert_rule_overrides
    render "repos/security_and_analysis/dependabot_rules/index", locals: {
      preset_rules: preset_rules,
      custom_repo_rules: custom_repo_rules,
      custom_org_rules: custom_org_rules.paginate(page: current_page, per_page: PAGE_SIZE),
      has_maximum_rules: has_maximum_rules?,
    }
  end

  def new
    rule = VulnerabilityAlertRule.new(
      target: current_repository,
      conditions: {},
      enablement: VulnerabilityAlertRule::Enablement::EnabledByDefault,
      actions: {
        alert_actions: {
          auto_dismiss: "until_patch",
        },
        update_actions: {
          create_pr: false,
        },
      })

    render "repos/security_and_analysis/dependabot_rules/new", locals: locals_for_render.merge({
      rule: rule,
      rule_criteria: DependabotAlerts::RuleCriteriaHelper.new(rule).form_value,
    })
  end

  def create
    if has_maximum_rules?
      flash[:error] = "Maximum number (10) of rules have been created."
      redirect_to dependabot_rules_path
    else
      rule = generate_rule_hash(params)
      rule = VulnerabilityAlertRule.create_rule(rule)

      if rule.errors.any?
        render "repos/security_and_analysis/dependabot_rules/new", locals: locals_for_render.merge({
          rule: rule,
          rule_criteria: rule.query_string,
        })
      else
        flash[:notice] = "Rule created."
        redirect_to dependabot_rules_path
      end
    end
  end

  def edit
    render "repos/security_and_analysis/dependabot_rules/edit", locals: locals_for_render.merge({
      rule: @rule,
      rule_criteria: DependabotAlerts::RuleCriteriaHelper.new(@rule).form_value
    })
  end

  def edit_parent_rule # rubocop:todo GitHub/UseRestfulActions
    render "repos/security_and_analysis/dependabot_rules/edit_parent_rule", locals: { rule: @rule }
  end

  def show
    if @rule.enablement_for_repository(current_repository).forced?
      render "repos/security_and_analysis/dependabot_rules/show", locals: {
        rule: @rule,
      }
    else
      redirect_to edit_dependabot_rule_path(@rule)
    end
  end

  def update
    if @rule.update_rule(generate_rule_hash(params))
      flash[:notice] = "Rule saved."
      redirect_to dependabot_rules_path
    else
      render "repos/security_and_analysis/dependabot_rules/edit", locals: locals_for_render.merge({
        rule: @rule,
        rule_criteria: @rule.query_string
      })
    end
  end

  def update_parent_rule # rubocop:todo GitHub/UseRestfulActions
    # Only organization owned repos would have an override:
    if owner.organization?
      org_override = VulnerabilityAlertRuleOverride.find_by(
        target: owner,
        rule: @rule,
      )
    end

    # You can't modify the parent rule enablement if:
    #   - The rule is force_enabled
    #   - The rule is force_disabled
    #   - The rule has an org override with enforcement set to "enforced_for_all"
    if @rule.forced? || org_override&.forced?
      flash[:error] = "Rule could not be saved."
      redirect_to dependabot_rules_path
      return
    end

    override = VulnerabilityAlertRuleOverride.find_or_initialize_by(
      rule: @rule,
      target: current_repository,
    )

    override.enabled = (params[:rule_behavior] == VulnerabilityAlertRule::Enablement::EnabledByDefault.name)

    # Determine if an override is necessary, so that we clean up unused records:
    rule_enablement = @rule.enablement
    delete_override =
      if rule_enablement.enabled_by_default_for_public?
        override.enabled? && current_repository.public?
      elsif rule_enablement.enabled?
        override.enabled?
      else
        !override.enabled?
      end

    success =
      if delete_override
        if override.persisted?
          # The override is not needed, delete it:
          override.destroy
        else
          # The override record doesn't exist and we don't need it, so we won't create it.
          # From a user's perspective, this is success:
          true
        end
      else
        override.save
      end

    if success
      if override.enabled?
        ReprocessAlertRulesJob.perform_later(repository_id: current_repository.id, enabled_rule_ids: override.rule_id)
      else
        ReprocessAlertRulesJob.perform_later(repository_id: current_repository.id, disabled_rule_ids: override.rule_id)
      end

      flash[:notice] = "Rule saved."
      redirect_to dependabot_rules_path
    else
      flash[:error] = "Rule could not be saved."
      redirect_to edit_parent_dependabot_rule_path
    end
  end

  def destroy
    if @rule.soft_delete_rule
      flash[:notice] = "Rule was successfully deleted."
    else
      flash[:error] = "Unable to delete rule."
    end
    redirect_to dependabot_rules_path
  end

  private

  def locals_for_render
    {
      dependabot_alert_cwe_suggestions: suggestions_for_cwes,
      dependabot_alert_scope_suggestions: suggestions_for_scopes,
      dependabot_alert_severity_suggestions: suggestions_for_severities,
      dependabot_alert_package_suggestions_path: repository_alerts_filter_input_suggestions_path(suggestion: "package") ,
      dependabot_alert_manifest_suggestions_path: repository_alerts_filter_input_suggestions_path(suggestion: "manifest"),
      dependabot_alert_ecosystem_suggestions_path: repository_alerts_filter_input_suggestions_path(suggestion: "ecosystem"),
      dependabot_alert_cve_id_suggestions_path: repository_alerts_filter_input_suggestions_path(suggestion: "cve_id"),
      dependabot_alert_ghsa_id_suggestions_path: repository_alerts_filter_input_suggestions_path(suggestion: "ghsa_id"),
    }
  end

  def generate_rule_hash(params)
    # This method is shared with Org Rules and is defined in the DependabotAlerts::RulesControllerHelper,
    # here we override it and then call the actual method with the target params for repo-level rules:
    super(target: current_repository, params:)
  end

  # Is this repository allowed to see ANY Dependabot Rules and manage enablement?
  # This is different than creating custom rules, which is checked below in check_custom_rules_writable
  #
  def check_feature_enablement
    dependabot_rules_enabled = current_repository.vulnerability_alerts_enabled? && GitHub.dependabot_rules_enabled?

    return render_404 unless dependabot_rules_enabled
  end

  # Is this repository allowed to create/update/destroy CUSTOM rules?
  #
  def check_custom_rules_writable
    return render_404 unless current_repository.dependabot_custom_rules_writable?
  end

  def find_rule_with_authorization
    # We want to be sure that the param being passed in is a rule that belongs to the current repo
    # We should not allow editing or deleting of global rules
    @rule = VulnerabilityAlertRule.for_repository(current_repository).find_by!(id: params.require(:rule_id))
  end

  def find_enforced_rule_with_authorization
    # We want to be sure that the param being passed in is a rule that belongs to the current repo's org
    # We do this because we want users to see org custom and global rules that apply to their repo
    @rule = VulnerabilityAlertRule.where(target_type: "global", id: params.require(:rule_id))
              .or(VulnerabilityAlertRule.for_organization(current_repository.owner).where(id: params.require(:rule_id)))
              .sole
  end

  memoize def rules
    RepositoryVulnerabilityAlertRules.new(repository: current_repository)
  end

  memoize def preset_rules
    rules.preset_rules
  end

  memoize def custom_repo_rules
    rules.custom_repo_rules
  end

  memoize def custom_org_rules
    rules.custom_org_rules
  end

  memoize def rule_count
    VulnerabilityAlertRule.active.for_repository(current_repository).count
  end

  def has_maximum_rules?
    rule_count >= 10
  end

  def find_parent_rule
    # Find a parent rule using the `rules` helper:
    parent_rule_id = params.require(:id).to_i
    @rule = rules.rules.find { |r| (r.global? || r.org_target?) && r.id == parent_rule_id }
    return render_404 unless @rule.present?
  end

  def rate_limit_key
    "dependabot-rule-updates:#{current_repository.owner_id}"
  end

  def flash_rate_limit_error
    flash[:error] = "You have exceeded our rule change rate limit. Please wait an hour before you try again."
    redirect_to dependabot_rules_path
  end
end
