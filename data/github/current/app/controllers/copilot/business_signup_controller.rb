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
    redirect_to_with_tracking_params copilot_plan_purchase_path
  end

  def choose_business_type # rubocop:todo GitHub/UseRestfulActions
    redirect_to_with_tracking_params copilot_plan_purchase_path
  end

  def choose_organization # rubocop:todo GitHub/UseRestfulActions
    redirect_to_with_tracking_params copilot_plan_purchase_path, priority: "organization"
  end

  def choose_enterprise # rubocop:todo GitHub/UseRestfulActions
    redirect_to_with_tracking_params copilot_plan_purchase_path, priority: "business"
  end

  def organization_payment # rubocop:todo GitHub/UseRestfulActions
    # If we're redirected here from creating a new organization, clear the redirect session key
    session.delete(:return_to) if session[:return_to] == "copilot_business_signup"
    redirect_to_with_tracking_params copilot_plan_purchase_path, organization: params[:org]
  end

  def enterprise_payment # rubocop:todo GitHub/UseRestfulActions
    redirect_to_with_tracking_params copilot_plan_purchase_path, enterprise: params[:enterprise]
  end

  def organization_policy # rubocop:todo GitHub/UseRestfulActions
    redirect_to_with_tracking_params copilot_plan_purchase_path, organization: params[:org]
  end

  def organization_seat_management # rubocop:todo GitHub/UseRestfulActions
    redirect_to_with_tracking_params copilot_plan_purchase_path, organization: params[:org]
  end

  def enterprise_policy # rubocop:todo GitHub/UseRestfulActions
    redirect_to_with_tracking_params copilot_plan_purchase_path, enterprise: params[:enterprise]
  end

  def organization_signup # rubocop:todo GitHub/UseRestfulActions
    redirect_to_with_tracking_params copilot_plan_purchase_path, organization: params[:org]
  end

  def enterprise_seat_management # rubocop:todo GitHub/UseRestfulActions
    redirect_to_with_tracking_params copilot_plan_purchase_path, enterprise: params[:enterprise]
  end

  def signup_completion # rubocop:todo GitHub/UseRestfulActions
    is_org = params[:business_type] == "org"
    is_enterprise = params[:business_type] == "enterprise"

    redirect_to_with_tracking_params copilot_plan_purchase_path, priority: is_org ? "organization" : "enterprise"
  end

  private

  def show_billing_info_prompt?
    return false if this_organization.org_is_on_standard_tos?

    !this_organization.has_saved_billing_information?
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
    return false if enterprise.enterprise_agreements.where(status: "active").empty?
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
