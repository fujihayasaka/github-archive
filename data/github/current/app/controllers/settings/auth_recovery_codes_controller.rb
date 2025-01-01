# typed: true
# frozen_string_literal: true

module Settings
  class AuthRecoveryCodesController < ApplicationController
    # The following actions do not require conditional access checks because
    # they *don't* access protected organization resources.
    # rubocop:disable GitHub/DoNotSkipCapBeforeAction
    skip_before_action :perform_conditional_access_checks, only: %w(
      index
      download_recovery_codes
      print
      update
    )

    before_action :login_required
    before_action :ensure_two_factor_enabled
    before_action :ensure_user_has_two_factor_enabled
    before_action :set_cache_control_no_store
    before_action :sudo_filter
    before_action :track_views

    javascript_bundle :settings

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Authnd,
      ApplicationRecord::Collab,
      ApplicationRecord::IamAbilities,
      only: [:print]

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Authnd,
      ApplicationRecord::Collab,
      ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Repositories,
      only: [:index]

    depends_on_clusters ApplicationRecord::Copilot,
      only: [:index],
      optional: true

    # only send the 2FA recovery codes viewed email once every hour for a user
    # this prevents a user from receiving multiple emails if they refresh the page
    # or if the GET is called twice (e.g. turbo, etc.)
    RECOVERY_CODES_VIEWED_EMAIL_THROTTLE = 1.hour

    def index
      GitHub.dogstats.increment("two_factor.holiday_warning_banner.engaged", tags: ["action:download_recovery_codes"]) if params[:two_factor_holiday_warning]
      GitHub.dogstats.increment("security_checkup_banner.engaged", tags: ["notice_type:#{params[:notice]}"]) if params[:notice]
      GitHub.dogstats.increment("two_factor.recovery_codes.viewed", tags: [
        "recent_security_checkup:#{current_user.recently_took_action_on_security_checkup?}",
      ])
      current_user.instrument_two_factor_recovery_codes_viewed

      if FeatureFlag.vexi.enabled?(:view_recovery_codes_email, current_user, default: false)
        if !session[:recovery_codes_email_last_sent_at] || RECOVERY_CODES_VIEWED_EMAIL_THROTTLE.ago.utc > session[:recovery_codes_email_last_sent_at]
          AccountMailer.recovery_codes_viewed(current_user, Time.now.utc).deliver_later
          session[:recovery_codes_email_last_sent_at] = Time.now.utc
        end
      end

      # If the user has visited the recovery codes page
      # we should hide the banner warnings
      @hide_two_factor_recover_code_warning = true

      if !!params[:from_banner] && !session[:user_visited_recovery_codes]
        session[:user_visited_recovery_codes] = true
        GitHub.dogstats.increment("recovery_code_settings_viewed", tags: ["from_banner:true"])
      end

      updated = session.delete(:recovery_codes_regenerated)
      render "settings/auth_recovery_codes/index", locals: { updated: updated }
    end

    def download_recovery_codes # rubocop:todo GitHub/UseRestfulActions
      GitHub.dogstats.increment("two_factor.recovery_codes.downloaded", tags: [
        "recent_security_checkup:#{current_user.recently_took_action_on_security_checkup?}",
        "related_global_notice:#{current_user.recovery_codes_related_global_notice?}",
        "global_notice:#{current_user.global_notice.name}",
      ])
      current_user.two_factor_credential.recovery_codes_downloaded!
      # Windows notepad likes extra fancy newlines https://github.com/github/github/issues/29828
      codes = current_user.two_factor_credential.formatted_recovery_codes
      send_data(
        codes.join("\r\n"),
        filename: "github-recovery-codes.txt",
      )
    end

    def print # rubocop:todo GitHub/UseRestfulActions
      GitHub.dogstats.increment("two_factor.recovery_codes.printed", tags: [
        "recent_security_checkup:#{current_user.recently_took_action_on_security_checkup?}",
        "related_global_notice:#{current_user.recovery_codes_related_global_notice?}",
        "global_notice:#{current_user.global_notice.name}",
      ])
      # We need to connect to a write role to update "recovery_codes_last_printed_at" since this is a GET request
      ActiveRecord::Base.connected_to(role: :writing) do
        current_user.two_factor_credential.recovery_codes_printed!
      end
      render "settings/auth_recovery_codes/print", layout: "layouts/popup", locals: { codes: current_user.two_factor_credential.formatted_recovery_codes }
    end

    def update
      credential = current_user.two_factor_credential
      credential.generate_recovery_secret!
      if credential.save
        GitHub.dogstats.increment("two_factor.recovery_codes.regenerated", tags: [
          "recent_security_checkup:#{current_user.recently_took_action_on_security_checkup?}",
          "regenerated_from_banner_warning:#{!!session[:user_visited_recovery_codes]}",
          "related_global_notice:#{current_user.recovery_codes_related_global_notice?}",
          "global_notice:#{current_user.global_notice.name}",
        ])
        flash[:warn] = "New two-factor recovery codes successfully generated. Save them in a safe, durable location and discard your previous codes."
        updated = true
        AccountMailer.two_factor_enable(credential, updated).deliver_later
      else
        flash[:error] = "Something went wrong. Please try again."
      end

      session[:recovery_codes_regenerated] = true
      redirect_to settings_auth_recovery_codes_path
    end

    private

    def track_views
      select_write_database do
        current_user.two_factor_credential.recovery_codes_viewed!
      end
    end

    def ensure_two_factor_enabled
      unless GitHub.auth.two_factor_authentication_enabled?
        render_404
      end
    end

    def ensure_user_has_two_factor_enabled
      unless current_user.two_factor_authentication_enabled?
        if request.xhr?
          head 422
        else
          redirect_to settings_user_2fa_intro_path
        end
      end
    end
  end
end
