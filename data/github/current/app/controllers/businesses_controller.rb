# typed: true
# frozen_string_literal: true

class BusinessesController < Businesses::BusinessController
  include BusinessesHelper
  include ResilienceHelper

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    ApplicationRecord::Repositories,
    only: %i(show)

  before_action :login_required
  before_action :redirect_invitees_to_invited, only: %i(show)
  before_action :business_access_required, except: %i(show)
  before_action only: %i(show) do
    T.bind(self, BusinessesController)
    business_access_required(allow_members: true, allow_unaffiliated: this_business&.supports_unaffiliated_user_accounts?)
  end
  before_action :business_owner_required, except: %i(show)
  before_action only: %i(show) do
    T.bind(self, BusinessesController)
    redirect_billing_manager_and_viewer_to_billing_settings(skip_redirecting_members: true)
  end
  before_action :self_serve_deletion_support_required, only: :destroy

  skip_before_action :cap_pagination, only: %i(show)
  skip_before_action :organization_upgrade_purchase_not_initiated, only: %i(show)
  skip_before_action :creation_from_coupon_purchase_not_initiated, only: %i(show)

  include Site::MicrosoftAnalyticsDependency
  before_action :enable_microsoft_analytics, only: %i(show)
  before_action :add_microsoft_analytics_csp_exceptions, only: %i(show)
  layout "enterprise_funnel", only: %i(show)

  stylesheet_bundle :suggestions, only: %i(show)

  def show
    instrument_show
    render "businesses/show", locals: {
      pending_invitation: this_business.pending_admin_invitation_for(current_user),
      display_org_attachment_failure_banner: display_org_attachment_failure_banner,
    }
  end

  def destroy
    unless this_business.self_serve_deletion_permitted?
      flash[:error] = "You must #{org_removal_flavor} all organizations before you can delete this enterprise.".squeeze(" ")
      return redirect_to settings_profile_enterprise_path(this_business)
    end

    unless destroy_verification_provided?
      flash[:error] = "The enterprise was not deleted. Please provide the correct verification phrase."
      return redirect_to settings_profile_enterprise_path(this_business)
    end

    this_business.soft_delete!(actor: current_user, self_serve: true)
    redirect_to "/", notice: "Deleted the #{this_business.name} enterprise."
  end

  private

  def destroy_verification_provided?
    verification_pattern = %r{\A#{ Regexp.quote this_business.slug }\z}i
    params[:verify].to_s =~ verification_pattern
  end

  def self_serve_deletion_support_required
    render_404 unless this_business.self_serve_deletion_supported?
  end

  # The following actions do not need the EMU tenant verification policy.
  # We redirect anonymous requests to SSO in redirect_to_login as a UX improvement.
  def tenant_verification_enforceable
    return :no if %w(show).include?(action_name)
    :yes
  end

  # The following actions do not need the EMU visibility policy.
  # We redirect anonymous requests to SSO in redirect_to_login as a UX improvement.
  def emu_visibility_enforceable
    return :no if %w(show).include?(action_name)
    :yes
  end

  def redirect_invitees_to_invited
    return unless this_business
    return if this_business.billing_manager?(current_user)
    return if this_business.owner?(current_user)
    return if has_member_business_access? # Also let members of owned orgs bypass the redirect
    return unless BusinessOrganizationInvitation.pending.where(business: this_business, invitee_id: current_user.owned_organization_ids).any?
    redirect_to enterprise_invited_path(this_business)
  end

  def instrument_show
    GlobalInstrumenter.instrument("enterprise_account.profile_view", {
      enterprise: this_business,
      actor: current_user,
    })
  end

  def org_removal_flavor
    return "delete" if this_business.enterprise_managed?
    "remove or transfer"
  end

  def display_org_attachment_failure_banner
    return false unless this_business.organization_upgrade_completed?
    return false unless upgrading_org = this_business.upgrade_initiated_from_organization
    return false if this_business.organizations.include?(upgrading_org)
    return false unless EnterpriseAccounts::KV.store.get(this_business.org_attachment_failure_notice_key(current_user)).value { true }.present?
    true
  end
end
