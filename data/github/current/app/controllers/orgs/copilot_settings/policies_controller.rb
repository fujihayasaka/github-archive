# typed: strict
# frozen_string_literal: true

class Orgs::CopilotSettings::PoliciesController < Orgs::Controller
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency


  before_action :dotcom_required
  before_action :org_admins_only
  before_action :check_not_legacy_plan
  before_action :check_copilot_available
  before_action :check_if_billable
  before_action :parse_json_params, only: [:update, :create_or_update_mcp_registry_url]

  javascript_bundle :settings
  javascript_bundle :copilot

  allow_verified_fetch only: [:update, :create_or_update_mcp_registry_url]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    only: [:index]

  sig { returns(String) }
  def self.react_bundle_name
    "copilot-for-business"
  end

  sig { void }
  def index
    # Check org or its enterprise for the feature flag:
    add_client_feature_flag(%i(
      copilot_extension_access
      copilot_private_telemetry_access
      copilot_desktop
      copilot_desktop_no_preview_badge
      billing_platform_overages_policies_enabled
      copilot_insights
      copilot_byok
    ), entity: current_organization) do |feature_name, organization|
      organization.feature_flag_enabled?(feature_name, default: false) ||
        organization.business&.feature_flag_enabled?(feature_name, default: false)
    end

    # Check just the org's enterprise for the feature flag:
    add_client_feature_flag([:copilot_dotcom_chat, :copilot_for_enterprise], entity: current_organization) do |feature_name, organization|
      organization.business&.feature_flag_enabled?(feature_name, default: false)
    end

    # Check the org, its enterprise, or the viewer for the feature flag:
    add_client_feature_flag([:copilot_chat_dotcom_ga], entity: current_organization) do |feature_name, organization|
      organization.business&.feature_flag_enabled?(feature_name, default: false) || feature_enabled_globally_or_for_current_user_or_entity?(feature_name, organization)
    end

    add_client_feature_flag([:copilot_workbench])

    # /organizations/:org/settings/copilot/policies
    if FeatureFlag.vexi.enabled?(:cfb_package_data_router, current_user, default: false)
      respond_with_react(
        payload: Copilot::Organizations::Policies::Payload.new(organization: copilot_organization, user: current_user),
        title: "GitHub Copilot",
        layout: "layouts/settings/copilot_org_react",
        page_data: { selected_link: :organization_copilot_settings_policies },
      )
    else
      render_react_app(
        payload: Copilot::Organizations::Policies::Payload.new(organization: copilot_organization, user: current_user).call,
        title: "GitHub Copilot",
        layout: "layouts/settings/copilot_org_react",
        disable_ssr: true,
        page_data: { selected_link: :organization_copilot_settings_policies }
      )
    end
  end

  sig { void }
  def models # rubocop:todo GitHub/UseRestfulActions
    # /organizations/:organization_id/settings/copilot/models

    add_client_feature_flag([:copilot_byok], entity: current_organization) do |feature_name, organization|
      organization.feature_flag_enabled?(feature_name, default: false) || organization.business&.feature_flag_enabled?(feature_name, default: false)
    end

    if FeatureFlag.vexi.enabled?(:cfb_package_data_router, current_user, default: false)
      respond_with_react(
        payload: Copilot::Organizations::Policies::ModelsPayload.new(organization: copilot_organization, user: current_user),
        title: "GitHub Copilot",
        layout: "layouts/settings/copilot_org_react",
        page_data: { selected_link: :organization_copilot_settings_models },
      )
    else
      render_react_app(
      payload: Copilot::Organizations::Policies::ModelsPayload.new(organization: copilot_organization, user: current_user).call,
      title: "GitHub Copilot",
      layout: "layouts/settings/copilot_org_react",
      disable_ssr: true,
      page_data: { selected_link: :organization_copilot_settings_models }
    )
    end
  end

  sig { void }
  def update
    unless valid_param_options?
      respond_to do |format|
        format.html do
          if params[:return_to]&.start_with?("/github-copilot/business_signup")
            flash[:error] = "Select an option below to continue"
            return redirect_to copilot_business_signup_organization_policy_path(org: copilot_organization)
          else
            return render "orgs/copilot_settings/policies/index", locals: {
              copilot_organization: copilot_organization,
              error: true,
            }
          end
        end
        format.json { return render json: { message: "Invalid copilot policies values" }, status: :unprocessable_entity }
      end
    end

    old_settings = copilot_organization.copilot_organization_settings

    update_settings

    new_settings = copilot_organization.copilot_organization_settings

    unless old_settings == new_settings
      Copilot::Instrumenter.instrument_organization_settings_changed(
        copilot_organization.organization_object,
        current_user,
        old_settings: old_settings,
        new_settings: new_settings,
      )
    end

    respond_to do |format|
      format.html do
        if params[:return_to]
          safe_redirect_to(params[:return_to])
        else
          redirect_to settings_org_copilot_policies_path(copilot_organization)
        end
      end
      format.json { render json: { success: true } }
    end
  end

  sig { void }
  def create_or_update_mcp_registry_url # rubocop:todo GitHub/UseRestfulActions
    registry = if params[:id].present?
      GitHub.logger.info("Updating MCP Registry URL for organization", "gh.org.id" => current_organization.id, "gh.registry_url.id" => params[:id])
      Copilot::McpAllowlist.for_organization(current_organization).find(params[:id])
    else
      GitHub.logger.info("Creating MCP Registry URL for organization", "gh.org.id" => current_organization.id)
      Copilot::McpAllowlist.new(entity: current_organization, entity_type: "Organization")
    end

    registry.registry_url = params[:registry_url]
    registry.registry_access = params[:registry_access] if params[:registry_access].present?
    registry.updated_by = current_user

    if registry.save
      success_message = "MCP Registry URL #{params[:id].present? ? 'updated' : 'created'} successfully"
      render json: { success: true, message: success_message }, status: :ok
    else
      error_message = "Failed to #{params[:id].present? ? 'update' : 'create'} MCP Registry. #{registry.errors.full_messages.join(', ')}"
      GitHub.logger.info("Failed to save MCP Registry URL for organization",
        "gh.org.id" => current_organization.id,
        "gh.registry_url.id" => registry.id,
        "gh.errors" => error_message
      )
      render json: { success: false, message: error_message }, status: :unprocessable_entity
    end
  end

  private

  sig { void }
  def update_settings
    # overages will be updated like this regardless of if the new system is in use or not
    case params[:copilot_overages]
    when "enabled"
      copilot_organization.overages_enabled!
    when "disabled"
      copilot_organization.overages_disabled!
    end

    if copilot_organization.feature_flag_enabled?(:copilot_org_settings_refactor, default: false)
      update_settings_candidate
    else
      update_settings_control
    end
  end

  sig { void }
  def update_settings_control
    case params[:copilot_public_code_suggestions]
    when "allowed"
      copilot_organization.allow_public_code_suggestions!
    when "blocked"
      copilot_organization.block_public_code_suggestions!
    end

    case params[:copilot_editor_chat_enabled]
    when "enabled"
      # this will send an email(s)
      copilot_organization.enable_chat!
    when "disabled"
      # this will send an email(s)
      copilot_organization.disable_chat!
    end

    case params[:copilot_mobile_chat]
    when "enabled"
      # this will send an email(s)
      copilot_organization.mobile_chat_enabled!
    when "disabled"
      # this will send an email(s)
      copilot_organization.mobile_chat_disabled!
    end

    case params[:copilot_for_dotcom]
    when "enabled"
      # this will send an email(s)
      copilot_organization.copilot_for_dotcom_enabled!
    when "disabled"
      # this will send an email(s)
      copilot_organization.copilot_for_dotcom_disabled!
    end

    case params[:bing_github_chat]
    when "enabled"
      copilot_organization.bing_github_chat_enabled!
    when "disabled"
      copilot_organization.bing_github_chat_disabled!
    end

    case params[:copilot_user_feedback_opt_in]
    when "enabled"
      copilot_organization.enable_user_feedback!
    when "disabled"
      copilot_organization.disable_user_feedback!
    end

    case params[:cli]
    when "enabled"
      # this will send an email(s)
      copilot_organization.cli_enabled!
    when "disabled"
      # this will send an email(s)
      copilot_organization.cli_disabled!
    end

    if copilot_organization.feature_flag_enabled?(:copilot_desktop, default: false)
      case params[:desktop]
      when "enabled"
        # this will send an email(s)
        copilot_organization.desktop_enabled!
      when "disabled"
        # this will send an email(s)
        copilot_organization.desktop_disabled!
      end
    end

    case params[:copilot_extensions]
    when "enabled"
      copilot_organization.copilot_extensions_enabled!
    when "disabled"
      copilot_organization.copilot_extensions_disabled!
    end

    case params[:copilot_editor_preview_features]
    when "enabled"
      copilot_organization.editor_preview_features_enabled!
    when "disabled"
      copilot_organization.editor_preview_features_disabled!
    end

    case params[:copilot_agent_mode]
    when "enabled"
      copilot_organization.agent_mode_enabled!
    when "disabled"
      copilot_organization.agent_mode_disabled!
    end

    case params[:copilot_mcp]
    when "enabled"
      copilot_organization.mcp_enabled!
    when "disabled"
      copilot_organization.mcp_disabled!
    end

    case params[:copilot_a_chat]
    when "enabled"
      copilot_organization.a_chat_enabled!
    when "disabled"
      copilot_organization.a_chat_disabled!
    end

    case params[:copilot_a_f]
    when "enabled"
      copilot_organization.a_f_enabled!
    when "disabled"
      copilot_organization.a_f_disabled!
    end

    case params[:copilot_afos]
    when "enabled"
      copilot_organization.afos_enabled!
    when "disabled"
      copilot_organization.afos_disabled!
    end

    case params[:copilot_al]
    when "enabled"
      copilot_organization.al_enabled!
    when "disabled"
      copilot_organization.al_disabled!
    end

    case params[:copilot_g_chat]
    when "enabled"
      copilot_organization.g_chat_enabled!
    when "disabled"
      copilot_organization.g_chat_disabled!
    end

    case params[:copilot_g_tf]
    when "enabled"
      copilot_organization.g_tf_enabled!
    when "disabled"
      copilot_organization.g_tf_disabled!
    end

    case params[:copilot_gtff]
    when "enabled"
      copilot_organization.gtff_enabled!
    when "disabled"
      copilot_organization.gtff_disabled!
    end

    case params[:copilot_o1]
    when "enabled"
      copilot_organization.o1_enabled!
    when "disabled"
      copilot_organization.o1_disabled!
    end

    case params[:copilot_o3]
    when "enabled"
      copilot_organization.o3_enabled!
    when "disabled"
      copilot_organization.o3_disabled!
    end

    case params[:copilot_o_ff]
    when "enabled"
      copilot_organization.o_ff_enabled!
    when "disabled"
      copilot_organization.o_ff_disabled!
    end

    case params[:copilot_o_fm]
    when "enabled"
      copilot_organization.o_fm_enabled!
    when "disabled"
      copilot_organization.o_fm_disabled!
    end

    case params[:copilot_ofct]
    when "enabled"
      copilot_organization.ofct_enabled!
    when "disabled"
      copilot_organization.ofct_disabled!
    end

    case params[:copilot_o_f]
    when "enabled"
      copilot_organization.o_f_enabled!
    when "disabled"
      copilot_organization.o_f_disabled!
    end

    case params[:copilot_o_t]
    when "enabled"
      copilot_organization.o_t_enabled!
    when "disabled"
      copilot_organization.o_t_disabled!
    end

    case params[:copilot_obmb]
    when "enabled"
      copilot_organization.obmb_enabled!
    when "disabled"
      copilot_organization.obmb_disabled!
    end

    case params[:copilot_obmw]
    when "enabled"
      copilot_organization.obmw_enabled!
    when "disabled"
      copilot_organization.obmw_disabled!
    end

    case params[:copilot_grok_code]
    when "enabled"
      copilot_organization.grok_code_enabled!
    when "disabled"
      copilot_organization.grok_code_disabled!
    end


    case params[:copilot_aofo]
    when "enabled"
      copilot_organization.aofo_enabled!
    when "disabled"
      copilot_organization.aofo_disabled!
    end

    case params[:copilot_ofo]
    when "enabled"
      copilot_organization.ofo_enabled!
    when "disabled"
      copilot_organization.ofo_disabled!
    end

    case params[:private_telemetry]
    when "enabled"
      copilot_organization.private_telemetry_enabled!
    when "disabled"
      copilot_organization.private_telemetry_disabled!
    end

    case params[:copilot_beta_features_opt_in]
    when "enabled"
      copilot_organization.beta_features_github_chat_enabled!
    when "disabled"
      copilot_organization.beta_features_github_chat_disabled!
    end

    case params[:copilot_usage_metrics_policy]
    when "enabled"
      copilot_organization.telemetry_aggregation_enabled!
    when "disabled"
      copilot_organization.telemetry_aggregation_disabled!
    end

    case params[:copilot_swe_agent]
    when "enabled"
      # this will send an email(s)
      copilot_organization.swe_agent_enabled!
    when "disabled"
      # this will send an email(s)
      copilot_organization.swe_agent_disabled!
    end

    case params[:copilot_spark]
    when "enabled"
      # this will send an email(s)
      copilot_organization.spark_enabled!
    when "disabled"
      # this will send an email(s)
      copilot_organization.spark_disabled!
    end

    case params[:copilot_insights]
    when "enabled"
      copilot_organization.insights_enabled!
    when "disabled"
      copilot_organization.insights_disabled!
    end

    case params[:copilot_code_review]
    when "enabled"
      # this will send an email(s)
      copilot_organization.code_review_enabled!
    when "disabled"
      # this will send an email(s)
      copilot_organization.code_review_disabled!
    end

    case params[:copilot_code_review_beta_features]
    when "enabled"
      copilot_organization.code_review_beta_features_enabled!
    when "disabled"
      copilot_organization.code_review_beta_features_disabled!
    end
  end

  sig { void }
  def update_settings_candidate
    params.each do |key, value|
      policy_class = Copilot::Policies::ORG_MUTABLE[key]
      if policy_class
        policy_class.update_org(copilot_organization, value)
      end
    end
  end


  sig { void }
  def check_not_legacy_plan
    render_404 if current_organization.plan.legacy?
  end

  sig { void }
  def check_copilot_available
    render_404 unless copilot_organization.has_copilot_for_business? || (copilot_organization.business_trial && T.must(copilot_organization.business_trial).has_trial?)
  end

  sig { void }
  def check_if_billable
    redirect_to settings_org_copilot_seat_management_path(current_organization) if !copilot_organization.copilot_billable? && !copilot_organization.business_trial.present?
  end

  sig { returns(Copilot::Organization) }
  memoize def copilot_organization
    T.must_because(current_copilot_organization) { "#org_admins_only ensures non-nil" }
  end

  sig { returns(T::Boolean) }
  def valid_param_options?
    feature_options = %w(enabled disabled)
    feature_names = %i[
      bing_github_chat
      cli
      copilot_a_chat
      copilot_a_f
      copilot_afos
      copilot_aofo
      copilot_al
      copilot_editor_preview_features
      copilot_agent_mode
      copilot_g_chat
      copilot_g_tf
      copilot_gtff
      copilot_o1
      copilot_o3
      copilot_o_f
      copilot_o_ff
      copilot_o_fm
      copilot_ofct
      copilot_o_t
      copilot_obmb
      copilot_obmw
      copilot_ofo
      copilot_grok_code
      copilot_beta_features_opt_in
      copilot_editor_chat_enabled
      copilot_extensions
      copilot_for_dotcom
      copilot_mobile_chat
      copilot_usage_metrics_policy
      copilot_user_feedback_opt_in
      private_telemetry
      desktop
      copilot_overages
      copilot_swe_agent
      copilot_mcp
      copilot_spark
      copilot_insights
      copilot_code_review
      copilot_code_review_beta_features
    ]

    alternate_feature_options = %w(allowed blocked)
    alternate_feature_names = %i[
      copilot_public_code_suggestions
    ]

    if copilot_organization.feature_flag_enabled?(:copilot_org_settings_refactor, default: false)
      feature_names = [
        *Copilot::Policies::ORG_MUTABLE.keys,
        :copilot_o_f,
        :copilot_overages
      ]
      alternate_feature_names = [Copilot::Policies::Snippy.config_name.to_sym]
    end

    feature_names.any? { |feature_name| feature_options.include?(params[feature_name]) } ||
    alternate_feature_names.any? { |alt_feature_name| alternate_feature_options.include?(params[alt_feature_name]) }
  end
end
