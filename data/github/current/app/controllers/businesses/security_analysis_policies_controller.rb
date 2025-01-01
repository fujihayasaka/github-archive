# typed: true
# frozen_string_literal: true

class Businesses::SecurityAnalysisPoliciesController < Businesses::BusinessController
  include SecretScanningCustomPatternsHelper
  include SecretScanning::Features::FeatureFlagHelper

  before_action :view_permission_required, only: [:index, :index_security_features]
  before_action :business_owner_required, only: [:update_dependency_insights_view_permissions]
  before_action :modify_code_security_policies_permission_required, except: [:index, :index_security_features, :update_dependency_insights_view_permissions]
  before_action :business_not_downgraded_to_free_plan_required
  before_action :security_features_required
  before_action :advanced_security_required, only: [
    :update_ghas_availability,
    :update_org_ghas_availability,
    :update_ghas_enablement,
    :update_org_ghas_sku_availability,
  ]
  before_action :secret_scanning_required, only: [
    :index_security_features,
    :update_secret_scanning_settings,
    :update_generic_secrets_settings
  ]

  before_action :dependency_insights_required, only: [:update_dependency_insights_view_permissions]
  before_action :dotcom_required, only: [:update_dependency_insights_view_permissions]
  before_action :business_full_plan_required

  javascript_bundle :settings
  javascript_bundle :scanning, only: :index

  track_latency_slo "p99-ui-request", 2000
  track_latency_slo "p50-ui-request", 500
  track_availability_slo "ui-request"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    only: [:index, :index_security_features]

  depends_on_clusters ApplicationRecord::Billing, optional: true,
    only: [:index, :index_security_features]

  depends_on_clusters ApplicationRecord::Mysql5,
    only: [:index, :index_security_features],
    optional: true

  def index
    render "businesses/settings/security_analysis_policies", locals: {
      business: this_business,
      current_user:,
      query: params["q"],
      current_page: current_page,
      show_dependabot_alerts: show_dependabot_alerts?,
      show_advanced_security: show_advanced_security?,
      show_secret_scanning: show_secret_scanning?,
      show_generic_secrets: show_generic_secrets?,
      show_code_scanning_autofix: show_code_scanning_autofix?,
      show_code_scanning_autofix_third_party_tools: show_code_scanning_autofix_third_party_tools?,
      is_advanced_security_available_on_selected_org: is_advanced_security_available_on_selected_org?,
    }
  end

  def index_security_features # rubocop:todo GitHub/UseRestfulActions
    render "businesses/settings/security_analysis_security_features", locals: {
      business: this_business,
      cursor: SecretScanningCustomPatternsHelper::get_custom_patterns_cursor(params),
      custom_patterns_query: params["query"]
    }
  end

  def update_ghas_availability # rubocop:todo GitHub/UseRestfulActions
    ghas_availability_setting = params[:ghas_availability]

    case ghas_availability_setting
    when "all_orgs"
      this_business.allow_members_to_enable_advanced_security(actor: current_user)
      flash[:notice] = "Policy changes saved."
    when "selected_orgs"
      this_business.allow_selected_members_to_enable_advanced_security(actor: current_user)
      flash[:notice] = "Policy changes saved."
    when "not_available"
      this_business.disallow_members_to_enable_advanced_security(actor: current_user)
      flash[:notice] = "Policy changes saved."
    else
      flash[:error] = "You provided an invalid input value. Please try again."
    end

    redirect_to :back
  end

  def update_org_ghas_availability # rubocop:todo GitHub/UseRestfulActions
    availability_setting = params[:org_ghas_availability]
    org_ids = params[:org_ids]

    organizations = this_business.organizations.where(id: org_ids)

    if organizations.present?
      case availability_setting
      when "available"
        organizations.each { |org| org.set_advanced_security_entity_policy(policy: Configurable::AdvancedSecurityAccessPolicy::ENTITY_ALLOWED_ALL, actor: current_user) }
        flash[:notice] = "Policy changes saved."
      when "not_available"
        organizations.each { |org| org.set_advanced_security_entity_policy(policy: Configurable::AdvancedSecurityAccessPolicy::ENTITY_ALLOWED_NONE, actor: current_user) }
        flash[:notice] = "Policy changes saved."
      else
        flash[:error] = "You provided an invalid input value. Please try again."
      end
    else
      flash[:error] = "Organization not found. Please select an organization and retry."
    end

    redirect_to :back
  end

  def update_org_ghas_sku_availability # rubocop:todo GitHub/UseRestfulActions
    availability_setting = params[:org_ghas_sku_availability]
    org_ids = params[:org_ids]

    organizations = this_business.organizations.where(id: org_ids)
    if !organizations.present?
      flash[:error] = "Organization not found. Please select an organization and retry."
      redirect_to :back
      return
    end

    if !Configurable::AdvancedSecurityAccessPolicy::ENTITY_ALLOWED_VALUES.include?(availability_setting)
      flash[:error] = "You provided an invalid input value. Please try again."
      redirect_to :back
      return
    end

    organizations.each { |org| org.set_advanced_security_entity_policy(policy: availability_setting, actor: current_user) }
    flash[:notice] = "Policy changes saved."

    redirect_to :back
  end

  def update_ghas_enablement # rubocop:todo GitHub/UseRestfulActions
    setting_for_repo_admins = params[:all_repo_admins]

    case setting_for_repo_admins
    when "allowed"
      this_business.allow_repo_admins_to_modify_advanced_security_enablement(actor: current_user)
      flash[:notice] = "Policy changes saved."
    when "not_allowed"
      this_business.disallow_repo_admins_to_modify_advanced_security_enablement(actor: current_user)
      flash[:notice] = "Policy changes saved."
    else
      flash[:error] = "You provided an invalid input value. Please try again."
    end

    redirect_to :back
  end

  def update_ghas_code_security_enablement # rubocop:todo GitHub/UseRestfulActions
    setting_for_repo_admins = params[:all_repo_admins]

    case setting_for_repo_admins
    when "allowed"
      this_business.allow_repo_admins_to_modify_code_security_enablement(actor: current_user)
      flash[:notice] = "Policy changes saved."
    when "not_allowed"
      this_business.disallow_repo_admins_to_modify_code_security_enablement(actor: current_user)
      flash[:notice] = "Policy changes saved."
    else
      flash[:error] = "You provided an invalid input value. Please try again."
    end

    redirect_to :back
  end

  def update_dependabot_alerts_enablement # rubocop:todo GitHub/UseRestfulActions
    setting_for_repo_admins = params[:all_orgs_repo_admins]

    case setting_for_repo_admins
    when "allowed"
      this_business.allow_repo_admins_to_modify_dependabot_alerts_enablement(actor: current_user)
      flash[:notice] = "Policy changes saved."
    when "not_allowed"
      this_business.disallow_repo_admins_to_modify_dependabot_alerts_enablement(actor: current_user)
      flash[:notice] = "Policy changes saved."
    else
      flash[:error] = "You provided an invalid input value. Please try again."
    end

    redirect_to :back
  end

  def update_secret_scanning_settings # rubocop:todo GitHub/UseRestfulActions
    setting_for_repo_admins = params[:all_repo_admins]

    case setting_for_repo_admins
    when "allowed"
      this_business.allow_repo_admins_to_modify_secret_scanning_settings(actor: current_user)
      flash[:notice] = "Policy changes saved."
    when "not_allowed"
      this_business.disallow_repo_admins_to_modify_secret_scanning_settings(actor: current_user)
      flash[:notice] = "Policy changes saved."
    else
      flash[:error] = "You provided an invalid input value. Please try again."
    end

    redirect_to :back
  end

  def update_generic_secrets_settings # rubocop:todo GitHub/UseRestfulActions
    setting_for_repo_admins = params[:all_orgs_repo_admins]

    case setting_for_repo_admins
    when "allowed"
      this_business.allow_repo_admins_to_modify_generic_secrets_settings(actor: current_user)
      flash[:notice] = "Policy changes saved."
    when "not_allowed"
      this_business.disallow_repo_admins_to_modify_generic_secrets_settings(actor: current_user)
      flash[:notice] = "Policy changes saved."
    else
      flash[:error] = "You provided an invalid input value. Please try again."
    end

    redirect_to :back
  end

  def update_dependency_insights_view_permissions # rubocop:todo GitHub/UseRestfulActions
    enabled = params[:members_can_view_dependency_insights]&.to_s
    validate_setting value: enabled

    case enabled
    when "enabled"
      this_business.allow_members_can_view_dependency_insights(actor: current_user, force: true)
      flash[:notice] = "Members can now view dependency insights."
    when "disabled"
      this_business.disallow_members_can_view_dependency_insights(actor: current_user, force: true)
      flash[:notice] = "Members can no longer view dependency insights."
    when "no_policy"
      this_business.clear_members_can_view_dependency_insights(actor: current_user)
      flash[:notice] = "Organization administrators can now change this setting for individual organizations."
    end

    redirect_to :back
  end

  private

  def view_permission_required
    business_authz = SecurityProduct::Permissions::BusinessAuthz.new(this_business, actor: current_user)
    render_404 unless business_authz.can_view_code_security_policies?
  end

  def show_dependabot_alerts?
    SecurityCenter::SecurityFeatures.dependabot_alerts_enabled_for_instance?
  end

  def show_advanced_security?
    this_business.advanced_security_purchased?
  end

  def show_secret_scanning?
    SecretScanning::Features::Business::TokenScanning.new(this_business).feature_available?
  end

  def show_generic_secrets?
    SecretScanning::Features::Business::GenericSecrets.new(this_business).feature_available?
  end

  def show_dependency_insights?
    !GitHub.single_business_environment?
  end

  def show_code_scanning_autofix?
    CodeScanning::AutofixCodeql.policy_available?(this_business)
  end

  def show_code_scanning_autofix_third_party_tools?
    CodeScanning::AutofixThirdPartyTools.policy_available?(this_business)
  end

  def is_advanced_security_available_on_selected_org?
    this_business.selected_members_can_enable_advanced_security?
  end

  def security_features_required
    render_404 unless show_dependabot_alerts? || show_advanced_security? || show_secret_scanning? || show_dependency_insights?
  end

  def advanced_security_required
    render_404 unless show_advanced_security?
  end

  def secret_scanning_required
    render_404 unless show_secret_scanning?
  end
end
