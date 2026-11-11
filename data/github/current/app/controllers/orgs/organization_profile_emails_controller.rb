# typed: true
# frozen_string_literal: true

class Orgs::OrganizationProfileEmailsController < Orgs::Controller
  rescue_from ActiveRecord::RecordNotFound, with: :email_not_found

  before_action :login_required
  before_action :ensure_authority
  before_action :find_email, except: [:create]

  include GitHub::RateLimitedRequest
  rate_limit_requests \
    only: :resend_verification_request,
    key: :resend_email_verification_rate_limit_key,
    log_key: :resend_email_verification_log_key,
    max: 10,
    ttl: 1.hour,
    at_limit: :resend_email_verification_rate_limit_render

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    only: [:confirm_verification]

  def create
    organization_email = this_organization.add_profile_email_to_verify(current_user)

    if organization_email && organization_email.valid?
      if organization_email.request_verification
        flash[:notice] = "We have sent a verification email to #{organization_email}. Please follow the instructions in it."
      end
    else
      if organization_email
        error = organization_email.errors.full_messages.to_sentence
      else
        error = "Could not initiate email verification. Please try again later."

        GitHub.logger.warn(
          "Profile email verification could not be initiated for org",
          "code.namespace" => "OrganizationProfileEmailsController",
          "code.function" => "create",
          "gh.org.id" => this_organization.id,
          "gh.actor.id" => current_user.id,
        )
      end
      flash[:error] = "Error verifying #{organization_email}: #{error}"
    end

    redirect_back fallback_location: settings_org_publisher_path
  end

  def resend_verification_request # rubocop:todo GitHub/UseRestfulActions
    if @email.request_verification(initiator: current_user)
      flash[:notice] = "A new verification email has been sent to #{@email}, please check your email or try again."
    else
      flash[:error] = "Could not resend verification email. Please try again later."
    end

    redirect_back fallback_location: settings_org_publisher_path
  end

  def confirm_verification # rubocop:todo GitHub/UseRestfulActions
    result = ActiveRecord::Base.connected_to(role: :writing) do
      @email.verify(params[:t], current_user)
    end

    if result.success
      flash[:notice] = "Your profile email was verified for #{this_organization.display_login} organization."
    else
      if result.error == :already_verified
        notice_type = :notice
        error_message = result.error_message.gsub("verified.", "verified by #{@email.verifier}.")
      else
        notice_type = :error
        error_message = result.error_message
      end

      flash[notice_type] = error_message
    end

    redirect_to settings_org_publisher_path
  end

  private

  def find_email
    @email = this_organization.organization_profile_emails.find(params[:id])
  end

  def ensure_authority
    unless current_user.site_admin? || this_organization.adminable_by?(current_user)
      flash[:error] = "You must be an admin to verify an email for this organization."
      redirect_to home_path
    end
  end

  def email_not_found
    flash[:error] = "Sorry, we couldn’t find an email to verify."
    redirect_to settings_org_publisher_path
  end

  def resend_email_verification_rate_limit_key
    "resend_profile_verification_email:#{this_organization.id}"
  end

  def resend_email_verification_log_key
    "resend-profile-verification-email-#{this_organization.id}"
  end

  def resend_email_verification_rate_limit_render
    GitHub.dogstats.increment("rate_limited", tags: ["action:organization_profile_email_resend_verification"])
    flash[:error] = "You have exceeded our email verification rate limit. Please try again after one hour."
    redirect_to settings_org_publisher_path
  end
end
