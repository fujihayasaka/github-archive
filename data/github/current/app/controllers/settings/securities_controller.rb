# typed: true
# frozen_string_literal: true

class Settings::SecuritiesController < ApplicationController
  include ApplicationHelper
  include Settings::ControllerMethods
  include OrganizationsHelper

  CSP_EXCEPTIONS = {
    frame_src: [GitHub.urls.octocaptcha_host_name],
  }

  before_action :login_required
  before_action :ensure_trade_restrictions_allows_org_settings_access
  before_action :sudo_required_for_reconfigure, only: [:show]
  before_action :add_csp_exceptions, only: [:show]

  skip_before_action :require_two_factor_checkup

  stylesheet_bundle :settings
  javascript_bundle :settings
  javascript_bundle :"two-factor-setup"
  # the signup bundle is required for captcha
  javascript_bundle :signup

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Authnd,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    ApplicationRecord::IssuesPullRequests,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  private def reconfigure_otp_factor_supported(user, two_factor_type)
    return false unless two_factor_type && [:app, :sms].include?(two_factor_type)
    return false unless TwoFactorSetup.pending?(current_user)
    true
  end

  private def sudo_required_for_reconfigure
    two_factor_type = params["type"]&.to_sym
    return true unless reconfigure_otp_factor_supported(current_user, two_factor_type)
    perform_sudo_filter
  end

  private def configuring_type(user, two_factor_type)
    return nil unless two_factor_type && [:app, :sms].include?(two_factor_type)
    return nil unless TwoFactorSetup.pending?(current_user)
    two_factor_type
  end

  def show
    GitHub.dogstats.increment("two_factor.holiday_warning_banner.engaged", tags: ["action:add_passkey"]) if params[:two_factor_holiday_warning]
    GitHub.dogstats.increment("security_checkup_banner.engaged", tags: ["notice_type:#{params[:notice]}"]) if params[:notice]
    GitHub.dogstats.increment("two_factor_checkup.redirect_to_reconfigure") if request.env["HTTP_REFERER"]&.include?("two_factor_checkup")

    two_factor_type = params["type"]&.to_sym
    if reconfigure_otp_factor_supported(current_user, two_factor_type)
      secret = TwoFactorSetup.values_for(current_user, :secret).first
      dev_otp = GitHub::TwoFactorAuthentication.totp(secret).now if Rails.env.development?

      if two_factor_type == :app
        mashed_secret = GitHub::TwoFactorAuthentication.mashed_secret(secret)
        qr_code = qr_code_generator GitHub::TwoFactorAuthentication.provisioning_url_for_authenticator_app(secret, current_user.login) # rubocop:todo GitHub/DoNotAllowLogin https://github.com/github/authentication/issues/2400
        qr_code_image_src = "data:image/svg+xml;base64,#{Base64.encode64(qr_code.as_svg(fill: "FFF", color: "000", module_size: 3)).gsub("\n", "")}"
      end
    end

    if current_user.is_due_for_two_factor_checkup?
      flash.now[:notice] = "Please update your two-factor authentication methods on this page, otherwise access will be limited."
    end

    # We should hide the recovery codes and 2FA global warning banner
    @hide_two_factor_recover_code_warning = true
    @hide_security_warning = true

    render "settings/securities/show", locals: {
      configuring_type: configuring_type(current_user, two_factor_type),
      mashed_secret: mashed_secret,
      qr_code_image_src: qr_code_image_src,
      dev_otp: dev_otp,
    }
  end
end
