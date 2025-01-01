# typed: true
# frozen_string_literal: true

class Businesses::BusinessController < ApplicationController
  include BusinessesHelper
  include LicensingHelper
  include Businesses::Concerns::BusinessAccess

  PAGE_SIZE = 30

  class InvalidBusinessSettingValueError < StandardError; end

  rescue_from InvalidBusinessSettingValueError, with: :report_invalid_input_error

  javascript_bundle :businesses
  stylesheet_bundle :businesses
  stylesheet_bundle :settings

  before_action :unsuspended_business_required
  before_action :redirect_if_organization_upgrade_initiated
  before_action :redirect_if_coupon_redemption_initiated
  before_action :organization_upgrade_purchase_not_initiated
  before_action :creation_from_coupon_purchase_not_initiated
  after_action :customer_category_instrumentation

  # How long does fist EMU owner user session last?
  FIRST_EMU_OWNER_USER_SESSION_EXPIRY = 24.hours

  protected

  # Protected: Check for an enterprise to not be IdP SCIM managed, used in the before_actions
  #
  # Renders 404 when business is IdP SCIM managed
  def non_scim_managed_business_required
    if GitHub.single_business_environment?
      render_404 unless this_business.non_scim_managed_business?
    else
      render_404 if scim_managed_enterprise?(this_business)
    end
  end

  # Protected: Check for an enterprise to not be IdP managed, used in the before_actions
  #
  # Renders 404 when business is IdP SCIM managed
  def non_idp_managed_business_required
    render_404 if scim_managed_enterprise?(this_business)
  end

  # Protected: Require business to be IdP enterprise managed, used in the before_actions
  #
  # Renders 404 when business is not IdP SCIM enterprise managed
  def idp_managed_business_required
    render_404 unless scim_managed_enterprise?(this_business)
  end

  # Protected: Require business to be enterprise managed, used in the before_actions
  #
  # Renders 404 when business is not enterprise managed
  def emu_business_required
    render_404 unless this_business&.enterprise_managed_user_enabled?
  end

  def parse_sort_order(query_args)
    field, direction = query_args[:sort].to_s.split("-")

    return { sort_field: nil, sort_direction: nil } if field.blank? || direction.blank?

    field = "created_at" if field.to_s.downcase == "created"
    { sort_field: field, sort_direction: direction }
  end
  helper_method :parse_sort_order

  private

  # This method overrides the default value set by GitHub.max_ui_pagination_page
  # that is used in ApplicationController, so that controllers that inherit from
  # Businesses::BusinessController can paginate up to 10_000 pages.
  def max_pagination_page
    10_000
  end

  # Private: Override of the redirect to login behaviour, which checks
  # redirects to SSO sign in for an IdP if this_business is EMU enabled.
  def redirect_to_login(return_to = nil)
    if this_business&.enterprise_managed_user_enabled?
      return redirect_to business_idm_sso_enterprise_path(this_business)
    end

    super
  end

  def dependency_insights_required
    render_404 unless this_business&.dependency_insights_enabled_for?(current_user)
  end

  def business_owner_required
    render_404 unless this_business&.owner?(current_user)
  end

  def business_permission_required(fgp)
    return render_404 unless this_business && current_user && fgp
    render_404 unless Authz.domain.check_allowed(current_user, fgp, this_business)
  end

  def business_admin_invitations_required
    render_404 if GitHub.bypass_business_member_invites_enabled? || this_business&.enterprise_managed_user_enabled?
  end

  def modify_code_security_policies_permission_required
    business_authz = SecurityProduct::Permissions::BusinessAuthz.new(this_business, actor: current_user)
    render_404 unless business_authz.can_modify_code_security_policies?
  end

  def active_enterprise_required
    return unless this_business.feature_enabled?(:hide_enterprise_features_for_expired_and_cancelled_trials)
    render_404 if this_business&.trial_expired? || this_business&.trial_cancelled?
  end

  def business_oidc_required
    render_404 if GitHub.single_business_environment? || !this_business.enterprise_managed_user_enabled?
  end

  def business_basic_access_or_owner_required
    if this_business&.seats_plan_basic?
      business_access_required(allow_members: true)
    else
      business_owner_required
    end
  end

  def business_basic_access_or_unaffiliated_or_owner_required
    if this_business&.seats_plan_basic? || this_business.supports_unaffiliated_user_accounts?
      business_access_required(allow_members: true, allow_unaffiliated: this_business.supports_unaffiliated_user_accounts?)
    else
      business_owner_required
    end
  end

  # `skip_redirecting_members` is used to skip redirecting the billing manager if they're also a member of the business
  def redirect_billing_manager_and_viewer_to_billing_settings(skip_redirecting_members: false)
    return unless this_business.billing_manager?(current_user)
    return if this_business.owner?(current_user)
    return if has_member_business_access?(allow_members: skip_redirecting_members) # Also let members of owned orgs bypass the redirect
    redirect_to settings_billing_enterprise_path(this_business)
  end

  def target_for_conditional_access
    return :no_target_for_conditional_access unless this_business # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    this_business
  end

  memoize def this_business_organizations_count
    this_business.organizations.count
  end
  helper_method :this_business_organizations_count

  memoize def query_param
    params[:query]
  end

  def slug_param
    params[:slug]
  end

  def admin_login_param
    params.require(:admin)
  end

  # Public: Generic way of validating whether a setting value is valid.
  #
  # Raises InvalidBusinessSettingValueError which is handled by rescue_from.
  #
  # value - String representing the provided value to check
  # valid_values - Array of String. Defaults to %w(enabled disabled no_policy)
  #                if not provided.
  #
  # Returns nothing.
  def validate_setting(value:, valid_values: %w(enabled disabled no_policy))
    raise InvalidBusinessSettingValueError unless valid_values.include?(value.to_s)
  end

  def report_invalid_input_error
    flash[:error] = "You provided an invalid input value. Please try again."
    redirect_back fallback_location: settings_profile_enterprise_path(this_business)
  end

  def person_required
    render_404 if person.nil?
  end

  def business_user_account_required
    return if GitHub.enterprise? && person.present?
    render_404 if person.nil? || business_user_account.nil?
  end

  memoize def person
    User.find_by(login: params[:person_login])
  end

  memoize def business_user_account
    person.business_user_accounts.find_by(business_id: this_business.id)
  end

  def sso_enabled_required
    if GitHub.enterprise?
      render_404 unless GitHub.auth.saml?
    else
      render_404 unless this_business&.external_provider_enabled?
    end
  end

  def business_full_plan_required
    render_404 unless this_business&.seats_plan_full?
  end

  def business_not_downgraded_to_free_plan_required
    render_404 if this_business&.downgraded_to_free_plan?
  end

  def redirect_if_organization_upgrade_initiated
    return if GitHub.enterprise?
    return unless params[:slug]
    if this_business&.organization_upgrade_initiated?
      flash[:error] = "Your upgrade for #{this_business.slug} is incomplete. Please complete the purchase to upgrade your account."
      redirect_to billing_upgrade_from_organization_enterprise_path(this_business)
    end
  end

  def redirect_if_coupon_redemption_initiated
    return if GitHub.enterprise?
    return unless params[:slug]
    if this_business&.creation_initiated_from_coupon?
      flash[:error] = "Coupon redemption for #{this_business.slug} is incomplete. Please redeem coupon to unlock your account."
      redirect_to find_coupon_path
    end
  end

  def organization_upgrade_initiated_required
    return if GitHub.enterprise?
    return unless params[:slug]
    render_404 unless this_business&.organization_upgrade_initiated?
  end

  def organization_upgrade_purchase_not_initiated
    return if GitHub.enterprise?
    return unless params[:slug]
    render_404 if this_business&.organization_upgrade_purchase_initiated?
  end

  def creation_from_coupon_purchase_not_initiated
    return if GitHub.enterprise?
    return unless params[:slug]
    render_404 if this_business&.creation_from_coupon_purchase_initiated?
  end

  # before_action that checks if the current business is suspended and needs to be hidden from users.
  # 404s to all regular users, unless they are an enterprise owner navigating to the suspended enterprise's landing page.
  def unsuspended_business_required
    return if GitHub.enterprise?
    return if current_user&.site_admin?
    return unless params[:slug] && this_business&.suspended?
    render_404 unless this_business&.owner?(current_user) && params["controller"] == "businesses" && params["action"] == "show"
  end

  def eligible_for_self_serve_payment_required
    render_404 unless this_business.eligible_for_self_serve_payment?
  end

  def redirect_to_billing_settings_or_return_to
    if params[:return_to].present?
      safe_redirect_to params[:return_to], fallback: settings_billing_enterprise_path(this_business)
    else
      redirect_to settings_billing_enterprise_path(this_business)
    end
  end

  def customer_category
    return "none" if params[:slug].blank?
    this_business&.customer_category || "none"
  end

  def customer_size
    this_business&.customer_category_size || 0
  end

  memoize def current_announcement
    GitHub::EnterpriseAnnouncement.get_announcement
  end
  helper_method :current_announcement

  memoize def current_organization
    this_business&.organizations&.find_by(login: params[:id])
  end
  helper_method :current_organization

  def require_current_organization
    render_404 if current_organization.nil?
  end

  sig { void }
  def ensure_not_spammy_user
    return unless current_user&.spammy?

    flash[:error] = ActionController::Base.helpers.strip_tags(TradeControls::Notices.trade_screening_account_spammy)
    redirect_to enterprise_path(this_business)
  end

  def require_tos_acceptance
    unless ActiveRecord::Type::Boolean.new.cast(params[:agreed_to_terms])
      flash[:error] = "You must accept the GitHub Customer Agreement."
      redirect_to :back
    end
  end

  def first_emu_admin_partially_signed_in?
    return true if session[:recovery_code_required_user].present? &&
      this_business.feature_enabled?(:login_first_emu_admin_recovery_code) &&
      this_business.enterprise_managed_user_enabled? &&
      this_business.external_provider_enabled? &&
      # We need to check against login rather than display_login because the user is going through the login flow.
      this_business.find_first_emu_owner&.login == session[:recovery_code_required_user]  # rubocop:todo GitHub/DoNotAllowLogin

    false
  end
end
