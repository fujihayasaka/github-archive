# typed: true
# frozen_string_literal: true

class Businesses::TrialAccountsController < ApplicationController
  include SharedBusinessActions
  include Businesses::TrialAccountsHelper

  before_action :login_required
  before_action :dotcom_required
  before_action only: [:new, :create] do
    T.bind(self, Businesses::TrialAccountsController)
    check_trade_compliance(redirect_url: dashboard_path, sdn_redirect: true)
  end
  before_action :add_csp_exceptions, only: [:new, :create]
  before_action :non_emu_required

  include Site::MicrosoftAnalyticsDependency
  before_action :allow_initial_cookie_consent, only: [:new, :create]
  before_action :enable_microsoft_analytics, only: [:new, :create]
  before_action :add_microsoft_analytics_csp_exceptions, only: [:new, :create]
  layout "enterprise_funnel", only: [:new, :create]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    only: [:new]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:new],
    optional: true

  CSP_EXCEPTIONS = {
    frame_src: [GitHub.urls.octocaptcha_host_name],
  }

  javascript_bundle :businesses
  javascript_bundle :signup

  stylesheet_bundle :site
  stylesheet_bundle :features

  def new
    if current_user.feature_enabled?(:metered_ghe_users_can_create_trials) && !params[:users_type].present?
      user_type_selector
    else
      new_trial
    end
  end

  def create
    analytics_event(
      category: "enterprise_trial_account",
      action: "create_enterprise_trial",
      label: "location:new_enterprise_trial_account;org_attached:#{business_organization.present?};org_plan:#{business_organization&.plan};user:#{current_user.display_login};slug:#{business_params[:slug]};acknowledged_missing_features_during_trial:#{ActiveModel::Type::Boolean.new.cast(params[:features_disabled_warning])};signed_tos:#{ActiveModel::Type::Boolean.new.cast(params[:business_owned])};"
    )

    @organization = business_organization
    owners = case
    when emu_trial?
      []
    when @organization.present?
      @organization.admins
    else
      [current_user]
    end

    business_creator = Business::Creator.new(
      business_params: business_params.merge(
        can_self_serve: true,
        owners: owners,
        seats: trial_seat_count,
        plan_duration: plan_duration,
        business_type: business_type,
        trial_expires_at: business_trial_expires_at,
        customer_attributes: business_params.fetch(:customer_attributes, {}).merge(
          billing_end_date: billing_end_date,
          billing_type: Customer::BILLING_TYPE_CARD,
          metered_ghe: metered_trial?,
          term_length: term_length
        )
      ),
      organization: @organization,
      organization_plan: @organization.present? ? "business_plus" : nil,
      actor: current_user,
      require_owners: !emu_trial?,
      billing_full_name: params[:company_info] ? params[:company_info][:full_name] : nil,
      marketing_consent: marketing_email_opt_in
    )

    error = nil

    if params[:business_owned].blank?
      error = "You must agree to the Customer Agreement to create your enterprise account."
      return render_creation_error(business_creator.business, error)
    end

    if !params[:account_screening_profile] || params[:account_screening_profile][:country_code].blank?
      error = "You must select a country from the dropdown below."
      return render_creation_error(business_creator.business, error)
    end

    if params[:features_disabled_warning].blank?
      error = "You must acknowledge that certain features will be unavailable during your trial to create your enterprise account."
      return render_creation_error(business_creator.business, error)
    end

    unless business_creator.valid?
      error = "Failed to create enterprise account: #{business_creator.error_message}."
      return render_creation_error(business_creator.business, error)
    end

    octocaptcha = Octocaptcha.new(session, params["octocaptcha-token"], page: :enterprise_trial_create, user: current_user)
    octocaptcha.verify
    unless octocaptcha.solved?
      error = "Unable to verify your captcha answer. " \
      "Please try again or visit #{octocaptcha_help_url} for troubleshooting information."
      return render_creation_error(business_creator.business, error)
    end

    if trade_screening_enabled?
      merged_screening_record_fields = trade_screening_record_fields.merge(entity_name: business_creator.business.name, address1: "", city: "")
      trade_screening_record = business_creator.business.build_trade_screening_record(merged_screening_record_fields)
      trade_screening_record.validate
      trade_screening_record.errors.delete(:owner_id)
      if trade_screening_record.errors.any?
        trade_screening_errors = trade_screening_record.errors.full_messages.to_sentence
        error = "Billing information has to be valid before proceeding. #{trade_screening_errors}"
        return render_creation_error(business_creator.business, error)
      end
    end

    if params[:staff_owned] == "true" && employee?
      business_creator.business.staff_owned = true
    end

    business_creator.save!
    business = business_creator.business

    # azure subscriptions handle trade screening and only metered trials use
    # azure subscriptions for a payment method at this time
    if trade_screening_enabled?
      trade_screening_record.owner = business
      trade_screening_record.save!
    end

    enqueue_cloud_trial_marketing_notification_job(business)
    schedule_enterprise_trial_emails(current_user, business) unless emu_trial?

    if metered_trial?
      GitHub.dogstats.increment("billing_platform.onboard_metered_self_serve_trial")
      business.customer.onboard_to_billing_platform(
        products: [Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Ghec.serialize],
      )
      plan_duration = "month"
    end

    if onboard_volume_self_serve_to_billing_platform?
      GitHub.dogstats.increment("billing_platform.onboard_volume_self_serve_trial")
      business.customer.onboard_to_billing_platform(
        products: [
          Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Actions.serialize,
          Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Codespaces.serialize,
          Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Copilot.serialize,
          Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Git_Lfs.serialize,
          Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Packages.serialize
        ]
      )
    end

    business.enable_self_serve_payments(skip_billing: true, plan_duration: plan_duration || "year")

    if emu_trial?
      create_first_emu_admin_with_password_reset(business)
      return
    end

    flash[:notice] = "Created #{business.name} enterprise trial account."

    if AzureEXP::Experiments.enterprise_onboarding_org_create?(current_user) && @organization.blank?
      redirect_to new_enterprise_onboarding_organization_path(business)
    else
      redirect_to enterprise_getting_started_path(business)
    end
  end

  private

  def user_type_selector
    render "businesses/trial_accounts/user_type_selector", locals: {
      organization: business_organization,
    }
  end

  def new_trial
    business = Business.new(
      owners: [current_user],
      seats: trial_seat_count
    )

    render "businesses/trial_accounts/new", locals: {
      business: business,
      maximum_seat_count: trial_seat_count,
      organizations: selectable_organizations(business),
      organization: business_organization,
      metered_trial: metered_trial?,
      business_type: business_type.to_s,
      emu_enterprise: emu_trial?,
      employee: employee?,
      show_organization_selection_dropdown: show_organization_selection_dropdown?,
      show_org_upgrade_not_possible_for_emu_banner: show_org_upgrade_not_possible_for_emu_banner?,
    }
  end

  def create_first_emu_admin_with_password_reset(business)
    business.create_and_add_first_emu_owner(email: business.billing_email, actor: current_user)
    first_admin = business.owners.first

    schedule_enterprise_trial_emails(first_admin, business)

    reset = PasswordReset.new(
      user: first_admin,
      email: first_admin.email,
      force: true,
      expires: 7.days.from_now,
    )

    logout_user
    redirect_to reset.link
  end

  def enqueue_cloud_trial_marketing_notification_job(business)
    return unless params[:company_info]

    if GitHub.flipper[:marketing_forms_api_integration_enterprise_trial].enabled?(current_user)
      details = trial_details_for_marketing_forms_api(business, trial_attributes)
      Billing::EnterpriseCloudTrialMarketingNotificationJob.perform_later(details, target: :marketing_forms)
    else
      details = trial_details_for_marketing(business, trial_attributes)
      Billing::EnterpriseCloudTrialMarketingNotificationJob.perform_later(details, target: :eloqua)
    end
  end

  def metered_trial?
    metered_ghec_trial? || emu_trial?
  end

  def metered_ghec_trial?
    users_type == :metered_ghe
  end

  def emu_trial?
    users_type == :enterprise_managed
  end

  def trade_screening_enabled?
    return true unless metered_trial?
    current_user.feature_enabled?(:metered_ghe_cc_paypal_payments)
  end

  def onboard_volume_self_serve_to_billing_platform?
    current_user.feature_enabled?(:onboard_volume_self_serve_to_billing_platform)
  end

  def users_type
    return :volume_ghe unless current_user.feature_enabled?(:metered_ghe_users_can_create_trials)

    return :enterprise_managed if params[:users_type] == "enterprise_managed" || params[:business_type] == "enterprise_managed"
    return :metered_ghe if params[:users_type] == "metered_ghe" || params[:metered_plan] == "true"

    :volume_ghe
  end

  def business_type
    return :enterprise_managed if users_type == :enterprise_managed

    :default_managed
  end

  def render_creation_error(business, error)
    flash[:error] = error
    render "businesses/trial_accounts/new", status: 422, locals: {
      business: business,
      organizations: selectable_organizations(business),
      metered_trial: metered_trial?,
      business_type: business_type,
      emu_enterprise: emu_trial?,
      show_organization_selection_dropdown: show_organization_selection_dropdown?,
      show_org_upgrade_not_possible_for_emu_banner: show_org_upgrade_not_possible_for_emu_banner?,
      company_info: params[:company_info],
      trade_screening_record_fields: params[:account_screening_profile],
      organization_id: params[:organization_id],
    }
  end

  def business_params
    params.require(:business).permit(
      :billing_email,
      :name,
      :slug,
      :shortcode
    )
  end

  def trade_screening_record_fields
    params.require(:account_screening_profile).permit(
      :country_code
    )
  end

  memoize def business_trial_starts_at
    Time.current
  end

  memoize def business_trial_expires_at
    business_trial_starts_at + Billing::EnterpriseCloudTrial.trial_length
  end

  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end

  def trial_attributes
    params.require(:company_info).permit(
      :full_name,
      :industry,
      :other_industry,
      :employees_size,
    )
  end

  def trial_details_for_marketing(business, trial_attributes)
    {
      business_id: business.id,
      business_slug: business.slug,
      business_name: business.name,
      email: current_user.email,
      user_id: current_user.id,
      trial_start: business_trial_starts_at.as_json,
      trial_expiration: business_trial_expires_at.as_json,
      user_agent: user_session.user_agent,
      remote_ip_address: user_session.ip,
      state: user_session.location[:region],
      city: user_session.location[:city],
      country: user_session.location[:country_code],
      postal_code: user_session.location[:postal_code],
      marketing_email_opt_in: marketing_email_opt_in,
      trial_id: business.id, # Update this after working on billing changes
      event_type: "cloud_trial",
      agreed_to_terms: true,
      billing_email: business.billing_email,
    }.merge(
      trial_attributes.slice(
        :full_name,
        :industry,
        :other_industry,
        :employees_size,
      ),
    ).merge(
      session.fetch(:utm_memo, Hash.new).slice("utm_medium", "utm_source", "utm_campaign"),
    ).stringify_keys
  end

  # These required fields are submitted to the marketing forms API, notable changes are
  # - Using the country code from the account screening profile (the country is user selected)
  # - The marketingConsent field is set to optInExplicit if the user has opted in
  def trial_details_for_marketing_forms_api(business, trial_attributes)
    cdl_program_name = GitHub.ghec_trial_campaign_id
    source = GitHub.ghec_trial_source.presence || GitHub.ghec_trial_campaign_id
    sf_status = GitHub.ghec_trial_status
    {
      dot_com_org_id: business.id,
      dot_com_org_name: business.slug,
      organization_name: business.name,
      email_address: business.billing_email,
      github_user_id: current_user.id,
      trial_start: business_trial_starts_at.as_json,
      trial_expiration: business_trial_expires_at.as_json,
      country: trade_screening_record_fields[:country_code],
      postal_code: user_session.location[:postal_code],
      marketingConsent: marketing_email_opt_in ? "optInExplicit" : nil,
      cDLProgramName: cdl_program_name,
      source: source,
      sFDCLastCampaignStatus: sf_status,
      billingEmail: business.billing_email,
      fullName1: trial_attributes[:full_name],
      industry1: trial_attributes[:industry],
    }.merge(
      session.fetch(:utm_memo, Hash.new).slice("utm_medium", "utm_source", "utm_campaign"),
    )
  end

  def marketing_email_opt_in
    if GitHub.flipper[:marketing_forms_api_integration_enterprise_trial].enabled?(current_user)
      params[:marketing_email_opt_in].present?
    else
      NewsletterPreference.marketing_preference(user: current_user)
    end
  end

  def business_organization
    return nil if metered_trial? && !current_user.feature_enabled?(:metered_ghe_allow_volume_transfers)

    if params[:organization_id].present?
      org = Organization.find_by_login(params[:organization_id])
      return org if org.present? && org.adminable_by?(current_user) && org.business.blank? && !org.invoiced?
    end

    nil
  end

  def selectable_organizations(business)
    current_user.owned_organizations.select { |org| org.selectable_for_enterprise_trial?(business) }
  end

  def trial_seat_count
    Billing::EnterpriseCloudTrial::INITIAL_SEAT_COUNT
  end

  def plan_duration
    return Business::BillingDependency::MONTHLY_PLAN if metered_trial?
    Business::BillingDependency::YEARLY_PLAN
  end

  def term_length
    metered_trial? ? 1 : 12
  end

  def billing_end_date
    metered_trial? ? GitHub::Billing.today + 1.month : GitHub::Billing.today + 1.year
  end

  def schedule_enterprise_trial_emails(user_to_email, business)
    welcome_enterprise_trial_account(user_to_email, business)
    trial_period_ending_for_enterprise_trial_account(user_to_email, business)
  end

  memoize def employee?
    current_user&.employee?
  end

  def show_organization_selection_dropdown?
    return true unless metered_trial?
    current_user.feature_enabled?(:metered_ghe_allow_volume_transfers) && !emu_trial?
  end

  def show_org_upgrade_not_possible_for_emu_banner?
    return false unless emu_trial?
    return false unless current_user.feature_enabled?(:metered_ghe_allow_volume_transfers)
    business_organization.present?
  end
end
