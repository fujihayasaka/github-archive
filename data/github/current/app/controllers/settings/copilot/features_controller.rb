# typed: true
# frozen_string_literal: true

class Settings::Copilot::FeaturesController < ApplicationController
  include Settings::ControllerMethods
  include Site::MicrosoftAnalyticsDependency

  before_action :login_required
  before_action :redirect_on_no_emu_seat, only: [:index]
  before_action :check_emu, only: [:update]

  before_action :enable_microsoft_analytics, only: [:index]
  before_action :add_microsoft_analytics_csp_exceptions, only: [:index]

  stylesheet_bundle :suggestions, :copilot
  javascript_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Copilot,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Configurations,
    ApplicationRecord::Ballast, # temporary, for free cca experiment
    only: [:index]

  def index
    if redirect_to_features_page?
      return redirect_to "/settings/copilot/features"
    end

    render "settings/copilot/index", locals: {
      copilot_user: copilot_user,
      copilot_auth: copilot_auth,
      update_payment_method_path: update_payment_method_path,
      enable_msft_analytics: @cookie_consent_enabled && @microsoft_analytics_enabled
    }
  end

  def update
    respond_to do |format|
      old_settings = copilot_user.copilot_user_settings
      old_dashboard_entry_point_enabled = if copilot_user.feature_flag_enabled?(:copilot_dashboard_entry_point_refactor, default: false)
        Copilot::Policies::DashboardEntryPoint.enabled?(copilot_user)
      else
        copilot_user.dashboard_entry_point_enabled?
      end

      update_settings

      new_settings = copilot_user.copilot_user_settings
      new_dashboard_entry_point_enabled = if copilot_user.feature_flag_enabled?(:copilot_dashboard_entry_point_refactor, default: false)
        Copilot::Policies::DashboardEntryPoint.enabled?(copilot_user)
      else
        copilot_user.dashboard_entry_point_enabled?
      end

      changed_settings = new_settings.to_a - old_settings.to_a
      changed_settings = Hash[*changed_settings.flatten]

      # don't need to instrument settings changed when only dashboard entry point is changed
      unless changed_settings.empty?
        Copilot::Instrumenter.instrument_settings_saved(
          copilot_user,
          old_settings: old_settings,
          new_settings: new_settings,
        )

        GitHub.logger.info(
          "User settings changed",
          "gh.user.id" => current_user.id,
          "gh.copilot.user_settings.previous_settings" => old_settings,
          "gh.copilot.user_settings.new_settings" => new_settings,
        )
      end

      if old_dashboard_entry_point_enabled != new_dashboard_entry_point_enabled
        changed_settings[:dashboard_entry_point_setting] = new_dashboard_entry_point_enabled ? :ENABLED : :DISABLED
      end

      if format.html_fragment
        # For unlicensed users updating telemetry only, render the unlicensed component
        if copilot_user.access_allowed?
          render(
            Copilot::Policies::UserSettingsComponent.new(
              copilot_user: copilot_user,
              submit_path: copilot_save_settings_path,
              changed_settings: changed_settings,
              error: false,
              disabled: !copilot_user.can_modify_copilot_settings?
            ),
            layout: false
          )
        else
          render(
            Copilot::Policies::UnlicensedUserSettingsComponent.new(
              copilot_user: copilot_user,
              submit_path: copilot_save_settings_path,
              changed_settings: changed_settings
            ),
            layout: false
          )
        end
      elsif format.html
        return render("settings/copilot/index", locals: {
          form_submit_path: copilot_save_settings_path,
          copilot_user: copilot_user,
          changed_settings: changed_settings
        })
      end
    end
  end

  sig { void }
  def show_copilot # rubocop:todo GitHub/UseRestfulActions
    if params[:show_copilot].present?
      params[:show_copilot] == "enabled" ? copilot_user.show_copilot_enabled! : copilot_user.show_copilot_disabled!
    end
    redirect_to "/settings/copilot", notice: "Your Copilot settings have been updated."
  end

  private

  sig { void }
  def update_settings
    # Always update default organization custom instructions first
    if params.key?(:default_org_custom_instructions)
      copilot_user.user_object.settings.set!(
        :copilot_default_org_custom_instructions,
        params[:default_org_custom_instructions]
      )
    end

    if !copilot_user.feature_flag_enabled?(:copilot_dashboard_entry_point_refactor, default: false) && params[:dashboard_entry_point].present?
      params[:dashboard_entry_point] == "enabled" ? copilot_user.dashboard_entry_point_enabled! : copilot_user.dashboard_entry_point_disabled!
    end

    # For EMU users, only allow updating default organization custom instructions, generated commit message and dashboard entry point
    if copilot_user.is_enterprise_managed?
      # We especially allow GeneratedCommitMessage and DashboardEntryPoint policy to be updated if the user is emu because for a non-emu user it will be included
      # as part of the Copilot::Policies::USER_MUTABLE map below, but for an emu user we skip that map so we need to special case it here
      if params.key?(:generated_commit_message)
        Copilot::Policies::GeneratedCommitMessage.update_user(copilot_user, params[:generated_commit_message])
      end

      if copilot_user.feature_flag_enabled?(:copilot_dashboard_entry_point_refactor, default: false) && params[:dashboard_entry_point].present?
        Copilot::Policies::DashboardEntryPoint.update_user(copilot_user, params[:dashboard_entry_point])
      end

      return
    end

    params[:telemetry] == "Allow" ? copilot_user.enable_telemetry! : copilot_user.disable_telemetry!

    if params[:overages].present? && params[:overages] != "unconfigured"
      params[:overages] == "enabled" ? copilot_user.overages_enabled! : copilot_user.overages_disabled!
    end

    if params[:billable_customer].present?
      copilot_user.set_billable_customer_id!(params[:billable_customer].to_i)
    end

    # dynamically update any user setting based on the params and the USER_MUTABLE map
    params.each do |key, value|
      policy_class = Copilot::Policies::USER_MUTABLE[key]
      if policy_class
        if policy_class == Copilot::Policies::DashboardEntryPoint && !copilot_user.feature_flag_enabled?(:copilot_dashboard_entry_point_refactor, default: false)
          next
        end
        policy_class.update_user(copilot_user, value)
      end
    end

    copilot_user.registry_models.each do |model|
      if params[model.model_key].present?
        params[model.model_key] == "enabled" ? copilot_user.model_enabled!(model.model_key) : copilot_user.model_disabled!(model.model_key)
      end
    end
  end

  def copilot_auth # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @copilot_auth if defined?(@copilot_auth)
    @copilot_auth = Copilot::Authorizer.new(copilot_user, include_snippy: false) # not including snippy check
  end

  memoize def copilot_user
    T.must_because(current_copilot_user) { "#login_required ensures non-nil" }
  end

  def check_emu
    if copilot_user.is_enterprise_managed?

      return if emu_editable_settings?

      redirect_to "/settings/profile"
    end
  end

  def emu_editable_settings?
    # EMU users can only update default org instructions, copilot generated commit messages and dashboard entry point, nothing else
    # This is because while EMU users should have their settings controlled by the enterprise but these policies are user updatable even for EMU users
    emu_editable_params = [:dashboard_entry_point, :default_org_custom_instructions, :generated_commit_message]

    emu_editable_params.any? { |allowed_param| params[allowed_param].present? }
  end

  def update_payment_method_path
    settings_user_billing_tab_path(tab: "payment_information")
  end

  sig { void }
  def redirect_on_no_emu_seat
    if copilot_user.is_enterprise_managed?
      redirect_to "/settings/profile" unless copilot_user.has_emu_seat?
    end
  end

  def redirect_to_features_page?
    request.path == "/settings/copilot"
  end
end
