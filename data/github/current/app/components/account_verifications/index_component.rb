# typed: true
# frozen_string_literal: true

module AccountVerifications
  class IndexComponent < ApplicationComponent
    def initialize(email:, resent: false, recommend_plan: false, error: nil, invitation_token: nil, repo_invitation_token: nil)
      @email                 = email
      @resent                = resent
      @error                 = error
      @recommend_plan        = recommend_plan
      @invitation_token      = invitation_token
      @repo_invitation_token = repo_invitation_token
    end

    private

    attr_reader :email, :resent, :error, :recommend_plan, :invitation_token, :repo_invitation_token
    alias :resent? :resent
    alias :recommend_plan? :recommend_plan

    def render?
      email.unverified?
    end

    memoize def launch_code?
      if email.verification_token.present?
        email.launch_code_verification?
      else
        current_user.user?
      end
    end

    def launch_code_length
      email.verification_token&.length || UserEmail::LAUNCH_CODE_LENGTH
    end

    def show_launch_code_animation?
      return false if params[:setup_organization] || params[:invitation_token] || params[:repo_invitation_token]
      return false if return_to.present?

      !recommend_plan?
    end

    def email_phrase
      launch_code? ? "a launch code" : "an email"
    end

    def resend_verification_path
      if accountless_verification_present?
        resend_account_verification_path(verification: params[:verification].presence, return_to: account_verifications_path(resent: 1, verification: params[:verification].presence, **redirect_or_recommend_plan))
      else
        request_verification_user_email_path(
          current_user,
          email,
          return_to: account_verifications_path(resent: 1, invitation_token: params[:invitation_token], repo_invitation_token: params[:repo_invitation_token], **redirect_or_recommend_plan)
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

    def redirect_or_recommend_plan
      return { return_to: return_to } if return_to

      { recommend_plan: recommend_plan }
    end
  end
end
