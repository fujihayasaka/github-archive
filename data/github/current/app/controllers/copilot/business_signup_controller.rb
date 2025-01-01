# typed: true
# frozen_string_literal: true

class Copilot::BusinessSignupController < ApplicationController
  include TradeControlsHelper

  before_action :login_required
  before_action :dotcom_required
  before_action :add_paypal_csp_exceptions, only: [:organization_payment, :enterprise_payment]
  before_action :require_organization, only: [
    :organization_payment,
    :organization_policy,
    :organization_signup,
    :organization_seat_management
  ]
  before_action :require_enterprise, only: [
    :enterprise_payment,
    :enterprise_policy,
    :enterprise_seat_management
  ]

  before_action only: :organization_signup do
    T.bind(self, Copilot::BusinessSignupController)
    check_trade_compliance(target: this_organization, sdn_redirect: true)
  end

  before_action except: :organization_signup do
    T.bind(self, Copilot::BusinessSignupController)
    check_trade_compliance(target: this_organization)
  end

  include Site::PreserveTrackingParamsDependency
  include Site::MicrosoftAnalyticsDependency
  before_action :allow_initial_cookie_consent
  before_action :enable_microsoft_analytics
  before_action :add_microsoft_analytics_csp_exceptions
  layout "layouts/copilot_business"

  stylesheet_bundle :copilot
  javascript_bundle :copilot
  javascript_bundle :billing

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Copilot,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Ballast,
    only: [
      :new,
      :choose_organization,
      :choose_enterprise,
      :choose_business_type,
      :organization_payment,
      :enterprise_payment,
      :organization_policy,
      :enterprise_policy,
      :signup_completion,
      :organization_seat_management,
      :enterprise_seat_management
    ]

  def new
    redirect_to_with_tracking_params copilot_plan_purchase_path and return if current_user.feature_enabled?(:copilot_purchase_flow_refresh)

    redirect_to_with_tracking_params copilot_business_signup_choose_business_type_path
  end

  def choose_business_type # rubocop:todo GitHub/UseRestfulActions
    redirect_to_with_tracking_params copilot_plan_purchase_path and return if current_user.feature_enabled?(:copilot_purchase_flow_refresh)

    unless current_user_is_enterprise_or_org_admin?
      return_to_path = preserve_tracking_params_path(copilot_business_signup_path)
      render "copilot/business_signup_must_be_admin", locals: {
        new_organization_signup_href: preserve_tracking_params_path(new_organization_path, return_to: return_to_path),
        contact_sales_team_href: preserve_tracking_params_path(enterprise_contact_path),
        copilot_settings_href: preserve_tracking_params_path(copilot_settings_path),
      }
      return
    end

    if !params[:business]
      render "copilot/business_signup_choose_business_type", locals: {
        form_submission_path: preserve_tracking_params_path(copilot_business_signup_choose_business_type_path),
        has_eligible_enterprises: enterprises_eligible_for_first_run_flow.any?
      }
    elsif params[:business] == "enterprise"
      redirect_to_with_tracking_params copilot_business_signup_choose_enterprise_path
    elsif params[:business] == "organization"
      redirect_to_with_tracking_params copilot_business_signup_choose_organization_path
    else
      redirect_to_with_tracking_params copilot_business_signup_path
    end
  end

  def choose_organization # rubocop:todo GitHub/UseRestfulActions
    redirect_to_with_tracking_params copilot_plan_purchase_path, priority: "organization" and return if current_user.feature_enabled?(:copilot_purchase_flow_refresh)

    already_signed_up_orgs = []
    available_organizations_for_signup = []

    current_user.organizations.each do |org|
      next unless org_eligible_for_first_run_flow?(org)
      copilot_org = Copilot::Organization.new(org)
      if copilot_org.has_trial? && copilot_org.copilot_billable?
        already_signed_up_orgs << org
      elsif copilot_org.has_trial?
        # if an org is on trial and does not have a valid payment method, they can go through the purchase flow
        available_organizations_for_signup << org
      elsif copilot_org.copilot_enabled?
        already_signed_up_orgs << org
      else
        available_organizations_for_signup << org
      end
    end

    render "copilot/business_signup_choose_organization", locals: {
      available_organizations: available_organizations_for_signup,
      already_signed_up_organizations: already_signed_up_orgs
    }
  end

  def choose_enterprise # rubocop:todo GitHub/UseRestfulActions
    redirect_to_with_tracking_params copilot_plan_purchase_path, priority: "business" and return if current_user.feature_enabled?(:copilot_purchase_flow_refresh)

    already_signed_up_enterprises, other_enterprises = enterprises_eligible_for_first_run_flow.partition do |enterprise|
      Copilot::Business.new(enterprise).copilot_enabled_organizations_count > 0 && !all_copilot_enabled_organizations_on_cb_trial?(enterprise)
    end

    trial_enterprises, available_enterprises = other_enterprises.partition(&:trial?)

    if available_enterprises.empty? && already_signed_up_enterprises.empty?
      render "copilot/business_signup_no_eligible_enterprise", locals: {
        trial_enterprises: trial_enterprises
      }
    else
      render "copilot/business_signup_choose_enterprise", locals: {
        available_enterprises: available_enterprises,
        already_signed_up_enterprises: already_signed_up_enterprises
      }
    end
  end

  def organization_payment # rubocop:todo GitHub/UseRestfulActions
    # If we're redirected here from creating a new organization, clear the redirect session key
    session.delete(:return_to) if session[:return_to] == "copilot_business_signup"

    redirect_to_with_tracking_params copilot_plan_purchase_path, organization: params[:org] and return if current_user.feature_enabled?(:copilot_purchase_flow_refresh)

    if session[:copilot_flash_create_org_message].present?
      flash[:copilot_notice_message] = "Your organization #{this_organization.display_login} has been successfully created! If you don't want Copilot, you can skip this and go to your new organization."
      session.delete(:copilot_flash_create_org_message)
      GlobalInstrumenter.instrument(
        "analytics.event",
        category: "new_org_copilot_add_on",
        action: "create_free_org_success",
        label: "flash_message:organization_created_successfully;",
      )
    end

    return render_404 unless org_eligible_for_first_run_flow?(this_organization)

    if this_organization.is_organization_billed_through_business?
      return render "copilot/business_signup_organization_contact_enterprise_admin", locals: { organization: this_organization }
    end

    if this_organization.plan.legacy?
      return render "copilot/business_signup_organization_legacy_plan", locals: { organization: this_organization }
    end

    return render_404 unless org_available_for_signup?(this_organization)

    if this_organization.invoiced? || this_organization.metered_via_azure?
      return render_404 unless copilot_organization.copilot_billable?

      copilot_organization.enable_copilot!(current_user)
      CopilotForBusinessMailer.cfb_enabled(this_organization).deliver_later
      return redirect_to_with_tracking_params copilot_business_signup_organization_policy_path, org: this_organization
    end

    render "copilot/business_signup_organization_payment", locals: {
      organization: this_organization,
      show_billing_info_prompt: show_billing_info_prompt?,
    }
  end

  def enterprise_payment # rubocop:todo GitHub/UseRestfulActions
    redirect_to_with_tracking_params copilot_plan_purchase_path, enterprise: params[:enterprise] and return if current_user.feature_enabled?(:copilot_purchase_flow_refresh)

    if enterprise_eligible_for_first_run_flow?(this_enterprise) && this_enterprise.trial?
      return render "copilot/business_signup_require_paid_enterprise_account", locals: { enterprise: this_enterprise }
    end

    force_sales_serve = enterprise_must_sales_serve_copilot?(this_enterprise)

    return render_404 if !enterprise_available_for_signup?(this_enterprise) && !force_sales_serve

    # If the enterprise is invoiced and manages its payments via GitHub, we don't
    # need to confirm payment details and can go straight to the policy page
    if !this_enterprise.eligible_for_self_serve_payment? && !force_sales_serve
      return redirect_to_with_tracking_params copilot_business_signup_enterprise_policy_path, enterprise: this_enterprise
    end

    render "copilot/business_signup_enterprise_payment", locals: {
      enterprise: this_enterprise,
      force_sales_serve: force_sales_serve
    }
  end

  def organization_policy # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless copilot_organization.copilot_enabled?

    redirect_to_with_tracking_params copilot_plan_purchase_path, organization: params[:org] and return if current_user.feature_enabled?(:copilot_purchase_flow_refresh)

    if copilot_organization.has_trial?
      return redirect_to_with_tracking_params copilot_business_signup_completion_path, business_type: "org", org: this_organization, **utm_memo
    end

    render "copilot/business_signup_policy", locals: {
      configurable: this_organization,
      default_suggestions_policy: default_policy_menu_item(copilot_organization.snippy_setting),
      default_chat_policy: "enabled",
      default_cli_policy: "unconfigured",
      business_type: "organization",
      submit_path: settings_org_copilot_policies_update_path(this_organization.display_login),
      return_to: preserve_tracking_params_path(copilot_business_signup_organization_seat_management_path, org: this_organization, **utm_memo)
    }
  end

  def organization_seat_management # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless copilot_organization.copilot_enabled?

    redirect_to_with_tracking_params copilot_plan_purchase_path, organization: params[:org] and return if current_user.feature_enabled?(:copilot_purchase_flow_refresh)

    page = 1
    if params[:page].present?
      page = params[:page].to_i
      show_user_list = true
    end
    query_params = Copilot::SeatManagement::SeatQuery.new

    render "copilot/business_signup_organization_seat_management", locals: { organization: this_organization, page: page, query_params: query_params, per_page: 1, show_user_list: show_user_list }
  end

  def enterprise_policy # rubocop:todo GitHub/UseRestfulActions
    redirect_to_with_tracking_params copilot_plan_purchase_path, enterprise: params[:enterprise] and return if current_user.feature_enabled?(:copilot_purchase_flow_refresh)

    snippy_setting = Copilot::Business.new(this_enterprise).snippy_setting

    render "copilot/business_signup_policy", locals: {
      configurable: this_enterprise,
      default_suggestions_policy: default_policy_menu_item(snippy_setting),
      default_chat_policy: "enabled",
      default_cli_policy: "unconfigured",
      business_type: "enterprise",
      submit_path: update_settings_copilot_policy_enterprise_path(this_enterprise.display_login),
      return_to: preserve_tracking_params_path(copilot_business_signup_enterprise_seat_management_path, enterprise: this_enterprise, **utm_memo)
    }
  end

  def organization_signup # rubocop:todo GitHub/UseRestfulActions
    redirect_to_with_tracking_params copilot_plan_purchase_path, organization: params[:org] and return if current_user.feature_enabled?(:copilot_purchase_flow_refresh)

    if !org_available_for_signup?(this_organization)
      GitHub.logger.info(
        "Cannot sign up organization to CB, not eligible",
        "gh.org.id" => this_organization.id,
      )
      return render "copilot/business_signup_organization_cannot_signup", locals: {
        organization: this_organization,
        recommendation: "contact GitHub Support"
      }
    end

    if !copilot_organization.copilot_billable?
      result = this_organization.metered_services_billable?(commercial_restriction_feature_type: :copilot)
      GitHub.logger.info(
        "Cannot sign up organization to CB, not billable",
        "gh.org.id" => this_organization.id,
        "gh.copilot.metered_services_billable" => result[:billable],
        "gh.copilot.metered_services_billable.reason" => result[:reason]
      )
      return render "copilot/business_signup_organization_cannot_signup", locals: {
        organization: this_organization,
        recommendation: "update your payment details"
      }
    end
    url_options = { host: GitHub.admin_host_name, protocol: "https" }
    staff_url = stafftools_user_copilot_settings_url(this_organization, **url_options)
    blocked = copilot_organization.block_if_sharing_payment_method_with_other_blocked_users!

    if blocked
      copilot_organization.send_abuse_notification(
        url: staff_url,
        signed_up: false,
      )

      return render "copilot/business_signup_organization_cannot_signup", locals: {
        organization: this_organization,
        recommendation: "contact GitHub Support"
      }
    end

    if copilot_organization.shares_payment_method_with_blocked_user?
      copilot_organization.send_abuse_notification(
        url: staff_url,
        signed_up: true,
      )
    end

    copilot_organization.enable_copilot!(current_user)
    copilot_organization.schedule_auth_and_capture!(reason: "signup")

    # If the org is untrusted (e.g. on the neutral or untrusted trust tier), we'll schedule another capture to be performed
    # when the first token is generated
    is_untrusted = TrustTiers::Tier.for_billable_owner(this_organization).tier >= TrustTiers::Tier::NEUTRAL
    copilot_organization.schedule_auth_and_capture!(reason: "first token", pending_token: true) if is_untrusted

    CopilotForBusinessMailer.cfb_enabled(this_organization).deliver_later
    redirect_to_with_tracking_params copilot_business_signup_organization_policy_path, org: this_organization
  end

  def enterprise_seat_management # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless enterprise_available_for_signup?(this_enterprise)

    redirect_to_with_tracking_params copilot_plan_purchase_path, enterprise: params[:enterprise] and return if current_user.feature_enabled?(:copilot_purchase_flow_refresh)

    copilot_business = Copilot::Business.new(this_enterprise)

    page = params[:page] || 1
    paginated_orgs = copilot_business.business_object.organizations.paginate(page: page, per_page: 10).to_a

    render "copilot/business_signup_enterprise_seat_management", locals: {
      copilot_business: copilot_business,
      organizations: paginated_orgs,
      enabled_count: copilot_business.copilot_enabled_organizations_count,
      show_org_list: params[:page].present?
    }
  end

  def signup_completion # rubocop:todo GitHub/UseRestfulActions
    is_org = params[:business_type] == "org"
    is_enterprise = params[:business_type] == "enterprise"

    redirect_to_with_tracking_params copilot_plan_purchase_path, priority: is_org ? "organization" : "enterprise" and return if current_user.feature_enabled?(:copilot_purchase_flow_refresh)

    if is_org
      # We don't check this for enterprises because selecting zero orgs in the flow would
      # prevent you from seeing the completion page otherwise
      return render_404 unless this_organization && copilot_organization.copilot_enabled?
    elsif is_enterprise
      return render_404 unless this_enterprise.present?
    else
      return render_404
    end

    copilot_seat_count, total_seat_count, policy = if is_org
      copilot_seat_count = Copilot::SeatAssignment.for_organization(this_organization).count
      total_seat_count = this_organization.members_count
      policy = snippy_policy_string(copilot_organization.copilot_snippy_setting)
      [copilot_seat_count, total_seat_count, policy]
    elsif is_enterprise
      copilot_business = Copilot::Business.new(this_enterprise)
      copilot_seat_count = copilot_business.copilot_enabled_organizations_count
      total_seat_count = this_enterprise.organizations.count
      policy = snippy_policy_string(copilot_business.copilot_snippy_setting)
      [copilot_seat_count, total_seat_count, policy]
    end

    render "copilot/business_signup_completion", locals: {
      is_org: is_org,
      is_enterprise: is_enterprise,
      copilot_seat_count: copilot_seat_count,
      total_seat_count: total_seat_count,
      policy: policy,
      this_enterprise: this_enterprise,
      this_organization: this_organization,
      microsoft_analytics_order_id: microsoft_analytics_order_id
    }
  end

  private

  def show_billing_info_prompt?
    return false if this_organization.org_is_on_standard_tos?

    !this_organization.has_saved_trade_screening_record?
  end

  def default_policy_menu_item(snippy_setting)
    settings_to_menu_items = {
      "disabled" => "allowed",
      "enabled" => "blocked"
    }

    settings_to_menu_items[snippy_setting] || snippy_setting
  end

  memoize def enterprises_eligible_for_first_run_flow
    current_user.businesses.select do |business|
      enterprise_eligible_for_first_run_flow?(business)
    end
  end

  def already_signed_up_enterprises
    current_user.businesses.select do |enterprise|
      # An enterprise is considered signed up if at least one of its orgs has
      # copilot enabled
      enterprise.adminable_by?(current_user) && Copilot::Business.new(enterprise).copilot_enabled_organizations_count > 0
    end
  end

  def enterprise_eligible_for_first_run_flow?(enterprise)
    enterprise.adminable_by?(current_user) &&
    (enterprise.has_valid_payment_method? || enterprise.invoiced?) &&
    enterprise.zuora_account?
  end

  def enterprise_available_for_signup?(enterprise)
    enterprise_eligible_for_first_run_flow?(enterprise) &&
    !enterprise.trial? &&
    !enterprise_must_sales_serve_copilot?(enterprise) &&
    (Copilot::Business.new(enterprise).copilot_enabled_organizations_count == 0 || all_copilot_enabled_organizations_on_cb_trial?(enterprise))
  end

  # If an enterprise has an active enterprise agreement but isn't billed via Azure Subscription,
  # we cannot take them through the self-serve flow
  def enterprise_must_sales_serve_copilot?(enterprise)
    return false unless enterprise.enterprise_agreements.where(status: "active").count > 0
    enterprise.customer.present? && enterprise.customer.azure_subscription_id.nil?
  end

  def snippy_policy_string(snippy_policy)
    case snippy_policy
    when :SNIPPY_DISABLED then "Suggestions matching public code allowed"
    when :SNIPPY_ENABLED then "Suggestions matching public code blocked"
    else
      "No policy"
    end
  end

  def add_paypal_csp_exceptions
    paypal_csp_exceptions = {
      img_src: [GitHub.paypal_checkout_url],
      connect_src: [GitHub.braintreegateway_url, GitHub.braintree_analytics_url]
    }
    SecureHeaders.append_content_security_policy_directives(request, paypal_csp_exceptions)
  end

  # Organizations that can appear in the "choose organization" list
  def org_eligible_for_first_run_flow?(org)
    org.adminable_by?(current_user)
  end

  # Organizations that can have Copilot enabled for them via this self-serve flow
  # Organizations on Copilot Business trial can also purchase Copilot Business
  def org_available_for_signup?(org)
    return false unless org_eligible_for_first_run_flow?(org)
    return false if org.is_organization_billed_through_business?
    return false if org.plan.legacy?
    copilot_org = Copilot::Organization.new(org)
    !copilot_org.copilot_enabled? || copilot_org.has_trial?
  end

  def require_enterprise
    render_404 unless this_enterprise
  end

  def require_organization
    render_404 unless this_organization
  end

  def current_user_is_enterprise_or_org_admin?
    return true if current_user.businesses.any? do |enterprise|
      enterprise.adminable_by?(current_user)
    end

    current_user.organizations.any? do |org|
      org.adminable_by?(current_user)
    end
  end

  def target_for_conditional_access
    # This is safe due to :login_required, :require_enterprise, :require_organization
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  def resource_for_conditional_access
    return self unless logged_in?
    return this_organization if CAP_ORG_ACTIONS.include?(action_name) && this_organization.present?
    return this_enterprise if CAP_ENT_ACTIONS.include?(action_name) && this_enterprise.present?

    current_user
  end

  CAP_ORG_ACTIONS = %w[organization_payment organization_policy organization_signup organization_seat_management].freeze
  CAP_ENT_ACTIONS = %w[enterprise_payment enterprise_policy enterprise_seat_management].freeze

  memoize def this_organization
    current_user.organizations.find_by_login(params[:org])
  end

  memoize def this_enterprise
    current_user.businesses(membership_type: :admin)
      .find_by_slug(params[:enterprise])
  end

  sig { returns Copilot::Organization }
  memoize def copilot_organization
    Copilot::Organization.new(this_organization)
  end

  def redirect_to_with_tracking_params(to_path, additional_params = {})
    redirect_to preserve_tracking_params_path(to_path, additional_params)
  end

  def utm_memo
    session[:utm_memo] || {}
  end

  def microsoft_analytics_order_id
    is_org = params[:business_type] == "org"
    business_name = is_org ? params[:org] : params[:enterprise]
    timestamp = Time.now.strftime("%m%d") # month, day
    Digest::SHA256.hexdigest("#{timestamp}-#{params[:business_type]}-#{business_name}")
  end

  def all_copilot_enabled_organizations_on_cb_trial?(enterprise)
    Copilot::Business.new(enterprise).copilot_enabled_organizations.all? { |org| org.has_trial? && T.must(org.business_trial).copilot_plan_business? }
  end
end
