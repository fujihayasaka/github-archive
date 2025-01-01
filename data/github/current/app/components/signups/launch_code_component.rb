# typed: true
# frozen_string_literal: true

module Signups
  class LaunchCodeComponent < ApplicationComponent
    sig do params(
      email: UserEmail,
      error: T.nilable(String),
      resent: T::Boolean,
      invitation_token: T.nilable(String),
      repo_invitation_token: T.nilable(String),
      dark_mode: T::Boolean
    ).void
    end
    def initialize(
      email:,
      error: nil,
      resent: false,
      invitation_token: nil,
      repo_invitation_token: nil,
      dark_mode: false
    )
      @email = email
      @resent = resent
      @error = error
      @dark_mode = dark_mode
    end

    private

    attr_reader :email,
                :resent,
                :error,
                :invitation_token,
                :repo_invitation_token,
                :dark_mode
    alias :resent? :resent

    def color_theme
      @dark_mode ? "dark" : "light"
    end

    def render?
      email.unverified?
    end

    memoize def show_launch_code?
      if email.verification_token.present?
        email.launch_code_verification?
      else
        current_user.user?
      end
    end

    def launch_code_length
      email.verification_token&.length || UserEmail::LAUNCH_CODE_LENGTH
    end

    def resend_verification_path
      if accountless_verification_present?
        resend_account_verification_path(verification: params[:verification].presence, return_to: account_verifications_path(resent: 1, verification: params[:verification].presence, return_to: return_to))
      else
        request_verification_user_email_path(
          current_user,
          email,
          return_to: account_verifications_path(resent: 1, invitation_token: params[:invitation_token], repo_invitation_token: params[:repo_invitation_token], return_to: return_to)
        )
      end
    end

    def accountless_verification_present?
      params[:verification].present? || session[:accountless_email_verification_id].present?
    end

    def update_email_path
      # For accountless email verification, we just send user to the signup page again
      if accountless_verification_present?
        new_nux_signup_path
      else
        settings_email_preferences_path
      end
    end

    def return_to
      session[:return_to] || params[:return_to]
    end

    def hidden_fields_params
      {
        return_to: return_to,
        invitation_token: invitation_token,
        repo_invitation_token: repo_invitation_token,
        plan: params[:plan],
        verification: params[:verification],
        setup_organization: params[:setup_organization],
        trial_acquisition_channel: params[:trial_acquisition_channel],
      }.merge(
        params[:plan_duration].present? ? { plan_duration: params[:plan_duration] } : {}
      )
    end

    # Until this feature is ready for production release, allow the feature to be darkshipped via feature flag to review_lab without being released to production.
    # Also allow for this to always be available on localhost.
    sig { returns(T::Boolean) }
    def is_non_prod_env?
      Rails.env.development? || GitHub.review_lab?
    end

    sig { returns(T::Boolean) }
    def show_react_launch_component?
      GitHub.flipper[:nux_react_launch_code].enabled? &&
      GitHub.flipper[:nux_split_traffic].enabled? &&
      is_non_prod_env? &&
      helpers.feature_enabled_if_even_octo_cookie_id?
    end
  end
end
