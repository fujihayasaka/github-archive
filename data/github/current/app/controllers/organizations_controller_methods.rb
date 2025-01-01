# typed: true
# frozen_string_literal: true

module OrganizationsControllerMethods
  extend ActiveSupport::Concern
  extend T::Helpers
  include GitHub::Memoizer

  requires_ancestor { ApplicationController }

  private

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
        :members_can_create_internal_repositories, :seats, :company_name,
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

      send_and_setup_trial_notifications(cloud_trial, organization, current_user)

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

  def send_and_setup_trial_notifications(trial, organization, user)
    send_welcome_email_for_enterprise_cloud_trial(user, organization)

    deliver_end_email_at = (trial.expires_on - 1.day).to_datetime
    send_delayed_end_enterprise_cloud_trial_email(user, organization, deliver_end_email_at)
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

  def billing_params(params)
    params.permit \
    :first_name,
    :last_name,
    :middle_name,
    :region,
    :city,
    :country_code,
    :postal_code,
    :address1,
    :address2,
    :entity_name,
    :vat_code
  end

  def billing_information_params
    if params[:billing_contact].present?
      billing_params(params.require(:billing_contact))
    else
      billing_params(params.require(:account_screening_profile))
    end
  end

  memoize def billing_information_hash
    return nil unless params[:account_screening_profile].present? || params[:billing_contact].present?
    billing_information_params.to_h
  end

  def require_signup_flow_redesign
    render_404 unless GitHub.billing_enabled?
  end

  # Unfortunately complex code for responding from both OrganizationsController#new and
  # Orgs::TransformationsController#create.
  def render_new_organization
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
    if helpers.org_transform?
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
    if helpers.org_transform?
      @current_organization.login = current_user.login # rubocop:disable GitHub/DoNotAllowLogin shouldn't be changed since there's already a method to build `display_login` from `login`
      @current_organization.billing_email = current_user.billing_email
    end

    if GitHub.billing_enabled?
      if @current_organization.coupon
        @current_organization.plan = @current_organization.best_plan_for_coupon.to_s
      end

      if helpers.org_transform?
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
      if helpers.org_transform?
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
end
