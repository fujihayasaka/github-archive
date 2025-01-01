# typed: true
# frozen_string_literal: true

class Copilot::EnterpriseSignupController < ApplicationController
  include TradeControlsHelper

  before_action :login_required
  before_action :dotcom_required
  before_action :require_enterprise, only: [
    :payment, :completion, :signup
  ]

  include Site::MicrosoftAnalyticsDependency
  before_action :allow_initial_cookie_consent
  before_action :enable_microsoft_analytics
  before_action :add_microsoft_analytics_csp_exceptions
  layout "layouts/copilot_enterprise"

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
      :choose_enterprise,
      :payment,
      :policy,
      :seat_management,
      :completion
    ]

  def new
    redirect_to_with_utm copilot_plan_purchase_path and return

    redirect_to_with_utm copilot_enterprise_signup_choose_enterprise_path
  end

  def choose_enterprise # rubocop:todo GitHub/UseRestfulActions
    redirect_to_with_utm copilot_plan_purchase_path, priority: "business" and return

    already_signed_up_enterprises, other_enterprises = enterprises_eligible_for_first_run_flow.partition do |enterprise|
      Copilot::Business.new(enterprise).copilot_plan_enterprise?
    end

    trial_enterprises, available_enterprises = other_enterprises.partition(&:trial?)

    if available_enterprises.empty? && already_signed_up_enterprises.empty?
      render "copilot/enterprise_signup/no_eligible_enterprise", locals: {
        trial_enterprises: trial_enterprises
      }
    else
      render "copilot/enterprise_signup/choose_enterprise", locals: {
        available_enterprises: available_enterprises,
        already_signed_up_enterprises: already_signed_up_enterprises,
        upgrading: params[:upgrading].present?
      }
    end
  end

  def payment # rubocop:todo GitHub/UseRestfulActions
    redirect_to_with_utm copilot_plan_purchase_path, enterprise: params[:enterprise] and return

    return render_404 unless copilot_business.copilot_plan_business?

    unless this_enterprise_available_for_signup?
      return render "copilot/enterprise_signup/require_paid_enterprise_account", locals: {
        enterprise: this_enterprise,
        copilot_business_trial: ongoing_copilot_business_trial
      }
    end

    render "copilot/enterprise_signup/payment", locals: {
      enterprise: this_enterprise,
      seat_count: copilot_business.copilot_enabled_members_count,
      payment_method: this_enterprise.payment_method,
      upgrading: current_enterprise_has_copilot_enabled?
    }
  end

  def seat_management # rubocop:todo GitHub/UseRestfulActions
    redirect_to_with_utm copilot_plan_purchase_path, enterprise: params[:enterprise] and return

    return render_404 unless copilot_business.copilot_plan_enterprise?

    unless this_enterprise_available_for_signup?
      return render "copilot/enterprise_signup/require_paid_enterprise_account", locals: { enterprise: this_enterprise }
    end

    page = params[:page] || 1
    paginated_orgs = copilot_business.business_object.organizations.paginate(page: page, per_page: 10).to_a

    render "copilot/enterprise_signup/seat_management", locals: {
      copilot_business: copilot_business,
      organizations: paginated_orgs,
      enabled_count: copilot_business.copilot_enabled_organizations_count,
      show_org_list: params[:page].present?
    }
  end

  def policy # rubocop:todo GitHub/UseRestfulActions
    redirect_to_with_utm copilot_plan_purchase_path, enterprise: params[:enterprise] and return

    render_404 unless copilot_business.copilot_plan_enterprise?

    snippy_setting = copilot_business.snippy_setting

    render "copilot/enterprise_signup/policy", locals: {
      configurable: this_enterprise,
      default_suggestions_policy: default_policy_menu_item(snippy_setting),
      default_chat_policy: "enabled",
      default_cli_policy: "enabled",
      submit_path: update_settings_copilot_policy_enterprise_path(this_enterprise.display_login),
      return_to: "/github-copilot/enterprise_signup/seat_management?enterprise=#{this_enterprise}&#{(utm_memo).to_query}"
    }
  end

  def signup # rubocop:todo GitHub/UseRestfulActions
    redirect_to_with_utm copilot_plan_purchase_path, enterprise: params[:enterprise] and return

    return render_404 unless copilot_business.copilot_plan_business?
    return render_404 unless this_enterprise_available_for_signup?
    upgrading_from_copilot_business = current_enterprise_has_copilot_enabled?

    copilot_business.copilot_plan_enterprise!

    # When an enterprise purchases/upgrades to the Copilot Enterprise plan, we want Copilot at the platform policy
    # to be Enabled by default, except if they were already part of the Copilot Enterprise beta
    copilot_business.copilot_for_dotcom_enabled! unless this_enterprise&.feature_flag_enabled?(:copilot_for_enterprise, default: false)

    CopilotEnterpriseMailer.welcome_business_admins(this_enterprise).deliver_later

    if upgrading_from_copilot_business
      Copilot::Instrumenter.instrument_copilot_plan_changed(current_user, this_enterprise, "business", "enterprise")

      redirect_to_with_utm copilot_enterprise_signup_completion_path, enterprise: this_enterprise
    else
      # Copilot in the CLI policy is Enabled by default for Copilot Enterprise customers
      # Customers who have upgraded from Copilot Business plan or Copilot Enterprise trial will keep their existing CLI setting
      copilot_business.cli_enabled!

      redirect_to_with_utm copilot_enterprise_signup_policy_path, enterprise: this_enterprise
    end
  end

  def completion # rubocop:todo GitHub/UseRestfulActions
    redirect_to_with_utm copilot_plan_purchase_path, enterprise: params[:enterprise] and return

    return render_404 unless this_enterprise.present?
    render "copilot/enterprise_signup/completion", locals: {
      this_enterprise: this_enterprise,
      copilot_organizations_count: copilot_business.copilot_enabled_organizations_count,
      copilot_seat_count: copilot_business.copilot_enabled_members_count,
      microsoft_analytics_order_id: microsoft_analytics_order_id
    }
  end

  private

  memoize def copilot_business
    Copilot::Business.new(this_enterprise)
  end

  memoize def current_enterprise_has_copilot_enabled?
    copilot_business.has_copilot_organization?
  end

  memoize def enterprises_eligible_for_first_run_flow
    enterprises = current_user.businesses(membership_type: :admin)
    cap_filter.authorized_resources(enterprises)
  end

  def default_policy_menu_item(snippy_setting)
    settings_to_menu_items = {
      "disabled" => "allowed",
      "enabled" => "blocked"
    }

    settings_to_menu_items[snippy_setting] || snippy_setting
  end

  def already_signed_up_enterprises
    current_user.businesses.select do |enterprise|
      enterprise.adminable_by?(current_user) && Copilot::Business.new(enterprise).copilot_plan_enterprise?
    end
  end

  memoize def this_enterprise_available_for_signup?
    this_enterprise.adminable_by?(current_user) &&
    !this_enterprise.trial? &&
    copilot_business.copilot_billable? &&
    !ongoing_copilot_business_trial
  end

  memoize def ongoing_copilot_business_trial
    Copilot::BusinessTrial.ongoing.where(
      trialable_id: this_enterprise.organization_ids,
      trialable_type: "Organization",
      copilot_plan: "business"
    ).first
  end

  def require_enterprise
    render_404 unless this_enterprise
  end

  def target_for_conditional_access
    # This is safe due to :login_required, :require_enterprise
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  def resource_for_conditional_access
    return self unless logged_in?
    return this_enterprise if CAP_ENT_ACTIONS.include?(action_name) && this_enterprise.present?

    current_user
  end

  CAP_ENT_ACTIONS = %w[payment completion signup].freeze

  memoize def this_enterprise
    current_user.businesses(membership_type: :admin)
      .find_by_slug(params[:enterprise])
  end

  def redirect_to_with_utm(to_path, additional_params = {})
    redirect_to preserve_utm_query_params(to_path, additional_params)
  end

  def preserve_utm_query_params(to_path, additional_params = {})
    params = (utm_memo).merge(additional_params)
    return to_path if params.empty?

    uri = URI::HTTP.build(path: to_path, query: params.to_query)
    # only return the absolute path and query, don't include blank hostname and protocol
    "#{uri.path}?#{uri.query}"
  end

  def utm_memo
    session[:utm_memo] || {}
  end

  def microsoft_analytics_order_id
    business_name = params[:enterprise]
    timestamp = Time.now.strftime("%m%d") # month, day
    Digest::SHA256.hexdigest("#{timestamp}-enterprise-#{business_name}")
  end
end
