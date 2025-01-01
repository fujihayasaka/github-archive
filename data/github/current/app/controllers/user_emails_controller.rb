# typed: false
# frozen_string_literal: true

class UserEmailsController < ApplicationController
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  before_action :login_required, :find_user_or_organization
  before_action :find_email, except: [:create, :confirm_verification, :toggle_visibility, :toggle_email_visibility_warning, :set_backup]
  before_action :ensure_authority
  before_action :disallow_for_enterprise_managed_user, except: [:request_claim, :cancel_claim_request, :confirm_claim, :mark_as_unclaimed]
  before_action :emu_required, only: [:request_claim, :cancel_claim_request, :confirm_claim, :mark_as_unclaimed]
  before_action :sudo_filter, only: [:destroy]
  before_action :sudo_filter, only: [:create]
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Authnd,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    only: [:confirm_verification]

  before_action :limit_unverified_emails, only: [:create] if GitHub.email_verification_enabled?

  MAXIMUM_UNVERIFIED_EMAILS = 20
  BACKUP_EMAIL_PRIMARY_ONLY = "primary_only"
  BACKUP_EMAIL_ALLOW_ALL = "all"

  include GitHub::RateLimitedRequest
  rate_limit_requests \
    only: [:request_verification, :confirm_verification],
    key: :send_email_verification_rate_limit_key,
    log_key: :send_email_verification_log_key,
    max: 10,
    ttl: 1.hour,
    at_limit: :send_email_verification_rate_limit_render

  def create
    email = params[:user_email] && params[:user_email][:email]

    if current_user.is_first_emu_owner?
      profile_email = email
      email = current_user.add_emu_shortcode_to_emails(email)
    end

    handle_dupe_email!(email) and return if UserEmail.duplicate?(email)

    user_email = if @user.organization?
      @user.add_email(email)
    else
      if current_user.is_first_emu_owner?
        if current_user.primary_user_email.email == email
          current_user.primary_user_email
        else
          primary_user_email = current_user.emails.build(email: email)

          if primary_user_email && primary_user_email.valid?
            old_primary_email = current_user.primary_user_email
            status = current_user.set_primary_email primary_user_email

            unless status.error?
              current_user.remove_email old_primary_email

              profile = if current_user.persisted?
                current_user.find_or_create_profile
              else
                current_user.build_profile
              end

              unless profile.email == profile_email
                profile.email = profile_email
                profile.save
              end
            end
          end

          primary_user_email
        end
      else
        current_user.add_email(email)
      end
    end

    if user_email && user_email.valid?
      redirect = params[:user_email] && params[:user_email][:redirect]
      if GitHub.email_verification_enabled? && user_email.request_verification(requested_by: current_user, redirect: redirect)
        flash[:notice] = "We sent a verification email to #{email}. Please follow the instructions in it."
      end

      # Track how often the claim form is actually used.
      if params[:ref] == "commit-claim-email-form"
        GitHub.dogstats.increment("contributions", tags: ["action:claim-form-used"])
      end
    else
      error =
        if (reserved_domain_error = user_email.errors.where(:email, :reserved_domain)).any?
          reserved_domain_error&.first.options[:message]
        elsif  user_email
          user_email.errors.full_messages.to_sentence
        else
          "email is already in use"
        end
      flash[:error] = "Error adding #{email}: #{error}."
    end

    redirect_to settings_email_preferences_path
  end

  def destroy
    destroyed = current_user.remove_email @email unless current_user.is_enterprise_managed?

    if request.xhr?
      head :ok
    else
      if destroyed
        flash[:notice] = "Removed email #{@email} from your account."
      else
        flash[:error] = current_user.errors.full_messages.to_sentence
      end
      redirect_to settings_email_preferences_path
    end
  end

  def toggle_visibility # rubocop:todo GitHub/UseRestfulActions
    if @user.primary_user_email.toggle_visibility
      if @user.primary_user_email.private?
        @user.update!(warn_private_email: true)
      else
        @user.update!(warn_private_email: false)
      end
      flash[:toggle_visibility_notice] = true
      redirect_to settings_email_preferences_path(@user)
    else
      flash[:error] = "Error changing visibility on your email"
      redirect_to settings_email_preferences_path
    end
  end

  def toggle_email_visibility_warning # rubocop:todo GitHub/UseRestfulActions
    if @user.toggle_warn_private_email
      if @user.warn_private_email?
        flash[:notice] = "Commits pushed with a private email will now be blocked and you will see a warning."
      else
        flash[:notice] = "Commits pushed with a private email will no longer be blocked."
      end
    else
      flash[:error] = "Error changing your private email warning settings."
    end

    redirect_to settings_email_preferences_path
  end

  def set_primary # rubocop:todo GitHub/UseRestfulActions
    verified_email_required =
      GitHub.email_verification_enabled? &&
      @user.emails.not_bouncing.user_entered_emails.verified.any? &&
      @email.unverified?
    if verified_email_required
      flash[:error] = "Please use a verified email address."
    elsif (set_primary_email_status = @user.set_primary_email(@email)).success?
      if notification_email_changed?(@email)
        flash[:prompt_notification_email] = true
      else
        flash[:notice] = "Your primary email was changed to #{@email}."
      end
    else
      flash[:error] = \
        "Error setting your primary email address: #{set_primary_email_status.error.downcase}"
    end

    redirect_to settings_email_preferences_path
  end

  def set_backup # rubocop:todo GitHub/UseRestfulActions
    if params[:id] == BACKUP_EMAIL_ALLOW_ALL
      @user.allow_password_reset_with_any_email
      email_type = if !GitHub.email_verification_enabled?
        "All"
      elsif @user.verified_emails?
        "All verified"
      else
        "All unverified"
      end
      flash[:notice] = "#{email_type} emails can now be used for password resets."
    elsif params[:id] == BACKUP_EMAIL_PRIMARY_ONLY
      @user.allow_password_reset_with_primary_email_only
      flash[:notice] = "Only your primary email address can now be used for password resets."
    else
      email = @user.emails.find(params[:id])
      if GitHub.email_verification_enabled? && email.unverified?
        flash[:error] = "Please use a verified email address."
      elsif @user.primary_user_email == email
        flash[:error] = "Please select the 'Only allow primary email' option."
      elsif @user.set_backup_email(email)
        flash[:notice] = "Your backup email was changed to #{email}."
      else
        flash[:error] = "Error setting your backup email address"
      end
    end

    redirect_to settings_email_preferences_path
  end

  def request_verification # rubocop:todo GitHub/UseRestfulActions
    if @email.request_verification
      flash[:notice] = "We sent a verification email to #{@email}. Please follow the instructions in it."
    else
      flash[:error] = if @email.disposable?
        "Emails from the '#{@email.domain}' domain cannot be verified."
      else
        "Could not send email verification."
      end
    end

    redirect_to_return_to(fallback: settings_email_preferences_path)
  end

  def confirm_verification # rubocop:todo GitHub/UseRestfulActions
    if params[SignupsMailer::LAUNCH_CODE_METRICS_PARAM].present?
      # Log when the fallback link from the launch code email was clicked.
      GitHub.dogstats.increment("launch_code_verification.email_fallback_link_clicked")
    end

    result = ActiveRecord::Base.connected_to(role: :writing) do
      UserEmail::Verify.call(
        email_id: params[:id],
        token: params[:t],
        owner: current_user,
      )
    end

    GitHub.dogstats.increment("email.confirm_verification", tags: [
      "success:#{result.success?}",
      "recent_security_checkup:#{current_user.recently_took_action_on_security_checkup?}",
      "related_global_notice:#{current_user.verified_emails_related_global_notice?}",
      "global_notice:#{current_user.global_notice.name}",
    ])

    if result.success?
      flash[:notice] = "Your email was verified."

      # If this is the first email the user has verified, they're new: redirect them appropriately.
      start_space = current_user.feature_enabled?(:nux_redirect_to_welcome) ? signup_welcome_path : get_started_path
      redirect_path = current_user.emails.verified.count == 1 ? start_space : home_path
      safe_redirect_to params.fetch(:redirect, redirect_path)
    else
      notice_type = result.error == :already_verified ? :notice : :error
      redirect_path = result.error == :already_verified ? home_path : settings_email_preferences_path

      flash[notice_type] = result.error_message
      redirect_to redirect_path
    end
  end

  def access_denied # rubocop:todo GitHub/UseRestfulActions
    redirect_to_login(request.url)
  end

  def request_claim # rubocop:todo GitHub/UseRestfulActions
    if @email.request_claim(requested_by: current_user)
      flash[:notice] = "We sent a confirmation email to #{@email.deobfuscated_email}. Please follow the instructions in it to verify your email."
    elsif @email.errors.any?
      flash[:error] = "#{@email.errors.full_messages.to_sentence}."
    else
      flash[:error] = "Email verification could not be requested."
    end

    redirect_to_return_to(fallback: settings_email_preferences_path)
  end

  def cancel_claim_request # rubocop:todo GitHub/UseRestfulActions
    if @email.cancel_claim_request(canceler: @user)
      flash[:notice] = "Email verification request canceled."
    elsif @email.errors.any?
      flash[:error] = "#{@email.errors.full_messages.to_sentence}."
    else
      flash[:error] = "Email verification request could not be canceled."
    end

    redirect_to_return_to(fallback: settings_email_preferences_path)
  end

  def confirm_claim # rubocop:todo GitHub/UseRestfulActions
    if @email.confirm_claim(claimer: @user, token: params[:token])
      flash[:notice] = "Email successfully verified."
    elsif @email.errors.any?
      flash[:error] = "#{@email.errors.full_messages.to_sentence}."
    else
      flash[:error] = "Email could not be verified."
    end

    redirect_to_return_to(fallback: settings_email_preferences_path)
  end

  def mark_as_unclaimed # rubocop:todo GitHub/UseRestfulActions
    if @email.mark_as_unclaimed(unclaimer: @user)
      flash[:notice] = "Email successfully unverified."
    elsif @email.errors.any?
      flash[:error] = "#{email.errors.full_messages.to_sentence}."
    else
      flash[:error] = "Email could not be unverified."
    end

    redirect_to_return_to(fallback: settings_email_preferences_path)
  end

  private

  # Set flash error and redirect on a duplicate email error
  def handle_dupe_email!(email)
    flash[:error] = "Error adding #{email}: email is already in use"
    redirect_to settings_email_preferences_path
  end

  def find_user_or_organization
    @user = User.with_logins(params[:user_id] || params[:organization_id]).first!
  end

  def find_email
    @email = @user.emails.find(params[:id])
  end

  def ensure_authority
    if @user.organization?
      unless @user.adminable_by?(current_user)
        redirect_to :back, alert: "You must be an owner to add an email to this organization."
      end
    else
      redirect_to settings_email_preferences_path unless current_user == @user
    end
  end

  def send_email_verification_rate_limit_key
    "resend_verification_email:#{current_user.id}"
  end

  def send_email_verification_log_key
    "resend-verification-email-#{current_user.id}"
  end

  def send_email_verification_rate_limit_render
    GitHub.dogstats.increment("rate_limited", tags: ["action:user_email_request_verification"])
    flash[:error] = "You have exceeded our email verification rate limit. Please try again later."
    redirect_to settings_email_preferences_path
  end

  def limit_unverified_emails
    if @user.emails.user_entered_emails.unverified.count >= MAXIMUM_UNVERIFIED_EMAILS
      flash[:error] = "Please verify one or more of your unverified emails before adding another."
      redirect_to settings_email_preferences_path
    end
  end

  def disallow_for_enterprise_managed_user
    return unless @user.is_emu_and_not_first_owner?

    flash[:error] = UserEmail::ENTERPRISE_MANAGED_USER_ERROR

    if action_name == "request_verification"
      redirect_to_return_to(fallback: settings_email_preferences_path)
    else
      redirect_to settings_email_preferences_path
    end
  end

  def notification_email_changed?(primary_email)
    settings_response = GitHub.newsies.settings(@user)

    if settings_response.success?
      settings = settings_response.value
      notification_email = settings.email(:global).address

      return notification_email != primary_email.to_s
    end

    false
  end
end
