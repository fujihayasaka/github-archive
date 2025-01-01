# typed: true
# frozen_string_literal: true

module OrganizationsControllerMethods
  extend ActiveSupport::Concern
  extend T::Helpers
  include GitHub::Memoizer

  requires_ancestor { ApplicationController }

  def at_rate_limit
    message = "You've attempted this action too many times. Please try again later."

    respond_to do |format|
      format.html_fragment do
        render \
          body: message,
          formats: :html,
          status: 429
      end

      format.html do
        flash[:error] = message
        redirect_to :back
      end
    end
  end

  def per_seat_pricing_model(coupon: nil, new_plan: nil, duration: params[:plan_duration])
    Billing::PlanChange::PerSeatPricingModel.new \
      @current_organization,
      seats: params[:seats] || @current_organization.seats,
      plan_duration: duration,
      new_plan: new_plan,
      coupon: coupon
  end

  def org_creators_only
    if !user_can_create_organizations?
      if current_user.spammy? && !GitHub.enterprise?
        flash[:error] = "Something went wrong. Please contact support."
        redirect_to :back
      else
        render_404
      end
    end
  end

  def org_hash
    @org_hash ||= begin
      organization_profile_attributes = GitHub.sponsors_enabled? ? [:sponsors_update_email] : []

      permitted_organization_params = [
        :email, :login, :billing_email, :plan, :profile_name, :profile_email,
        :profile_blog, :profile_company, :profile_location, :profile_hireable,
        :profile_bio, :gravatar_email, :billing_extra, :plan_duration,
        :members_can_create_repositories, :granular_repo_creation_permissions_changing,
        :members_can_create_public_repositories, :members_can_create_private_repositories,
        :members_can_create_internal_repositories, :seats, :company_name, :profile_twitter_username,
        :achievements_projects_opt_out,
        admin_logins: [],
        profile_social_accounts: [:key, :url],
        organization_profile_attributes: organization_profile_attributes
      ]

      params.require(:organization).permit(permitted_organization_params)
    end
  end

  def trial_attributes
    params.require(:company_info).permit(
      :full_name,
      :industry,
      :other_industry,
      :employees_size,
    ).merge(
      params.require(:user).permit(:ga_client_id, :ga_tracking_id, :ga_user_id),
    )
  end

  def trial_details_for_marketing(organization:, cloud_trial:, trial_attributes:)
    {
      organization_id: organization.id,
      organization_login: organization.display_login,
      company_name: organization.company_name,
      email: current_user.email,
      user_id: current_user.id,
      trial_start: cloud_trial.started_on.as_json,
      trial_expiration: cloud_trial.expires_on.as_json,
      user_agent: user_session.user_agent,
      remote_ip_address: user_session.ip,
      state: user_session.location[:region],
      city: user_session.location[:city],
      country: user_session.location[:country_code],
      postal_code: user_session.location[:postal_code],
      marketing_email_opt_in: NewsletterPreference.marketing_preference(user: current_user),
      trial_id: cloud_trial.plan_trial_id,
      event_type: "cloud_trial",
      agreed_to_terms: true,
      billing_email: organization.billing_email,
    }.merge(
      params[:trial_acquisition_channel] == "resources" ? { paid_media_sourced: true } : {}
    ).merge(
      trial_attributes.slice(
        :full_name,
        :industry,
        :other_industry,
        :employees_size,
        :ga_client_id,
        :ga_tracking_id,
        :ga_user_id,
      ),
    ).merge(
      session.fetch(:utm_memo, Hash.new).slice("utm_medium", "utm_source", "utm_campaign"),
    ).stringify_keys
  end

  def create_enterprise_trial_for_existing_org
    existing_organization = Organization.find_by_login(org_hash[:profile_name])
    return render_404 unless existing_organization.adminable_by?(current_user)

    enterprise_trial_for_existing_org_and_redirect(existing_organization)
  end

  def enterprise_trial_for_existing_org_and_redirect(organization)
    success = T.let(false, T::Boolean)

    if !agreed_to_terms_attribute?
      flash[:error] = "GitHub Customer Agreement has to be accepted to start a GitHub Enterprise Cloud Trial."
      return redirect_back(fallback_location: new_organization_path)
    end

    cloud_trial = Billing::EnterpriseCloudTrial.new(organization)
    Organization.transaction do
      if cloud_trial.create && organization.update(org_hash)
        success = true
      end
    end

    if success
      check_ghas_eligibility(organization)

      marketing_details = trial_details_for_marketing(
        organization: organization,
        cloud_trial: cloud_trial,
        trial_attributes: trial_attributes,
      )
      send_and_setup_trial_notifications(cloud_trial, organization, current_user, marketing_details)

      flash[:notice] = "Welcome to GitHub Enterprise Cloud Trial!"

      enterprise_trial_redirect(organization)
    else
      flash[:error] = "Sorry, the organization is not eligible for GitHub Enterprise Cloud Trial!"
      redirect_back(fallback_location: new_organization_path)
    end
  end

  def enterprise_trial_redirect(organization)
    if params[:trial_acquisition_channel] != "resources"
      return redirect_to user_path(organization)
    end

    # We add an 'order_id' parameter so resources.github.com can track the conversion event.
    # The value is a random string unrelated to any user or organization.
    # We use a 32-length, alphanumeric string to reduce the chance of collisions.
    resources_redirect_path = "https://resources.github.com/enterprise/trial/thankyou?order_id=#{SecureRandom.alphanumeric(32)}"

    cookies[:enterprise_trial_redirect_to] = { value: organization.display_login, expires: 5.minutes.from_now, httponly: true }

    # rubocop:disable GitHub/RailsViewRenderPathsExist
    render(
      "organizations/signup/enterprise_trial_meta_redirect",
      locals: { redirect_url: resources_redirect_path },
      layout: "layouts/redirect"
    )
  end

  def agreed_to_terms_attribute?
    params[:agreed_to_terms] == "yes"
  end

  def check_ghas_eligibility(organization)
    return unless GitHub.flipper[:ghas_trial_eligibility].enabled?(organization)

    ::EnterpriseCloudOnboard::GhasTrialEligibilityJob.perform_later(organization)
  end

  def send_and_setup_trial_notifications(trial, organization, user, marketing_details = nil)
    send_welcome_email_for_enterprise_cloud_trial(user, organization)

    deliver_end_email_at = (trial.expires_on - 1.day).to_datetime
    send_delayed_end_enterprise_cloud_trial_email(user, organization, deliver_end_email_at)

    unless marketing_details.nil?
      EnterpriseCloudTrialMarketingNotificationJob.perform_later(marketing_details)
    end
  end

  # Internal: Sends a welcome email to creator of organization that meets the criteria:
  # 1. Creator is opt-out of marketing emails
  # 2. Organization is on a free trial for GHE Cloud
  #
  # Returns nothing.
  def send_welcome_email_for_enterprise_cloud_trial(creator, organization)
    return unless organization.plan_trial_active?

    OrganizationMailer.welcome_enterprise_cloud_trial(creator, organization).deliver_later
  end

  # Internal: Sends a welcome email to creator of organization that meets the criteria:
  # 1. Creator is opt-out of marketing emails
  # 2. Organization is on a free trial for GHE Cloud
  #
  # Returns nothing.
  def send_delayed_end_enterprise_cloud_trial_email(creator, organization, delivery_date)
    return unless organization.plan_trial_active?

    OrganizationMailer.end_enterprise_cloud_trial(creator, organization).deliver_later(wait_until: delivery_date)
  end

  memoize def github_customer_terms?
    params["terms_of_service_type"]&.downcase == "corporate"
  end

  memoize def standard_terms_of_service?
    params["terms_of_service_type"]&.downcase == "standard"
  end

  def orgs_data_collection_enabled?
    github_customer_terms? || standard_terms_of_service?
  end

  def account_screening_profile_params
    params.require(:account_screening_profile).permit \
      :first_name,
      :last_name,
      :middle_name,
      :region,
      :city,
      :country_code,
      :postal_code,
      :address1,
      :address2,
      :org_record_is_individual_owned,
      :entity_name,
      :vat_code
  end

  memoize def account_screening_profile_hash
    return nil unless orgs_data_collection_enabled?
    return nil unless params[:account_screening_profile].present?

    account_screening_profile_params.except(
      :org_record_is_individual_owned
    ).to_h
  end

  def require_signup_flow_redesign
    render_404 unless GitHub.billing_enabled?
  end
end
