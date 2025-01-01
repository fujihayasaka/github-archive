# typed: true
# frozen_string_literal: true

class Settings::CopilotController < ApplicationController
  extend T::Sig
  include Settings::ControllerMethods
  include ApplicationHelper

  before_action :login_required
  before_action :redirect_on_no_emu_seat, only: [:index]
  before_action :check_emu, only: [:update]

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
    render "settings/copilot/index", locals: {
      copilot_user: copilot_user,
      copilot_auth: copilot_auth,
      update_payment_method_path: update_payment_method_path
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

      params[:public_code_suggestions] == "allowed" ? copilot_user.allow_public_code_suggestions! : copilot_user.block_public_code_suggestions!
      params[:telemetry] == "Allow" ? copilot_user.enable_telemetry! : copilot_user.disable_telemetry!

      new_settings = copilot_user.copilot_user_settings

      Copilot::Instrumenter.instrument_settings_saved(
        copilot_user,
        old_settings: old_settings,
        new_settings: new_settings,
      )

      changed_settings = new_settings.to_a - old_settings.to_a
      changed_settings = Hash[*changed_settings.flatten]

      if format.html_fragment
        render(
          Copilot::Policies::UserSettingsComponent.new(
            copilot_user: copilot_user,
            submit_path: copilot_save_settings_path,
            changed_settings: changed_settings,
            error: false
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
end
