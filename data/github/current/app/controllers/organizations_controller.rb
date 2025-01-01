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

  before_action :login_required, except: :transforming
  before_action :check_trade_compliance, only: %w(new create), if: :couponed_paid_upgrade?
  before_action only: :transform do
    T.bind(self, OrganizationsController)
    check_trade_compliance(redirect_url: settings_organizations_url)
  end
  before_action :org_members_only, except: %w(
    show new create transform transforming
  )
  before_action :org_admins_only, except: %w(
    create destroy new
    show transform transforming
  )
  before_action :validate_update_params, only: :update
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

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    only: [:transforming]

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
    return redirect_to "/" if current_organization.nil?

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
    if current_user.has_any_trade_restrictions? &&
        [GitHub::Plan.business.name, GitHub::Plan.business_plus.name].include?(params[:plan])
      return redirect_to org_plan_path
    end

    has_sdn_restrictions = if [GitHub::Plan.free.name, GitHub::Plan::TEAM_FREE_PLAN_NAME].include?(params[:plan])
      current_user.has_commercial_interaction_restriction?(feature_type: :free_org_creation)
    else
      current_user.has_commercial_interaction_restriction?
    end

    if has_sdn_restrictions
      return render "orgs/restricted_org_notice", locals: {
        target: current_user,
        header_view: nil,
        selected_nav_item: nil
      }
    end

    if GitHub.billing_enabled? && params[:plan] == GitHub::Plan.business_plus.name
      return redirect_to enterprise_trial_accounts_new_path
    end

    @coupon = Coupon.find_by_code(params[:coupon]) if params[:coupon]

    if @coupon && @coupon.plan
      @plan = @coupon.plan
    else
      @plan = GitHub::Plan.find(params[:plan]) || GitHub::Plan.default_plan
    end

    if @coupon && @coupon.user_only?
      return redirect_to redeem_coupon_url(@coupon.code)
    end

    # Prevent transform when sponsoring
    if org_transform?
      error = if current_user.has_a_plan_specific_coupon?
        "You cannot transform this account into an organization because you have an active coupon that is locked to a plan. Please contact support."
      elsif current_user.active_sponsors_account?
        "You cannot transform this account into an organization because you have an active GitHub Sponsors account."
      elsif current_user.actively_sponsoring?
        "You cannot transform this account into an organization because active sponsorships must be cancelled first."
      end

      if error
        flash[:error] = error
        return redirect_to(settings_organizations_url)
      end
    end

    @current_organization = Organization.new(
      plan: @plan.name,
      coupon: @coupon,
      login: params[:login],
      billing_email: params[:billing_email],
      company_name: params[:organization].present? ? org_hash[:company_name] : nil,
    )
    if org_transform?
      @current_organization.login = current_user.login # rubocop:disable GitHub/DoNotAllowLogin shouldn't be changed since there's already a method to build `display_login` from `login`
      @current_organization.billing_email = current_user.billing_email
    end

    if GitHub.billing_enabled?
      if @current_organization.coupon
        @current_organization.plan = @current_organization.best_plan_for_coupon.to_s
      end

      if org_transform?
        @current_organization.seats = current_user.default_seats

        if current_user.coupon.present? && !current_user.coupon.user_only?
          @current_organization.coupon = current_user.coupon
          @current_organization.plan = @current_organization.best_plan_for_coupon.to_s
        end

        if @current_organization.plan.repos < current_user.owned_private_repositories.count
          @current_organization.plan = GitHub::Plan.org_plans.detect do |available|
            available.repos > current_user.owned_private_repositories.count
          end
        end
      end

      @monthly_per_seat_pricing_model = per_seat_pricing_model(coupon: @coupon, duration: "month")
      @annual_per_seat_pricing_model = per_seat_pricing_model(coupon: @coupon, duration: "year")
      @per_seat_pricing_model = per_seat_pricing_model(coupon: @coupon)
      @monthly_business_plus_pricing_model = per_seat_pricing_model(coupon: @coupon, new_plan: GitHub::Plan.business_plus, duration: "month")
      @annual_business_plus_pricing_model = per_seat_pricing_model(coupon: @coupon, new_plan: GitHub::Plan.business_plus, duration: "year")
      @business_plus_pricing_model = per_seat_pricing_model(coupon: @coupon, new_plan: GitHub::Plan.business_plus)

      # NB: If you are on a 100% off coupon the business plan could be
      # a default plan option. However, we also don't want to set it
      # if the coupon has a specific plan already associated.
      #
      # see https://github.com/github/github/commit/67d6809b7fd0219cccf8ddc646eb466da12bef28
      if @per_seat_pricing_model.final_price.zero? && !@coupon.try(:plan_specific?)
        @plan = GitHub::Plan.business
      end
    end

    if GitHub.billing_enabled? && params[:plan] == GitHub::Plan.business_plus.name
      view = Orgs::SetupView.new(current_user: current_user, plan: @plan, organization: @current_organization)
      if params[:ref_page] == "/move_work/organization/plans"
        render "move_work/organizations/new", locals: {
          progressbar_value: 40,
          view: view,
          current_context: current_user
        }
      else
        render "organizations/signup/new", locals: { view: view }
      end
    else
      if org_transform?
        if current_user.feature_enabled?(:data_collection_user_to_org_transform)
          view = Orgs::CreationView.new({
            admin_logins: params[:organization].present? ? org_hash[:admin_logins] : [],
            coupon: @coupon,
            current_user: current_user,
            plan: @plan,
            organization: @current_organization,
            org_transform: true,
            org_transform_steps_complete: params[:org_transform_steps_complete],
            terms_of_service: params[:terms_of_service_type],
          })
          return render "organizations/transform/org_transform_new_design", locals: { view: view }
        end
        render "organizations/transform/org_transform"
      else
        view = Orgs::SetupView.new(current_user: current_user, plan: @plan, organization: @current_organization)
        if params[:ref_page] == "/move_work/organization/plans"
          render "move_work/organizations/new", locals: {
            progressbar_value: 40,
            view: view,
            current_context: current_user
          }
        else
          render "organizations/signup/new", locals: { view: view }
        end
      end
    end
  end

  # Creates a fresh organization.
  def create
    if account_screening_profile_hash.present? && params[:billing].blank?
      # If the data collection form is present and the user is not submitting payment info,
      # then this is a billing info update submit operation.

      # We save the data collection answers and redirect back to the signup page
      redirect_uri = Addressable::URI.parse(request.referrer)
      query_values = redirect_uri.query_values || {}
      query_values[:billing_email] = org_hash[:billing_email] if org_hash[:billing_email].present?

      account_screening_profile_hash.each do |key, value|
        query_values["account_screening_profile[#{key}]"] = value
      end

      screening_record = current_user.trade_screening_record
      merged_attrs = account_screening_profile_hash.merge(metadata: screening_record.metadata.merge(screening_context: "new_org_creation"))
      screening_record.assign_attributes(merged_attrs)
      address_validity_response = screening_record.validate_billing_information_for_tax

      if address_validity_response.valid && params["org_exists"] != "true" && github_customer_terms?
        # The billing_address_validated_at needs to be saved in the session here because the organization has _not_ been created yet,
        # and therefore the associated account screening profile / trade screening record does not yet exist.
        # The organization will only be created after the billing information is confirmed to be correct, and not at this stage.
        # Thus, this value will be used later during organization creation.
        #
        # Note that this not applicable to customers on the standard terms of service as the billing information being used
        # already exists on their personal account.
        session[:billing_address_validated_at_org_creation] = screening_record.billing_address_validated_at
      elsif !address_validity_response.valid
        flash[:address_validation_error] = address_validity_response.error
        q = query_values.except("account_screening_profile[country_code]") # causes the form to be re-rendered in edit mode because info is missing
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
        screening_record.save
        flash[:error] = "Billing information has to be valid before proceeding." if screening_record.errors.any?
      else
        profile = AccountScreeningProfile.new(account_screening_profile_hash)
        flash[:error] = "Billing information has to be valid before proceeding." if profile.invalid?(:entity)
      end

      return redirect_to redirect_uri.to_s
    end

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
    if billing_address_validated_at.present? && account_screening_profile_hash.present?
      account_screening_profile_hash.merge!(billing_address_validated_at:)
      session.delete(:billing_address_validated_at_org_creation)
    elsif github_customer_terms? && account_screening_profile_hash.present? && account_screening_profile_hash[:country_code] == "US"
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
                                           trade_screening_info: account_screening_profile_hash)

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

  # Transforms the currently logged in user into an
  # organization. Yikes.
  def transform # rubocop:todo GitHub/UseRestfulActions
    GitHub.dogstats.increment("organization", tags: ["action:transform"])

    if current_user.is_enterprise_managed?
      flash[:error] = "You cannot transform this account into an organization because this account is managed by your enterprise."
      return redirect_to settings_organizations_url
    end

    # Prevent transforms for plan specific coupons
    if current_user.has_a_plan_specific_coupon?
      flash[:error] = "You cannot transform this account into an organization because you have an active coupon that is locked to a plan. Please contact support."
      return redirect_to settings_organizations_url
    end

    # Prevent transform when sponsoring
    if current_user.actively_sponsoring?
      flash[:error] = "You cannot transform this account into an organization because active sponsorships must be " \
        "cancelled first."
      return redirect_to settings_organizations_url
    end

    if current_user.active_sponsors_account?
      flash[:error] = "You cannot transform this account into an organization because you have an active GitHub Sponsors account."
      return redirect_to settings_organizations_url
    end

    if params[:org_transform_steps_complete].present? && params[:org_transform_steps_complete] != "true"
      return redirect_to action: :new,
        transform_user: 1,
        org_transform_steps_complete: params[:org_transform_steps_complete],
        terms_of_service_type: params[:terms_of_service_type],
        organization: params[:organization].present? ? { company_name: params[:organization][:company_name], admin_logins: params[:organization][:admin_logins] || [] } : nil
    end

    # First convert the array of string user names into user objects.
    if !params[:organization]
      flash.now[:error] = "No owners or emails were submitted."
      return new
    end

    if current_user.organizations.any?
      flash[:error] = "You cannot transform this account into an organization before leaving all other organizations first."
      return redirect_to settings_organizations_url
    end

    if GitHub.billing_enabled?
      plan = org_hash[:plan] ||= params[:plan]
      unless GitHub::Plan.find(plan).try(:org_plan_or_per_seat?)
        flash.now[:error] = "Please choose a valid plan."
        return new
      end
    else
      plan = org_hash[:plan] = "enterprise"
    end

    if has_payment_details?
      if current_user.has_billing_record?
        result = GitHub::Billing.update_payment_method(current_user, payment_details)
      else
        result = GitHub::Billing.create_customer(current_user, payment_details, actor: current_user)
      end
      unless result.success?
        flash[:error] = result.error_message.to_s
        return new
      end
    end

    org_hash.delete(:login)
    admin_logins = org_hash.delete(:admin_logins) || []
    owner        = User.find_by_login(admin_logins.first) if admin_logins.any?
    org          = Organization.new(org_hash)

    old_seats_count = owner&.seats
    old_plan_name = owner&.plan&.name

    # Prevent transforming the org when the owner would be someone who has blocked the current user
    # See: https://github.com/github/search-and-flywheel/issues/222
    if current_user.blocked_by?(owner)
      # Message should be generic so we don't reveal the current user is blocked by the submitted owner
      flash[:error] = "You cannot transform this account into an organization right now."
      return redirect_to settings_organizations_url
    end

    if !current_user.needs_valid_payment_method_to_switch_to_plan?(plan)
      Organization.transform(current_user, owner, org_hash.to_hash)
      publish_billing_plan_changed_for(
        actor: current_user,
        user: owner,
        old_seat_count: old_seats_count,
        new_seat_count: org.seats,
        old_plan_name: old_plan_name,
        new_plan_name: plan,
      )
      reset_session
      cookies[:org_transform_notice] = { value: Base64.strict_encode64("Please sign in as #{owner.display_login}, the owner of your new #{current_user.safe_profile_name} organization."),
                                         expires: 1.hour.from_now, secure: request && request.ssl?, domain: cookie_domain }
      render "organizations/transform/transforming"
    else
      @current_organization = org
      flash[:error] = "Please provide a credit card to switch to the #{plan.capitalize} plan."
      new
    end
  rescue Organization::TransformationFailed => e
    flash.now[:error] = e.to_s
    new
  end

  # Responds to the poll-include-fragment element ajax request, indicating
  # whether the user is currently transforming or not.
  def transforming # rubocop:todo GitHub/UseRestfulActions
    user = User.find_by_login(params[:user])
    return head 404 if user.nil?

    if Organization.transforming?(user)
      head 202
    else
      head 200
    end
  end

  # Updates an organization's public profile.
  def update
    GitHub.context.push(spamurai_form_signals: spamurai_form_signals)

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

        notice = if org_hash.key?(:granular_repo_creation_permissions_changing)
          enabled = current_organization.allow_members_can_create_repositories_with_visibilities(actor: current_user,
            public_visibility: public_creation_allowed?,
            private_visibility: org_hash[:members_can_create_private_repositories] == "1",
            internal_visibility: org_hash[:members_can_create_internal_repositories] == "1")
          if enabled.length > 0
            "Members can now create #{to_sentence(enabled)} repositories."
          else
            "Members can no longer create #{available_repo_types_to_sentence("or")} repositories."
          end
        else
          "Profile updated."
        end
      end
    end

    if success
      redirect_to :back, notice: notice
    else
      redirect_to :back, flash: { error: current_organization.errors.full_messages.to_sentence }
    end
  end

  private

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

  def invite_rate_limited_organization
    current_organization
  end

  def public_creation_allowed?
    # Ensure we set a valid value, preventing private-only policies for free/team orgs
    # regardless of any client-side shenanigans.
    if current_organization.can_restrict_only_public_repo_creation?
      org_hash[:members_can_create_public_repositories] == "1"
    else
      org_hash[:members_can_create_public_repositories] == "1" || org_hash[:members_can_create_private_repositories] == "1"
    end
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

  def validate_update_params
    if org_hash.key?(:members_can_create_repositories)
      unless %w[1 0 all none private].include?(org_hash[:members_can_create_repositories]&.to_s)
        redirect_to :back, flash: { error: "Invalid value given, unable to update the repository creation setting." }
      end
    end
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
      "gh.org_transform": org_transform?,
      "gh.billing_enabled": GitHub.billing_enabled?,
      "gh.enduser.trade_restrictions": current_user.has_any_trade_restrictions?,
      "gh.org.plan": params[:plan],
    })

    return if org_transform? || !GitHub.billing_enabled?
    # Have to choose plan first in redesigned flow
    # OFAC sanctioned users can only see the new form for free plan

    redirect_to(org_plan_path(utm_memo)) if !params[:plan] || (current_user.has_any_trade_restrictions? && [GitHub::Plan.free.name, GitHub::Plan::TEAM_FREE_PLAN_NAME].exclude?(params[:plan]))
  end

  def available_repo_types_to_sentence(conjunction = "and")
    types = %w[public private]
    types.append("internal") if current_organization.supports_internal_repositories?
    to_sentence(types, conjunction)
  end

  def move_work_session
    session[:move_work] ||= {}
  end

  def to_sentence(items, conjunction = "and")
    return items.first if items.length == 1
    list = items[0..-2].join(", ")
    list += "," if items.length > 2 # Oxford commas keep it classy
    list += " #{conjunction} "
    list += items.last
  end
end
