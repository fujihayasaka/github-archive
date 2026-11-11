# typed: strict
# frozen_string_literal: true

class Orgs::CopilotSettings::PoliciesController < Orgs::Controller
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency


  before_action :dotcom_required
  before_action :org_admins_only
  before_action :check_not_legacy_plan
  before_action :check_copilot_available
  before_action :check_models_available, only: :models
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
    only: [:index, :models]

  sig { returns(String) }
  def self.react_bundle_name
    "copilot-for-business"
  end

  sig { void }
  def index
    # Check org or its enterprise for the feature flag:
    add_client_feature_flag(%i(
      copilot_extension_access
      hide_copilot_extensions_policy
      copilot_private_telemetry_access
      copilot_byok
    ), entity: current_organization) do |feature_name, organization|
      organization.feature_flag_enabled?(feature_name, default: false) ||
        organization.business&.feature_flag_enabled?(feature_name, default: false)
    end

    # Check just the org's enterprise for the feature flag:
    add_client_feature_flag([:copilot_dotcom_chat], entity: current_organization) do |feature_name, organization|
      organization.business&.feature_flag_enabled?(feature_name, default: false)
    end

    # Check the org, its enterprise, or the viewer for the feature flag:
    add_client_feature_flag([:copilot_chat_dotcom_ga], entity: current_organization) do |feature_name, organization|
      organization.business&.feature_flag_enabled?(feature_name, default: false) || feature_enabled_globally_or_for_current_user_or_entity?(feature_name, organization)
    end

    add_client_feature_flag([:copilot_workbench])

    additional_params = {
      member_feature_request_completed: session.delete(:member_request_completed),
      member_feature_request_feature_name: session.delete(:member_request_feature_name)
    }

    # /organizations/:org/settings/copilot/policies
    if FeatureFlag.vexi.enabled?(:cfb_package_data_router, current_user, default: false)
      respond_with_react(
        payload: Copilot::Organizations::Policies::Payload.new(organization: copilot_organization, user: current_user, additional_params: additional_params),
        title: "GitHub Copilot",
        layout: "layouts/settings/copilot_org_react",
        page_data: { selected_link: :organization_copilot_settings_policies },
      )
    else
      render_react_app(
        payload: Copilot::Organizations::Policies::Payload.new(organization: copilot_organization, user: current_user, additional_params: additional_params).call,
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

    add_client_feature_flag(%i(copilot_byok),
      entity: current_organization,
    ) do |feature_name, organization|
      organization.feature_flag_enabled?(feature_name, default: false) ||
        organization.business&.feature_flag_enabled?(feature_name, default: false)
    end

    if FeatureFlag.vexi.enabled?(:cfb_package_data_router, current_user, default: false)
      respond_with_react(
        payload: Copilot::Organizations::Policies::ModelsPayload.new(organization: copilot_organization),
        title: "GitHub Copilot",
        layout: "layouts/settings/copilot_org_react",
        page_data: { selected_link: :organization_copilot_settings_models },
      )
    else
      render_react_app(
      payload: Copilot::Organizations::Policies::ModelsPayload.new(organization: copilot_organization).call,
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
            redirect_to settings_org_copilot_policies_path(copilot_organization)
            return
          end
        end
        format.json { return render json: { message: "Invalid copilot policies values" }, status: :unprocessable_entity }
      end
    end

    GitHub.logger.info("Updating Copilot policies for organization", "gh.org.id" => current_organization.id, "gh.user.id" => current_user.id, "gh.params" => policy_params)

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

      GitHub.logger.info(
        "Organization settings changed",
        "gh.organization.id" => current_organization.id,
        "gh.user.id" => current_user.id,
        "gh.copilot.organization_settings.previous_settings" => old_settings,
        "gh.copilot.organization_settings.new_settings" => new_settings,
      )
    end

    respond_to do |format|
      format.html do
        if params[:return_to]
          safe_redirect_to(params[:return_to])
        elsif params[:is_member_request]
          session[:member_request_completed] = params[:is_member_request].to_s
          session[:member_request_feature_name] = params[:feature_name].to_s
          redirect_to settings_org_copilot_policies_path(copilot_organization)
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
      Copilot::McpRegistry.for_organization(current_organization).find(params[:id])
    else
      GitHub.logger.info("Creating MCP Registry URL for organization", "gh.org.id" => current_organization.id)
      Copilot::McpRegistry.new(entity: current_organization, entity_type: "Organization")
    end

    old_settings = copilot_organization.copilot_organization_settings

    registry.registry_url = params[:registry_url]
    registry.registry_access = params[:registry_access] if params[:registry_access].present?
    registry.updated_by = current_user

    if registry.save
      new_settings = copilot_organization.copilot_organization_settings

      unless old_settings == new_settings
        Copilot::Instrumenter.instrument_organization_settings_changed(
          copilot_organization.organization_object,
          current_user,
          old_settings: old_settings,
          new_settings: new_settings,
        )
      end

      GitHub.logger.info(
        "Organization MCP registry settings changed",
        "gh.organization.id" => current_organization.id,
        "gh.user.id" => current_user.id,
        "gh.copilot.organization.previous_settings" => old_settings,
        "gh.copilot.organization.new_settings" => new_settings
      )

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

    # dynamically update supported policies
    params.each do |key, value|
      policy_class = Copilot::Policies::ORG_MUTABLE[key]
      if policy_class
        policy_class.update_org(copilot_organization, value)
      elsif org_model_keys.include?(key)
        old_value = copilot_organization.model_policy(key)
        next if old_value == value || %w(enabled disabled).exclude?(value)

        if value == "enabled"
          copilot_organization.model_enabled!(key)
        elsif value == "disabled"
          copilot_organization.model_disabled!(key)
        end

        Copilot::Instrumenter.instrument_organization_settings_changed(
          copilot_organization.organization_object,
          current_user,
          old_settings: { key => old_value },
          new_settings: { key => value },
        )
      end
    end
  end


  sig { void }
  def check_not_legacy_plan
    render_404 if current_organization.plan.legacy?
  end

  sig { void }
  def check_copilot_available
    render_404 unless copilot_organization.has_copilot_for_business? || (copilot_organization.business_trial && T.must(copilot_organization.business_trial).has_trial?) || copilot_organization.can_view_settings_page_with_copilot_disabled?
  end

  sig { void }
  def check_models_available
    # allow access to the models page for orgs with direct org billing
    render_404 unless copilot_organization.has_copilot_for_business? || (copilot_organization.business_trial && T.must(copilot_organization.business_trial).has_trial?) || copilot_organization.has_copilot_direct_org_billing_enabled?
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
    feature_names = [
      *Copilot::Policies::ORG_MUTABLE.keys,
      :copilot_o_f,
      :copilot_overages,
      *org_model_keys
    ]

    alternate_feature_options = %w(allowed blocked)
    alternate_feature_names = [Copilot::Policies::Snippy.config_name.to_sym]

    feature_names.any? { |feature_name| feature_options.include?(params[feature_name]) } ||
    alternate_feature_names.any? { |alt_feature_name| alternate_feature_options.include?(params[alt_feature_name]) }
  end

  sig { returns(T::Hash[Symbol, T.any(Symbol, String)]) }
  def policy_params
    possible_features = [
      *Copilot::Policies::ORG_MUTABLE.keys,
      :copilot_o_f,
      :copilot_overages,
      *org_model_keys,
    ]
    possible_features.each_with_object({}) do |feature_name, hash|
      if params[feature_name].present?
        hash[feature_name] = params[feature_name]
      end
    end
  end

  sig { returns(T::Array[String]) }
  memoize def org_model_keys
    return [] unless copilot_organization.feature_flag_enabled?(:copilot_model_registry_ui, default: false)
    Copilot::ModelsRegistryCache.for_organization(copilot_organization).map(&:model_key)
  end
end
