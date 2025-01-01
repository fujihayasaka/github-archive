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
  before_action :parse_json_params, only: [:update]

  javascript_bundle :settings
  javascript_bundle :copilot

  allow_verified_fetch only: [:update]

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
    add_client_feature_flag([:copilot_extension_access], entity: current_organization) do |feature_name, organization|
      organization.feature_enabled?(feature_name) || organization.business&.feature_enabled?(feature_name)
    end

    add_client_feature_flag([:copilot_private_telemetry_access], entity: current_organization) do |feature_name, organization|
      organization.feature_enabled?(feature_name) || organization.business&.feature_enabled?(feature_name)
    end

    add_client_feature_flag([:copilot_dotcom_chat], entity: current_organization) do |feature_name, organization|
      organization.business&.feature_enabled?(feature_name)
    end

    add_client_feature_flag([:copilot_for_enterprise], entity: current_organization) do |feature_name, organization|
      organization.business&.feature_enabled?(feature_name)
    end

    add_client_feature_flag([:copilot_chat_dotcom_ga], entity: current_organization) do |feature_name, organization|
      organization.business&.feature_enabled?(feature_name) || feature_enabled_globally_or_for_current_user_or_entity?(feature_name, organization)
    end

    add_client_feature_flag([:copilot_desktop], entity: current_organization) do |feature_name, organization|
      organization.feature_enabled?(feature_name) || organization.business&.feature_enabled?(feature_name)
    end

    add_client_feature_flag([:copilot_overages], entity: current_organization) do |feature_name, organization|
      organization.feature_enabled?(feature_name) || organization.business&.feature_enabled?(feature_name)
    end

    # /organizations/:org/settings/copilot/policies
    render_react_app(
      payload: Copilot::Organizations::Policies::Payload.new(organization: copilot_organization, user: current_user).call,
      title: "GitHub Copilot",
      layout: "layouts/settings/copilot_org_react",
      disable_ssr: true,
      page_data: { selected_link: :organization_copilot_settings_policies }
    )
  end

  sig { void }
  def models # rubocop:todo GitHub/UseRestfulActions
    # /organizations/:org/settings/copilot/policies
    render_react_app(
      payload: Copilot::Organizations::Policies::Payload.new(organization: copilot_organization, user: current_user).call,
      title: "GitHub Copilot",
      layout: "layouts/settings/copilot_org_react",
      disable_ssr: true,
      page_data: { selected_link: :organization_copilot_settings_models }
    )
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
      copilot_organization.enable_mobile_chat!
    when "disabled"
      # this will send an email(s)
      copilot_organization.disable_mobile_chat!
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
      copilot_organization.bing_github_chat_enable!
    when "disabled"
      copilot_organization.bing_github_chat_disable!
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

    if copilot_organization.feature_enabled?(:copilot_desktop)
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

    case params[:copilot_g_chat]
    when "enabled"
      copilot_organization.g_chat_enabled!
    when "disabled"
      copilot_organization.g_chat_disabled!
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

    case params[:copilot_o_f]
    when "enabled"
      copilot_organization.o_f_enabled!
    when "disabled"
      copilot_organization.o_f_disabled!
    end

    case params[:private_telemetry]
    when "enabled"
      copilot_organization.private_telemetry_enabled!
    when "disabled"
      copilot_organization.private_telemetry_disabled!
    end

    case params[:copilot_beta_features_opt_in]
    when "enabled"
      copilot_organization.beta_features_github_chat_enable!
    when "disabled"
      copilot_organization.beta_features_github_chat_disable!
    end

    case params[:copilot_usage_metrics_policy]
    when "enabled"
      copilot_organization.telemetry_aggregation_enabled!
    when "disabled"
      copilot_organization.telemetry_aggregation_disabled!
    end

    case params[:copilot_overages]
    when "enabled"
      copilot_organization.overages_enabled!
    when "disabled"
      copilot_organization.overages_disabled!
    end

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

  private

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
      copilot_editor_preview_features
      copilot_g_chat
      copilot_o1
      copilot_o3
      copilot_o_f
      copilot_o_ff
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
    ]

    alternate_feature_options = %w(allowed blocked)
    alternate_feature_names = %i[
      copilot_public_code_suggestions
    ]

    feature_names.any? { |feature_name| feature_options.include?(params[feature_name]) } ||
    alternate_feature_names.any? { |alt_feature_name| alternate_feature_options.include?(params[alt_feature_name]) }
  end
end
