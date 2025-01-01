# typed: true
# frozen_string_literal: true

class OrganizationsController < ApplicationController
  include BillingSettingsHelper
  include OrganizationsHelper
  include OrganizationsControllerMethods
  include BusinessesHelper
  include DashboardAnalyticsHelper
  include SeatsHelper
  include SignupHelper
  include MarketingMethods
  include Actions::PolicyHelper
  include ApplicationHelper
  include Orgs::Invitations::RateLimiting
  include TradeControlsControllerMethods
  include GitHub::RateLimitedRequest
  include ContextControllerMethods

  before_action :login_required
  before_action :check_trade_compliance, only: %w(new create), if: :couponed_paid_upgrade?
  before_action :org_members_only, except: %w(show new create)
  before_action :org_admins_only, except: %w(create destroy new show)
  before_action :org_creators_only, only: %w(new create)
  before_action :add_gh_classroom_csp_exceptions, only: :new
  before_action :orgs_set_return_to, only: :new
  before_action :require_plan_selection, only: :new
  before_action :add_csp_exceptions, only: [:new, :create]
  after_action :customer_category_instrumentation

  include Site::MicrosoftAnalyticsDependency
  before_action :allow_initial_cookie_consent, only: %w(new create)
  before_action :enable_microsoft_analytics, only: %w(new create)
  before_action :add_microsoft_analytics_csp_exceptions, only: %w(new create)
  layout "enterprise_funnel", only: %w(new create)

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:new]

  depends_on_clusters ApplicationRecord::Copilot, only: [:new, :show], optional: true

  CSP_EXCEPTIONS = {
    frame_src: [GitHub.urls.octocaptcha_host_name],
  }

  javascript_bundle "signup"
  javascript_bundle "organizations"

  stylesheet_bundle "site", only: %w(new create)
  stylesheet_bundle :signup

  def show
    # Redirect to dashboard if this org isn't found.
    # Useful after an org has been deleted and the user's context is
    # still set to that org.
    return redirect_to "/" if current_organization.nil? || current_organization.deleted?

    set_context
    context_region_title "Dashboard", path: home_url

    respond_to do |format|
      format.html do
        render "organizations/show", layout: "layouts/dashboard_three_column", locals: {
          query: params[:q],
          rate_limited: org_invite_rate_limited?,
        }
      end
    end
  end

  def new
    render_new_organization
  end

  # Creates a fresh organization.
  def create
    # If the data collection form is present and the user is not submitting payment info,
    # then this is a billing info update submit operation.
    return update_billing_information if billing_information_hash.present? && params[:billing].blank?

    GitHub.dogstats.increment("organization", tags: ["action:create"])
    GitHub.context.push(visitor_id: current_visitor.id)

    # Create as a free org plan if cloud trial
    is_enterprise_cloud_trial = params.dig("enterprise", "plan") == "cloud-trial" &&
      org_hash[:plan] == "business_plus"

    if is_enterprise_cloud_trial && !agreed_to_terms_attribute?
      flash[:error] = "GitHub Customer Agreement has to be accepted to start a GitHub Enterprise Cloud Trial."
      return redirect_back(fallback_location: new_organization_path)
    elsif GitHub.billing_enabled? && params[:billing].blank? && !agreed_to_terms_attribute?
      # params[:billing] is only set when the billing form
      # (organizations/signup/billing) is submitted, which does not
      # have the agreed_to_terms_attribute checkbox
      flash[:error] = "GitHub Customer Agreement has to be accepted to create a new organization."
      return redirect_back(fallback_location: new_organization_path)
    end

    original_plan_name = org_hash[:plan] || params[:plan]

    plan_tag = %w[free business business_plus].include?(original_plan_name) ? original_plan_name : nil

    GitHub.dogstats.increment("organization.plan_selection", tags: ["action:attempt", "plan:#{plan_tag}"])

    plan_name = if is_enterprise_cloud_trial
      GitHub::Plan.free.name
    else
      original_plan_name
    end

    plan = GitHub::Plan.find(plan_name) || GitHub::Plan.default_plan

    if plan.paid? && org_hash[:seats].present?
      max_seats = Configurable::SeatLimitForUpgrades::DEFAULT_SEAT_LIMIT_FOR_UPGRADES
      if org_hash[:seats].to_i > max_seats
        flash[:error] = "You can only add up to #{max_seats} seats when upgrading."
        return redirect_back(fallback_location: new_organization_path)
      end
    end

    old_seat_count = current_user.seats
    old_plan_name = current_user.plan.name

    org_hash[:plan_duration] = params[:plan_duration]

    if current_user.has_any_trade_restrictions? && plan.paid?
      flash[:error] = sanctioned_by_ofac_message
      GitHub.dogstats.increment("organization.plan_selection", tags: ["action:rejected", "plan:#{plan_tag}"])
      return redirect_to(organizations_new_path)
    end

    if !plan.paid? && !current_user.hammy?
      octocaptcha = Octocaptcha.new(session, params["octocaptcha-token"], page: :org_create)
      octocaptcha.verify
      if !octocaptcha.solved?
        anonymous_flash[:error] = "Unable to verify your captcha answer. " \
          "Please try again or visit #{octocaptcha_help_url} for troubleshooting information."
        view = Orgs::SetupView.new({
          current_user: current_user,
          plan: GitHub::Plan.find(original_plan_name),
          organization: Organization.new,
          extend_captcha_timeout: !!params[:error_loading_captcha],
        })
        return render "organizations/signup/new", locals: { view: view }
      end
    end

    return create_enterprise_trial_for_existing_org if params["org_exists"] == "true"

    billing_address_validated_at = session[:billing_address_validated_at_org_creation]
    if billing_address_validated_at.present? && billing_information_hash.present?
      billing_information_hash.merge!(billing_address_validated_at:)
      session.delete(:billing_address_validated_at_org_creation)
    elsif github_customer_terms? && billing_information_hash.present? && billing_information_hash[:country_code] == "US"
      # If we reach here, then the address was never validated
      flash[:error] = "Billing information has to be re-submitted before proceeding"
      redirect_uri = Addressable::URI.parse(request.referrer)
      query_values = redirect_uri.query_values || {}
      redirect_uri.query_values = query_values.except("account_screening_profile[country_code]") # causes the form to be re-rendered in edit mode because info is missing
      return redirect_to redirect_uri.to_s
    end
    result = Organization::Creator.perform(current_user,
                                           plan,
                                           org_hash,
                                           payment_details: payment_details,
                                           coupon_code: params[:coupon],
                                           business: current_user.enterprise_managed_business,
                                           business_owned: org_is_on_business_tos?,
                                           terms_of_service: params[:terms_of_service_type],
                                           trade_screening_info: billing_information_hash)

    @current_organization = result.organization
    @coupon = result.coupon

    if result.success?
      is_paid_plan = @current_organization.plan.cost > 0

      instrument_billing_form_submitted(flow: "ORGANIZATION_SIGNUP")

      GitHub.dogstats.increment("organization.plan_selection", tags: ["action:success", "plan:#{plan_tag}"])
      # Change plan to trial
      if is_enterprise_cloud_trial
        cloud_trial = Billing::EnterpriseCloudTrial.new(result.organization.reload)
        if cloud_trial.create
          send_and_setup_trial_notifications(cloud_trial, result.organization, current_user)
        end
      end

      GitHub.dogstats.increment("organization", tags: ["action:create", "type:paid"]) if is_paid_plan
      ga_action = result.organization.plan.free? ? {} : { action: "upgrade" }
      flash[:analytics_location_params] = {
        target: "Organization",
        billing: false,
        plan: result.organization.plan.name,
      }.merge(ga_action)

      analytics_event(
        **organization_creation_ga_event_attributes(
          true,
          @current_organization,
          current_user,
          is_enterprise_cloud_trial
        )
      )

      unless is_enterprise_cloud_trial
        analytics_ec_purchase(result.organization, @current_organization.subscription.discounted_price, "Signup")
        publish_billing_plan_changed_for(
          actor: current_user,
          user: @current_organization,
          old_plan_name: old_plan_name,
          new_plan_name: result.organization.plan.name,
          old_seat_count: old_seat_count,
          new_seat_count: @current_organization.seats,
          user_first_name: params[:user_first_name],
          user_last_name: params[:user_last_name],
        )

        if @current_organization.payment_method
          publish_payment_method_changed_for(
            actor: current_user,
            account: @current_organization,
            payment_method: @current_organization.payment_method,
          )
        end
      end

      add_on_checked = ActiveRecord::Type::Boolean.new.deserialize(params[:copilot_add_on]) || false

      GlobalInstrumenter.instrument(
        "analytics.event",
        category: "new_org_copilot_add_on",
        action: "create_free_org",
        label: "copilot_box_checked:#{add_on_checked};",
      )

      if session[:return_to] == "classroom"
        redirect_to_return_to(fallback: "#{GitHub.classroom_host}/classrooms/new")
      else
        if add_on_checked
          session[:return_to] = "copilot_business_signup"
          session[:copilot_flash_create_org_message] = session[:copilot_flash_pay_info_message] = true
        else
          session.delete(:return_to)
        end

        if params[:move_work].present?
          move_work_session["organization_id"] = @current_organization.id

          redirect_to move_work_confirmation_page_path(current_user)
        else
          if is_enterprise_cloud_trial
            enterprise_trial_redirect(current_organization)
          else
            redirect_to(invite_organization_path(current_organization, utm_memo))
          end
        end
      end
    else
      flash.now[:error] = result.error_message
      GitHub.dogstats.increment("organization.plan_selection", tags: ["action:failed", "plan:#{plan_tag}"])

      analytics_event(
        **organization_creation_ga_event_attributes(
          false,
          @current_organization,
          current_user,
          is_enterprise_cloud_trial
        )
      )

      @current_organization.plan = GitHub::Plan.free
      if GitHub.billing_enabled?
        @monthly_per_seat_pricing_model      = per_seat_pricing_model(coupon: @coupon, duration: "month")
        @annual_per_seat_pricing_model       = per_seat_pricing_model(coupon: @coupon, duration: "year")
        @monthly_business_plus_pricing_model = per_seat_pricing_model(coupon: @coupon, new_plan: GitHub::Plan.business_plus, duration: "month")
        @annual_business_plus_pricing_model  = per_seat_pricing_model(coupon: @coupon, new_plan: GitHub::Plan.business_plus, duration: "year")
        @per_seat_pricing_model              = per_seat_pricing_model(coupon: @coupon)
        @business_plus_pricing_model         = per_seat_pricing_model(coupon: @coupon, new_plan: GitHub::Plan.business_plus)
        @plan = GitHub::Plan.business if @per_seat_pricing_model.final_price.zero?
      end

      view = Orgs::SetupView.new(current_user: current_user, plan: GitHub::Plan.find(original_plan_name), organization: @current_organization)
      render "organizations/signup/new", locals: { view: view }
    end
  end

  def destroy
    DeleteToken.verify! current_user, current_organization, params[:dangerzone]

    if current_organization.has_any_trade_restrictions?
      flash[:trade_controls_organization_billing_error] = true
    end

    if current_organization.adminable_by? current_user
      cannot_delete_reason = current_organization.cannot_delete_reason(current_user)
      case cannot_delete_reason
      when :trusted_oauth_apps_owner
        flash[:error] = "#{current_organization.display_login} cannot be deleted. It’s the owner of some trusted applications."
      when :sponsorable
        flash[:error] = "#{current_organization.display_login} cannot be deleted. It has a published Sponsors " \
          "profile that must be unpublished first."
      else
        current_organization.async_destroy(current_user)
        flash[:notice] = "#{current_organization.display_login} is being deleted."
      end
    end
  rescue DeleteToken::DangerZone => danger
    failbot StandardError.new("OrganizationsController.destroy failed - invalid CRSF token")
    GitHub.logger.error({ exception: danger, "code.function": "OrganizationsController.destroy" })
  ensure
    if request.xhr?
      head 200
    else
      redirect_to "/"
    end
  end

  # Updates an organization's public profile.
  def update
    GitHub.context.push(spamurai_form_signals: spamurai_form_signals)

    # Always create a Profile for the Organization if one does not exist.
    # Not doing this causes a race condition when repeatedly calling Organization#find_or_create_profile
    # from the various Organization#profile_...= methods, which can result in ActiveRecord::RecordNotUnique
    # being raised due to duplicate Profile records being created.
    current_organization.find_or_create_profile

    success = T.let(false, T::Boolean)
    notice = T.let(nil, T.nilable(String))
    Organization.transaction do
      params = profile_params
      SocialAccounts::AcceptSocialAccountParameters.call(user: current_organization, params: params)
      params.delete(:profile_social_accounts)

      if success = current_organization.update(params)
        if params.dig(:organization, :achievements_projects_opt_out).present?
          current_organization.
            profile_settings.
            all_private_projects_opted_out_of_achievements_tracking =
            params[:organization][:achievements_projects_opt_out]
        end
      end
    end

    if success
      redirect_to :back, notice: "Profile updated."
    else
      redirect_to :back, flash: { error: current_organization.errors.full_messages.to_sentence }
    end
  end

  private

  def update_billing_information
    # We save the data collection answers and redirect back to the signup page
    redirect_uri = Addressable::URI.parse(request.referrer)
    query_values = redirect_uri.query_values || {}
    query_values[:billing_email] = org_hash[:billing_email] if org_hash[:billing_email].present?

    query_value_key = read_billing_contact? ? "billing_contact" : "account_screening_profile"

    billing_information_hash.each do |key, value|
      query_values["#{query_value_key}[#{key}]"] = value
    end

    query_values["vat_code"] = params[:vat_code] unless params[:vat_code].blank?

    # VAT code is handled in the query values when flag enabled and is not stored on the billing contact.
    user_billing_information_hash = billing_information_hash.dup
    user_billing_information_hash.delete(:vat_code) if current_user.feature_flag_enabled?(:read_billing_information_from_contacts, default: false)
    billing_contact = current_user.billing_contact

    billing_contact.assign_attributes(user_billing_information_hash)
    address_validity_response = billing_contact.validate_address

    if address_validity_response.valid && params["org_exists"] != "true" && github_customer_terms?
      # The billing_address_validated_at needs to be saved in the session here because the organization has _not_ been created yet,
      # and therefore the associated account screening profile / trade screening record does not yet exist.
      # The organization will only be created after the billing information is confirmed to be correct, and not at this stage.
      # Thus, this value will be used later during organization creation.
      #
      # Note that this not applicable to customers on the standard terms of service as the billing information being used
      # already exists on their personal account.
      session[:billing_address_validated_at_org_creation] = billing_contact.address_validated_at
    elsif !address_validity_response.valid
      flash[:address_validation_error] = address_validity_response.error
      q = query_values.except("#{query_value_key}[country_code]") # causes the form to be re-rendered in edit mode because info is missing
      redirect_uri.query_values = q
      return redirect_to redirect_uri.to_s
    end

    redirect_uri.query_values = query_values

    if org_hash[:billing_email].blank?
      flash[:error] = "Billing email has to be provided before proceeding."
    end

    # If the organization being created will be on standard terms of service, then the
    # submit operation should update the current user's billing info since that is what
    # will be used to link to the org.
    if standard_terms_of_service?
      billing_contact.save(context: :individual_trade_screening)
      flash[:error] = "Billing information has to be valid before proceeding." if billing_contact.errors.any?
    else
      if read_billing_contact?
        billing_information_hash.delete(:vat_code)
        billing_information = Billing::Contact.new(billing_information_hash)
        billing_information.customer = Customer.new(name: billing_information.entity_name, vat_code: params[:vat_code])
      else
        billing_information = AccountScreeningProfile.new(billing_information_hash)
      end

      unless billing_information.valid_for_trade_screening?(owner_type: :entity_trade_screening)
        if billing_information.errors.include?(:vat_code)
          # vat_code is not a field on the billing contact, so we need to handle this error separately.
          # Also, since the organization has not been created yet, we cannot call Billing::ContactUpdateStash.stash_update_for
          # as we do for flows where the organization already exists.
          flash[:vat_code_validation_error] = billing_information.errors.full_messages_for(:vat_code).to_sentence
        end

        flash[:error] = "Billing information has to be valid before proceeding."
      end
    end

    redirect_to redirect_uri.to_s
  end

  def add_gh_classroom_csp_exceptions
    SecureHeaders.append_content_security_policy_directives(request, {
      form_action: ["'self'"].concat([GitHub.classroom_host]),
    })
  end

  def orgs_set_return_to
    case params[:return_to]
    when "classroom"
      session[:return_to] = "classroom"
    when "copilot_business_signup"
      session[:return_to] = "copilot_business_signup"
    end
  end

  # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
  def target
    @target ||= current_organization
  end
  # rubocop:enable GitHub/ControllersShouldUseMemoizeForMemoization

  def current_context
    current_organization_for_member_or_billing
  end

  def read_billing_contact?
    return true if FeatureFlag.vexi.enabled?(:read_billing_information_from_contacts, default: false)
    !!target&.feature_flag_enabled?(:read_billing_information_from_contacts, default: false)
  end

  def invite_rate_limited_organization
    current_organization
  end

  def is_paid_plan?
    plan = GitHub::Plan.find(org_hash[:plan]) || GitHub::Plan.default_plan
    plan.paid?
  end

  def org_is_on_business_tos?
    return false unless GitHub.terms_of_service_enabled?
    Organization::TermsOfService::BUSINESS_TERMS_OF_SERVICE_TYPES.include?(params[:terms_of_service_type]&.capitalize)
  end

  def org_is_on_github_customer_tos_with_paid_plan?
    return false unless is_paid_plan?

    params[:terms_of_service_type]&.downcase == "corporate"
  end

  def org_is_on_standard_tos_with_paid_plan?
    return false unless is_paid_plan?

    params[:terms_of_service_type]&.downcase == "standard"
  end

  def couponed_paid_upgrade?
    params[:coupon].present?
  end

  def profile_params
    org_hash.slice(
      :profile_name, :profile_email, :profile_bio, :profile_blog,
      :profile_company, :profile_location, :billing_email, :gravatar_email,
      :profile_social_accounts, :organization_profile_attributes,
    )
  end

  def all_events # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @all_events ||= events_timeline.events(page: 1, per_page: Stratocaster::OrgAllTimeline::INDEX_LENGTH)
  end

  def events_timeline_key
    "org:#{current_organization.id}"
  end

  def publish_payment_method_changed_for(actor:, account:, payment_method:)
    GlobalInstrumenter.instrument(
      "billing.payment_method.addition",
      actor_id: actor.id,
      account_id: account.id,
      payment_method_id: payment_method.id,
    )
  end

  def require_plan_selection
    # Users coming from `https://classroom.github.com/` can only see the new form for free plan
    return org_plan_path if params[:return_to] == "classroom"

    GitHub.logger.info({
      "code.function": "require_plan_selection",
      "enduser.id": current_user,
      "gh.org_transform": helpers.org_transform?,
      "gh.billing_enabled": GitHub.billing_enabled?,
      "gh.enduser.trade_restrictions": current_user.has_any_trade_restrictions?,
      "gh.org.plan": params[:plan],
    })

    return if helpers.org_transform? || !GitHub.billing_enabled?
    # Have to choose plan first in redesigned flow
    # OFAC sanctioned users can only see the new form for free plan

    redirect_to(org_plan_path(utm_memo)) if !params[:plan] || (current_user.has_any_trade_restrictions? && [GitHub::Plan.free.name, GitHub::Plan::TEAM_FREE_PLAN_NAME].exclude?(params[:plan]))
  end

  def move_work_session
    session[:move_work] ||= {}
  end
end
