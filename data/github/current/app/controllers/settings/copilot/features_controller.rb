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
      if params_errors?(params)
        if format.html_fragment
          return render(
            Copilot::Policies::UserSettingsComponent.new(
              copilot_user: copilot_user,
              submit_path: copilot_save_settings_path,
              error: true
            ),
            layout: false
          )
        end

        if format.html
          return render "settings/copilot/index", locals: {
            error: true,
            form_submit_path: copilot_save_settings_path,
            copilot_user: copilot_user
          }
        end
      end

      old_settings = copilot_user.copilot_user_settings
      old_dashboard_entry_point_enabled = copilot_user.dashboard_entry_point_enabled?

      params[:copilot_policy_bing] == "enabled" ? copilot_user.bing_github_chat_enabled! : copilot_user.bing_github_chat_disabled!
      params[:public_code_suggestions] == "allowed" ? copilot_user.allow_public_code_suggestions! : copilot_user.block_public_code_suggestions!
      params[:telemetry] == "Allow" ? copilot_user.enable_telemetry! : copilot_user.disable_telemetry!

      if params[:dashboard_entry_point].present?
        params[:dashboard_entry_point] == "enabled" ? copilot_user.dashboard_entry_point_enabled! : copilot_user.dashboard_entry_point_disabled!
      end

      if params[:editor_preview_features].present?
        params[:editor_preview_features] == "enabled" ? copilot_user.editor_preview_features_enabled! : copilot_user.editor_preview_features_disabled!
      end

      if params[:automatic_code_review].present? && copilot_user.feature_enabled?(:copilot_code_review_user_automatic_setting)
        params[:automatic_code_review] == "enabled" ? copilot_user.automatic_code_review_enabled! : copilot_user.automatic_code_review_disabled!
      end

      if params[:a_chat].present? && params[:a_chat] != "unconfigured"
        params[:a_chat] == "enabled" ? copilot_user.a_chat_enabled! : copilot_user.a_chat_disabled!
      end

      if params[:a_f].present? && params[:a_f] != "unconfigured"
        params[:a_f] == "enabled" ? copilot_user.a_f_enabled! : copilot_user.a_f_disabled!
      end

      if params[:afos].present? && params[:afos] != "unconfigured"
        params[:afos] == "enabled" ? copilot_user.afos_enabled! : copilot_user.afos_disabled!
      end

      if params[:al].present? && params[:al] != "unconfigured" && copilot_user.feature_enabled?(:copilot_al)
        params[:al] == "enabled" ? copilot_user.al_enabled! : copilot_user.al_disabled!
      end

      if params[:g_chat].present? && params[:g_chat] != "unconfigured"
        params[:g_chat] == "enabled" ? copilot_user.g_chat_enabled! : copilot_user.g_chat_disabled!
      end

      if params[:g_tf].present? && params[:g_tf] != "unconfigured"
        params[:g_tf] == "enabled" ? copilot_user.g_tf_enabled! : copilot_user.g_tf_disabled!
      end

      if params[:gtff].present? && params[:gtff] != "unconfigured" && copilot_user.feature_enabled?(:copilot_gtff)
        params[:gtff] == "enabled" ? copilot_user.gtff_enabled! : copilot_user.gtff_disabled!
      end

      if params[:o1].present? && params[:o1] != "unconfigured"
        params[:o1] == "enabled" ? copilot_user.o1_enabled! : copilot_user.o1_disabled!
      end

      if params[:o3].present? && params[:o3] != "unconfigured"
        params[:o3] == "enabled" ? copilot_user.o3_enabled! : copilot_user.o3_disabled!
      end

      if params[:o_f].present? && params[:o_f] != "unconfigured"
        params[:o_f] == "enabled" ? copilot_user.o_f_enabled! : copilot_user.o_f_disabled!
      end

      if params[:o_ff].present? && params[:o_ff] != "unconfigured"
        params[:o_ff] == "enabled" ? copilot_user.o_ff_enabled! : copilot_user.o_ff_disabled!
      end

      if params[:o_fm].present? && params[:o_fm] != "unconfigured"
        params[:o_fm] == "enabled" ? copilot_user.o_fm_enabled! : copilot_user.o_fm_disabled!
      end

      if params[:o_t].present? && params[:o_t] != "unconfigured"
        params[:o_t] == "enabled" ? copilot_user.o_t_enabled! : copilot_user.o_t_disabled!
      end

      if params[:ofo].present? && params[:ofo] != "unconfigured"
        params[:ofo] == "enabled" ? copilot_user.ofo_enabled! : copilot_user.ofo_disabled!
      end

      if current_user.feature_preview_enabled?(:copilot_chat_custom_instructions) && params[:default_org_custom_instructions].present?
        copilot_user.user_object.settings.set!(:copilot_default_org_custom_instructions, params[:default_org_custom_instructions])
      end

      if params[:overages].present? && params[:overages] != "unconfigured"
        params[:overages] == "enabled" ? copilot_user.overages_enabled! : copilot_user.overages_disabled!
      end

      if params[:billable_customer].present?
        copilot_user.set_billable_customer_id!(params[:billable_customer].to_i)
      end

      new_settings = copilot_user.copilot_user_settings
      new_dashboard_entry_point_enabled = copilot_user.dashboard_entry_point_enabled?

      changed_settings = new_settings.to_a - old_settings.to_a
      changed_settings = Hash[*changed_settings.flatten]

      # don't need to instrument settings changed when only dashboard entry point is changed
      unless changed_settings.empty?
        Copilot::Instrumenter.instrument_settings_saved(
          copilot_user,
          old_settings: old_settings,
          new_settings: new_settings,
        )
      end

      if old_dashboard_entry_point_enabled != new_dashboard_entry_point_enabled
        changed_settings[:dashboard_entry_point_setting] = new_dashboard_entry_point_enabled ? :ENABLED : :DISABLED
      end

      if format.html_fragment
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
      elsif format.html
        return render("settings/copilot/index", locals: {
          form_submit_path: copilot_save_settings_path,
          copilot_user: copilot_user
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

  sig { params(params: ActionController::Parameters).returns(T::Boolean) }
  def params_errors?(params)
    !params[:public_code_suggestions].present?
  end

  def copilot_auth # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @copilot_auth if defined?(@copilot_auth)
    @copilot_auth = Copilot::Authorizer.new(copilot_user, include_snippy: false) # not including snippy check
  end

  memoize def copilot_user
    T.must_because(current_copilot_user) { "#login_required ensures non-nil" }
  end

  def check_emu
    redirect_to "/settings/profile" if copilot_user.is_enterprise_managed?
  end

  def update_payment_method_path
    settings_user_billing_tab_path(tab: "payment_information")
  end

  sig { void }
  def redirect_on_no_emu_seat
    if copilot_user.is_enterprise_managed?
      redirect_to "/settings/profile" unless copilot_user.has_enterprise_seat?
    end
  end

  def redirect_to_features_page?
    request.path == "/settings/copilot"
  end
end
