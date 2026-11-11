# typed: true
# frozen_string_literal: true

class Businesses::EmailVerificationsController < Businesses::BusinessController
  include Businesses::TrialAccountsHelper
  include WithParameterValidation

  depends_on_clusters ApplicationRecord::Mysql1,
                      ApplicationRecord::Configurations,
                      ApplicationRecord::IamAbilities,
                      ApplicationRecord::Collab,
                      ApplicationRecord::Mysql2,
                      ApplicationRecord::NotificationsEntries,
                      ApplicationRecord::Billing,
                      ApplicationRecord::Copilot

  skip_before_action :ensure_email_verified_for_trial_access
  before_action :business_owner_access_required
  before_action :ensure_verification_required

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Businesses::EmailVerificationsController#create",
    "Businesses::EmailVerificationsController#update"
  ]

  def show
    with_param = extract_with_param_from_request(request, params)

    if with_param.present?
      redirect_to enterprise_trial_accounts_new_path(show_verification: true, business_slug: this_business.slug, with: with_param)
    else
      redirect_to enterprise_trial_accounts_new_path(show_verification: true, business_slug: this_business.slug)
    end
  end

  def create
    if this_business.send_verification_email(current_user)
      flash[:notice] = "Verification email sent to your email. Please check your inbox."
    else
      flash[:error] = "Unable to send verification email. Please try again."
    end

    with_param = extract_with_param_from_request(request, params)
    if with_param.present?
      redirect_to enterprise_trial_accounts_new_path(show_verification: true, business_slug: this_business.slug, with: with_param)
    else
      redirect_to enterprise_trial_accounts_new_path(show_verification: true, business_slug: this_business.slug)
    end
  end

  def update
    code = params[:code]

    if this_business.verify_email_and_activate_trial(code)[:success]
      this_business.enable_dfd_trial_experience(current_user)

      # Send trial welcome emails now that email is verified
      welcome_enterprise_trial_account(current_user, this_business)
      trial_period_ending_for_enterprise_trial_account(current_user, this_business)

      flash[:notice] = "Email verified! Your enterprise trial is now active."
      with_param = extract_with_param_from_request(request, params)
      if this_business.copilot_trial_activation_blocked?
        redirect_to enterprise_path(this_business)
      elsif with_param.present?
        redirect_to enterprise_trial_activations_path(this_business, with: with_param)
      else
        redirect_to enterprise_trial_activations_path(this_business)
      end
    else
      flash[:error] = "Invalid or expired verification code. Please request a new one."
      with_param = extract_with_param_from_request(request, params)
      if with_param.present?
        redirect_to enterprise_trial_accounts_new_path(show_verification: true, business_slug: this_business.slug, with: with_param)
      else
        redirect_to enterprise_trial_accounts_new_path(show_verification: true, business_slug: this_business.slug)
      end
    end
  end

  private

  def business_owner_access_required
    business_access_required(allow_members: false)  # Only owners, not members
  end

  def ensure_verification_required
    unless this_business.requires_email_verification?
      redirect_to enterprise_path(this_business)
    end
  end

  def resource_for_conditional_access
    this_business || self
  end

  def target_for_conditional_access
    return :no_target_for_conditional_access unless this_business # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    this_business
  end
end
