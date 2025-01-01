# typed: true
# frozen_string_literal: true

class EmailUnlinkController < ApplicationController
  include GitHub::RateLimitable

  layout "layouts/session_authentication"

  before_action :dotcom_required

  before_action :requires_valid_token
  before_action :requires_valid_user
  before_action :render_flash_messages, only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    only: [:index]

  # pages meant to be accessed anonymously, authorization not necessary
  private def resource_for_conditional_access
    :no_resource_for_conditional_access # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
  end

  private def target_for_conditional_access
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  private def requires_valid_token
    @unlink = EmailUnlink.build_from_token params[:token]
    unless @unlink
      GitHub.dogstats.increment("two_factor_account_recovery.email_unlink.sat_validation_failure.count")
      return render "sessions/email_unlink/bad_token"
    end

    @user = @unlink.user

    if @unlink.staff_initated?
      GitHub.dogstats.increment("two_factor_account_recovery.email_unlink.staff_bypass.count", tags: ["action:#{action_name}"])
    end
  end

  private def requires_valid_user
    return render_404 if @user&.is_emu_and_not_first_owner?
  end

  private def render_flash_messages
    flash[:notice] = @unlink.flash_notice if @unlink.flash_notice?
    flash[:warn] = @unlink.flash_warn if @unlink.flash_warn?
    flash[:error] = @unlink.flash_error if @unlink.flash_error?
  end

  # given an EmailUnlink token, render a page that allows a user to begin the process of unlinking emails associated
  # with their account
  def index
    unless @unlink.email
      if @unlink.emails_sent?
        GitHub.dogstats.increment("two_factor_account_recovery.email_unlink.render.emails_sent.count")
        return render "sessions/email_unlink/verification_sent", locals: {
          display_login: @user.display_login,
        }
      else
        GitHub.dogstats.increment("two_factor_account_recovery.email_unlink.render.initiate.count", tags: [
          "without_password:#{session[:user_without_password].present?}"
        ])
        return render "sessions/email_unlink/initiate", locals: {
          display_login: @user.display_login,
        }
      end
    end

    if @unlink.successful?
      GitHub.dogstats.increment("two_factor_account_recovery.email_unlink.render.success.count", tags: [
        "without_password:#{session[:user_without_password].present?}"
      ])
      render "sessions/email_unlink/success", locals: {
        display_login: @user.display_login,
        email: @unlink.email,
      }
    elsif @unlink.failed?
      GitHub.dogstats.increment("two_factor_account_recovery.email_unlink.render.failure.count")
      render "sessions/email_unlink/failure", locals: {
        display_login: @user.display_login,
        email: @unlink.email,
      }
    else
      GitHub.dogstats.increment("two_factor_account_recovery.email_unlink.render.confirm.count")
      render "sessions/email_unlink/confirm", locals: {
        display_login: @user.display_login,
        email: @unlink.email,
        unlink_blocker: AppSecurity::EmailHelper.prevent_email_unlink_message(@unlink.email)
      }
    end
  end

  # given an account-bound SAT, send an email to each email address associated with the account,
  # allowing unlinking of the email address from the account
  def update
    if @unlink.email
      render_404
    else
      @user.emails.not_bouncing.each do |email|
        GitHub.dogstats.increment("two_factor_account_recovery.email_unlink.email_verification.count", tags: ["verified:#{email.verified?}"])
        link = EmailUnlink.new(@user, email: email.email).link
        CriticalAccountLoginMailer.email_unlink_verification(email, @user, link).deliver_later
      end

      @user.instrument_email_unlink_initiate(reason: "account-lockout")
      @unlink.mark_emails_sent!
      redirect_to email_unlink_index_path(@unlink.token)
    end
  end

  def submit # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless @unlink.email

    to_remove = @user.emails.detect { |e| e.email == @unlink.email }
    unlink_error = AppSecurity::EmailHelper.unlink_from_account(@user, to_remove, two_factor_lockout: true)
    if unlink_error
      GitHub.dogstats.increment("two_factor_account_recovery.email_unlink.failed.count")
      @unlink.fail!
      @unlink.flash_error = unlink_error
      return redirect_to email_unlink_index_path(@unlink.token)
    end

    if @user.primary_user_email.email.match?(/\.unlinked[0-9]+\z/)
      GitHub.dogstats.increment("two_factor_account_recovery.email_unlink.final_email_unlinked.count")
      GitHub.instrument("user.disable_notifications", user: @user, reason: "final_email_unlinked")
    end

    # revoke all third party apps (oauth + github)
    OauthAuthorization.transaction do
      @user.oauth_authorizations.third_party.destroy_all
      @user.oauth_authorizations.third_party_github_apps.destroy_all
    end

    if @user.has_valid_payment_method?(feature_type: :noncommercial)
      GitHub.dogstats.increment("two_factor_account_recovery.email_unlink.active_payment.count")
      @unlink.flash_warn = "The '#{@user.display_login}' account has an active payment method. Please contact support to remove the payment method."
    end

    GitHub.dogstats.increment("two_factor_account_recovery.email_unlink.complete.count")
    @unlink.complete!
    redirect_to email_unlink_index_path(@unlink.token)
  end
end
