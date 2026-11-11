# typed: true
# frozen_string_literal: true

module Sessions
  class TwoFactorAlternativesComponent < ApplicationComponent
    include AbstractController::Helpers
    include GitHubMobileAuthHelper

    def initialize(user:, prompt_type:, list_label_id:, current_device_id: nil, auto_directed: false)
      @user = user
      @prompt_type = prompt_type
      @list_label_id = list_label_id
      @current_device_id = current_device_id
      @auto_directed = auto_directed
    end

    private

    attr_reader :user, :prompt_type, :list_label_id, :current_device_id, :auto_directed

    def render?
      user.present?
    end

    def can_use_trusted_device?
      !prompt_type.in?(%w[device checkup_app checkup_sms]) && user.has_webauthn_credential?
    end

    def trusted_device_description
      user.available_u2f_registrations_description(current_device_id, capitalize_first_word: true)
    end

    def can_use_gh_mobile?
      !prompt_type.in?(%w[mobile checkup_app checkup_sms]) && T.unsafe(self).user_and_session_can_use_gh_mobile_auth?(user)
    end

    def can_use_2fa_app_code?
      !prompt_type.in?(%w[app checkup_app]) && user.two_factor_configured_with?(:app)
    end

    def can_use_2fa_sms_code?
      !prompt_type.in?(%w[sms checkup_sms sms_confirm]) && user.two_factor_sms_enabled?
    end

    def can_use_2fa_code_resend?
      prompt_type.in?(%w[sms checkup_sms]) && user.two_factor_sms_enabled?
    end

    def can_use_2fa_fallback?
      prompt_type.in?(%w[sms checkup_sms]) && user.two_factor_sms_fallback_enabled?
    end

    def can_use_recovery_code?
      !prompt_type.in?(%w[recovery_code checkup_app checkup_sms])
    end

    def show_recovery_code_help?
      !is_checkup_prompt?
    end

    def show_account_recovery?
      prompt_type.in?(%w[recovery_code]) && !GitHub.single_or_multi_tenant_enterprise?
    end

    def is_checkup_prompt?
      prompt_type.in?(%w[checkup_app checkup_sms])
    end

    def webauthn_path
      case prompt_type
      when "mobile"
        github_mobile_navigating_away_metrics_path(reason: "webauthn_prompt", auto: auto_directed)
      else
        webauthn_prompt_path
      end
    end

    def gh_mobile_path
      github_mobile_two_factor_prompt_path
    end

    def two_factor_app_code_path
      return settings_two_factor_checkup_path(type: "app") if is_checkup_prompt?

      case prompt_type
      when "mobile"
        github_mobile_navigating_away_metrics_path(reason: "two_factor_app_prompt", auto: auto_directed)
      else
        two_factor_app_prompt_path
      end
    end

    def two_factor_sms_code_path
      return settings_two_factor_checkup_path(type: "sms") if is_checkup_prompt?

      case prompt_type
      when "mobile"
        github_mobile_navigating_away_metrics_path(reason: "two_factor_sms_confirm", auto: auto_directed)
      else
        two_factor_sms_confirm_path
      end
    end

    def recovery_path
      case prompt_type
      when "mobile"
        github_mobile_navigating_away_metrics_path(reason: "two_factor_recover_prompt", auto: auto_directed)
      else
        two_factor_recover_prompt_path
      end
    end

    def reconfigure_two_factor_path
      settings_security_path
    end
  end
end
