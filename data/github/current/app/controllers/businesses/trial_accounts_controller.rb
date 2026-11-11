# typed: true
# frozen_string_literal: true

class Businesses::TrialAccountsController < ApplicationController
  include SharedBusinessActions
  include Businesses::TrialAccountsHelper
  include SecretScanning::Features::FeatureFlagHelper
  include WithParameterValidation
  include Signups::CustomContentDependency
  include DatadomeGlbGating

  before_action :login_required
  before_action :dotcom_required
  before_action :validate_user_requirements, only: [:new, :create]
  before_action only: [:new, :create] do
    T.bind(self, Businesses::TrialAccountsController)
    check_trade_compliance(redirect_url: dashboard_path, sdn_redirect: true)
  end
  before_action only: [:create] do
    T.bind(self, Businesses::TrialAccountsController)
    organization = organization_to_attach
    check_trade_compliance(target: organization, redirect_url: dashboard_path, sdn_redirect: true) if organization.present?
  end
  before_action :add_csp_exceptions, only: [:new, :create]
  before_action :non_emu_required
  before_action :strip_blocked_copilot_business_with_param, only: [:new, :create]
  before_action :ff_enabled_for_japan_stamp, only: [:create]

  include Site::MicrosoftAnalyticsDependency
  before_action :allow_initial_cookie_consent, only: [:new, :create]
  before_action :enable_microsoft_analytics, only: [:new, :create]
  before_action :add_microsoft_analytics_csp_exceptions, only: [:new, :create]
  layout :trial_layout, only: [:new, :create]

  depends_on_clusters \
    ApplicationRecord::Authnd,
    ApplicationRecord::Mysql1,
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
  stylesheet_bundle "business-trial"

  def new
    if params[:show_verification].present? && params[:business_slug].present?
      show_verification_form
    elsif params[:region].present? || params[:users_type].present?
      new_trial
    else
      user_type_selector
    end
  end

  def create
    @organization = organization_to_attach

    analytics_event(
      category: "enterprise_trial_account",
      action: "create_enterprise_trial",
      label: "location:new_enterprise_trial_account;org_attached:#{@organization.present?};org_plan:#{@organization&.plan};user:#{current_user.display_login};slug:#{business_params[:slug]};acknowledged_missing_features_during_trial:#{ActiveModel::Type::Boolean.new.cast(params[:features_disabled_warning])};signed_tos:#{ActiveModel::Type::Boolean.new.cast(params[:business_owned])};"
    )

    owners = case
    when emu_trial?
      []
    when @organization.present?
      @organization.admins
    else
      [current_user]
    end

    error = nil
    business_creator = data_hosting_required? ? nil : dfd_trial_business_creator(owners)
    entity = data_hosting_required? ? multi_tenant_provisioning_request : business_creator.business
    if !entity.valid? || !trial_terms_valid?
      if !trial_terms_valid?
        entity.errors.add(:trial_terms, "Please acknowledge these terms and check these boxes to proceed.")
      elsif user_has_identical_provisioning_request_in_progress?(entity)
        entity.errors.clear
        error = "Your request to create this enterprise is already being processed."
      end
      return render_creation_error(entity, error)
    end

    if entity.is_a?(Business) && !business_creator.valid?
      error = "Failed to create enterprise account: #{business_creator.error_message}."
      return render_creation_error(business_creator.business, error)
    end

    octocaptcha = Octocaptcha.new(session, params["octocaptcha-token"], page: :enterprise_trial_create, user: current_user)
    octocaptcha.verify
    unless octocaptcha.solved?
      error = "Unable to verify your captcha answer."
      return render_creation_error(entity, error, captcha_error: true)
    end

    entity.staff_owned = params[:staff_owned] == "true" && employee?

    if data_hosting_required?
      if current_user.feature_flag_enabled?(:proxima_tms_background_job, default: false)
        entity.save!
        TenantProvisioningJob.perform_later(entity)
      else
        entity.provision_tenant
        if entity.provisioning_step == "in_progress"
          entity.save!
        else
          if entity.errors.empty?
            error = "Unable to create your enterprise. Please try again."
          end
          return render_creation_error(entity, error)
        end
      end

      enqueue_cloud_trial_with_data_hosting_marketing_notification_job

      EnterpriseManagedUserMailer.tenant_provisioning_in_progress(
        entity.subdomain, entity.admin_work_email, entity.data_hosting_region
      ).deliver_later
      redirect_url = enterprise_multi_tenant_provisioning_request_path(entity.subdomain)
      redirect_url += "?with=#{get_with_param}" if get_with_param.present?
      redirect_to redirect_url
    else
      merged_billing_contact_fields = billing_contact_fields.merge(entity_name: business_creator.business.name, address1: "", city: "")
      billing_contact = business_creator.business.billing_contact
      billing_contact.assign_attributes(merged_billing_contact_fields)
      billing_contact.validate(:new_self_serve_business)
      billing_contact.errors.delete(:owner_id)
      billing_contact.errors.delete(:customer_id)
      if billing_contact.errors.any?
        billing_contact_errors = billing_contact.errors.full_messages.to_sentence
        error = "Billing information has to be valid before proceeding. #{billing_contact_errors}."
        return render_creation_error(business_creator.business, error)
      end

      if billing_email_rate_limited?
        return render "businesses/trial_accounts/account_restricted", status: 403, locals: {
            reason_header: "Sorry, you've reached your limit.",
            reason_body: "You've created #{EnterpriseTrialLimit.default_limit} enterprise accounts using your admin work email, which is the most GitHub can support. If you’d like to try GitHub Enterprise, Copilot Business, and Advanced Security in a new enterprise account, we recommend that you ask a colleague to do so for you."
        }
      end
      business_creator.save!
      business = business_creator.business
      billing_contact.respond_to?(:customer) ? billing_contact.customer = business.customer : billing_contact.owner = business
      billing_contact.save!(context: :new_self_serve_business)

      enqueue_cloud_trial_marketing_notification_job(business)

      convert_to_self_serve_billing(business)

      if emu_trial?
        create_first_emu_admin_with_password_reset(business)
        return
      end

      # Set to pending verification if feature flag is enabled, otherwise activate immediately
      if email_verification_required?
        business.update!(trial_completion_status: :trial_email_verification_pending)
        email_sent = business.send_verification_email(current_user)

        respond_to do |format|
          format.html do
            if email_sent
              flash[:notice] = "Enterprise trial created! Please check your email for a verification email to activate your trial."
            else
              flash[:error] = "Enterprise trial created, but we couldn't send the verification email. Please try resending it."
            end
            if get_with_param.present?
              redirect_to enterprise_trial_accounts_new_path(show_verification: true, business_slug: business.slug, with: get_with_param)
            else
              redirect_to enterprise_trial_accounts_new_path(show_verification: true, business_slug: business.slug)
            end
          end

          format.turbo_stream do
            render "businesses/trial_accounts/create",
                   layout: false,
                   locals: { business: business, with_param: get_with_param, email_sent: email_sent }
          end
        end
      else
        # Original flow - activate trial immediately
        business.update!(trial_completion_status: :no_trial_or_active_trial)
        business.enable_dfd_trial_experience(T.cast(current_user, User))
        schedule_enterprise_trial_emails(T.cast(current_user, User), business) unless emu_trial?
        flash[:notice] = "Created #{business.name} enterprise trial account."
        redirect_to next_path(business)
      end
    end
  end

  private

  def trial_layout
    "layouts/enterprise_dfd_funnel"
  end

  def next_path(business)
    with_param = get_with_param
    if with_param.present?
      with_param_to_url(business, params)
    elsif business.copilot_trial_activation_blocked?
      enterprise_path(business)
    else
      enterprise_trial_activations_path(business)
    end
  end

  def email_verification_required?
    return false if current_user.employee?
    true
  end

  def user_type_selector
    render "businesses/trial_accounts/user_type_selector_dfd", locals: {
      organization: business_organization,
      custom_page_param: custom_page_param,
      contentful_custom_content_entry: contentful_custom_content_entry(custom_page_param)
    }
  end

  def show_verification_form
    business = Business.find_by(slug: params[:business_slug])

    unless business
      flash[:error] = "Enterprise not found."
      return redirect_to enterprise_trial_accounts_new_path
    end

    render "businesses/trial_accounts/new", locals: {
      entity: business,
      show_verification: true,
      business: business,
      with_param: get_with_param
    }
  end

  def new_trial
    entity = Business.new(owners: [T.cast(current_user, User)], seats: trial_seat_count)

    render "businesses/trial_accounts/new", locals: {
      entity: entity,
      custom_page_param: custom_page_param,
      contentful_custom_content_entry: contentful_custom_content_entry(custom_page_param),
      maximum_seat_count: trial_seat_count,
      organizations: selectable_organizations(entity),
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
    business.create_and_add_first_emu_owner(email: business.billing_email, actor: T.cast(current_user, User), auto_verify_email: false)
    first_admin = business.owners.first

    business.enable_dfd_trial_experience(first_admin)
    schedule_enterprise_trial_emails(first_admin, business)

    logout_user
    anonymous_flash[:notice] = "Your account was created successfully. Please use the password reset link sent to #{business.billing_email} to continue."
    redirect_to login_path
  end

  def enqueue_cloud_trial_marketing_notification_job(business)
    return unless params[:company_info]

    details = trial_details_for_marketing_forms_api(business, trial_attributes)

    MarketingFormsSubmissionJob.perform_later(form_name: "enterprise-cloud-trial-new", raw_data: details)
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

  def organization_to_attach
    emu_trial? ? nil : business_organization
  end

  def users_type
    return :enterprise_managed if params[:users_type] == "enterprise_managed" || params[:business_type] == "enterprise_managed" || params[:region].present?
    return :metered_ghe if params[:users_type] == "metered_ghe" || params[:metered_plan] == "true"

    :volume_ghe
  end

  def business_type
    return :enterprise_managed if users_type == :enterprise_managed

    :default_managed
  end

  def render_creation_error(entity, error, captcha_error: false)
    selectable_organizations = entity.is_a?(Business) ? selectable_organizations(entity) : []

    render "businesses/trial_accounts/new", status: 422, locals: {
      error: error,
      entity: entity,
      data_hosting_required: data_hosting_required?,
      organizations: selectable_organizations,
      metered_trial: metered_trial?,
      business_type: business_type,
      emu_enterprise: emu_trial?,
      captcha_error: captcha_error,
      show_organization_selection_dropdown: show_organization_selection_dropdown?,
      show_org_upgrade_not_possible_for_emu_banner: show_org_upgrade_not_possible_for_emu_banner?,
      company_info: params[:company_info],
      billing_contact_fields: params[:billing_contact],
      organization_id: params[:organization_id],
      with: params[:with]
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

  def multi_tenant_params
    params.require(:multi_tenant).permit(
      :data_hosting_region,
      :subdomain
    )
  end

  def billing_contact_fields
    params.require(:billing_contact).permit(
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
      marketing_email_opt_in: marketing_email_opt_in?,
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
      country: billing_contact_fields[:country_code],
      postal_code: user_session.location[:postal_code],
      marketingConsent: marketing_email_opt_in? ? "optInExplicit" : nil,
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

  def enqueue_cloud_trial_with_data_hosting_marketing_notification_job
    cdl_program_name = GitHub.proxima_trial_campaign_id
    source = GitHub.proxima_trial_source.presence || GitHub.proxima_trial_campaign_id
    sf_status = GitHub.proxima_trial_status

    details = {
      billingEmail: business_params[:billing_email],
      cDLProgramName: cdl_program_name,
      country: billing_contact_fields[:country_code],
      email_address: business_params[:billing_email],
      fullName1: trial_attributes[:full_name],
      github_user_id: current_user.id,
      industry1: trial_attributes[:industry],
      marketingConsent: marketing_email_opt_in? ? "optInExplicit" : nil,
      organization_name: business_params[:name],
      postal_code: user_session.location[:postal_code],
      sFDCLastCampaignStatus: sf_status,
      source: source,
      trial_expiration: business_trial_expires_at.as_json,
      trial_start: business_trial_starts_at.as_json,
    }.merge(
      session.fetch(:utm_memo, Hash.new).slice("utm_medium", "utm_source", "utm_campaign"),
    )

    MarketingFormsSubmissionJob.perform_later(form_name: "proxima-cloud-trial", raw_data: details)
  rescue => e
    GitHub.logger.error("Failed to enqueue marketing notification job for cloud trial with data hosting", {
      "exception.class" => e.class.name,
      "exception.message" => e.message,
      "exception.backtrace" => e.backtrace&.join("\n"),
      "code.function" => __method__,
      "code.namespace" => self.class.name,
    })
  end

  def marketing_email_opt_in?
    params[:marketing_email_opt_in] == "1"
  end

  def business_organization
    if params[:organization_id].present?
      org = Organization.find_by_login(params[:organization_id])
      return org if org.present? && org.adminable_by?(current_user) && org.business.blank? && !org.invoiced?
    end

    nil
  end

  def selectable_organizations(business)
    business.trial_selectable_organizations(current_user)
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
    !emu_trial?
  end

  def show_org_upgrade_not_possible_for_emu_banner?
    return false unless emu_trial?
    business_organization.present?
  end

  def dfd_trial_business_creator(owners)
    country_code = params[:billing_contact] ? params[:billing_contact][:country_code] : nil
    Business::Creator.new(
      business_params: business_params.merge(
        can_self_serve: true,
        owners: owners,
        seats: trial_seat_count,
        plan_duration: plan_duration,
        business_type: business_type,
        trial_expires_at: business_trial_expires_at,
        new_dfd_trial: true,
        industry: trial_attributes[:industry],
        employees_size: trial_attributes[:employees_size],
        country_code: country_code,
        emu_idp: params[:emu_idp],
        billing_full_name: trial_attributes[:full_name],
        customer_attributes: business_params.fetch(:customer_attributes, {}).merge(
          billing_end_date: billing_end_date,
          billing_type: Customer::BILLING_TYPE_CARD,
          metered_ghe: metered_trial?,
          term_length: term_length
        )
      ),
      organization: @organization,
      organization_plan: @organization.present? ? "business_plus" : nil,
      actor: T.must(current_user),
      require_owners: !emu_trial?,
      billing_full_name: trial_attributes[:full_name],
      marketing_consent: marketing_email_opt_in?,
      industry: trial_attributes[:industry],
      employees_size: trial_attributes[:employees_size]
    )
  end

  def trial_terms_valid?
    params[:business_owned] == "on" && params[:features_disabled_warning] == "on"
  end

  def data_hosting_required?
    return false unless current_user&.feature_flag_enabled?(:digital_front_door_proxima, default: false)
    return false unless business_type == :enterprise_managed
    multi_tenant_params[:data_hosting_region] != ""
  end

  def multi_tenant_provisioning_request
    country_code = params[:billing_contact] ? params[:billing_contact][:country_code] : nil
    MultiTenantProvisioningRequest.new(
      name: business_params[:name],
      subdomain: multi_tenant_params[:subdomain],
      industry: trial_attributes[:industry],
      other_industry: trial_attributes[:other_industry],
      number_of_seats: trial_attributes[:employees_size],
      country_code: country_code,
      data_hosting_region: multi_tenant_params[:data_hosting_region],
      emu_idp: params[:emu_idp],
      admin_name: trial_attributes[:full_name],
      admin_work_email: business_params[:billing_email],
      created_by: current_user,
      marketing_consent: marketing_email_opt_in?
    )
  end

  def user_has_identical_provisioning_request_in_progress?(entity)
    return false unless entity.is_a?(MultiTenantProvisioningRequest)
    return false unless existing_request = MultiTenantProvisioningRequest.find_by(
      subdomain: entity.subdomain,
      created_by: current_user)
    return false unless existing_request.provisioning_step == "in_progress"
    true
  end

  def validate_user_requirements
    # Skip account restrictions when the owner of an already-created pending
    # trial is accessing the inline verification form, not creating a new one.
    return if verification_access_for_owned_pending_trial?

    if account_restriction_reason.present?
      render "businesses/trial_accounts/account_restricted", status: 403, locals: {
        reason_header: account_restriction_reason[:header],
        reason_body: account_restriction_reason[:body]
      }
    end
  end

  def verification_access_for_owned_pending_trial?
    return false unless params[:show_verification].present? && params[:business_slug].present?

    pending_business = Business.find_by(slug: params[:business_slug])
    pending_business&.requires_email_verification? && pending_business.owner?(current_user)
  end

  memoize def trial_limiter
    EnterpriseTrialLimit.new(user: T.cast(current_user, User))
  end

  def billing_email_rate_limited?
    return false unless FeatureFlag.vexi.enabled?(:billing_email_rate_limit, current_user, default: false)
    return false if employee?
    return false unless params[:business].present?
    billing_email = business_params[:billing_email]
    # IF it's not a valid email format we want to render an error but not the rate limiting one.
    return false if billing_email.blank?
    return false unless billing_email =~ User::EMAIL_REGEX
    normalized_billing_email = UserEmail.normalize(billing_email)
    ghec_enterprise_count = Business.where(billing_email: normalized_billing_email).count
    proxima_enterprise_count = MultiTenantProvisioningRequest.where(admin_work_email: normalized_billing_email).count
    ghec_enterprise_count + proxima_enterprise_count >= EnterpriseTrialLimit.default_limit
  end

  memoize def account_restriction_reason
    return if employee?

    if current_user.spammy?
      return {
        header: "Sorry, you can't create an enterprise account right now.",
        body: "GitHub spotted some suspicious activity connected to your personal account. Until that's resolved, GitHub can't allow you to use that account to create a new enterprise account."
      }
    end

    if trial_limiter.created_trials_limit_reached?
      return {
        header: "Sorry, you've reached your limit.",
        body: "You've created #{trial_limiter.created_trials_limit} enterprise accounts over the lifetime of your personal account with GitHub, which is the most GitHub can support. If you'd like to try GitHub Enterprise, Copilot Business, and Advanced Security in a new enterprise account, we recommend that you ask a colleague to do so for you."
      }
    end

    if forbidden_due_to_recently_changed_primary_email?(current_user)
      {
        header: "Sorry, you can't create an enterprise account right now.",
        body: "You recently changed your primary email on GitHub. GitHub can't allow you to create a new enterprise account until it's been #{PRIMARY_EMAIL_COOLDOWN_PERIOD.inspect} since the change."
      }
    end
  end

  memoize def get_with_param
    extract_with_param_from_request(request, params)
  end

  def strip_blocked_copilot_business_with_param
    return unless params[:with] == "copilot-business"
    return unless FeatureFlag.vexi.enabled?(:block_enterprise_trial_copilot_activation, current_user, default: false)
    params.delete(:with)
  end

  def ff_enabled_for_japan_stamp
    if data_hosting_required? && multi_tenant_params[:data_hosting_region] == "prod_jpw_01"
      render_404 unless current_user&.feature_flag_enabled?(:proxima_enable_stamp_prod_jpw_01, default: false)
    end
  end
end
