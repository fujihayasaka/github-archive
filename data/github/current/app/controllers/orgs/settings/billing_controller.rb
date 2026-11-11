# typed: true
# frozen_string_literal: true

class Orgs::Settings::BillingController < Orgs::Controller
  include Billing::BillingChecksDependency

  before_action :login_required
  before_action :ensure_current_organization_for_billing
  before_action :ensure_trade_restrictions_allows_org_settings_access
  before_action :billing_access_required
  before_action :ensure_billing_enabled
  before_action :check_proxima_billing_status
  before_action do
    T.bind(self, Orgs::Settings::BillingController)
    check_trade_compliance(target: this_organization, trade_controls_redirect: false)
  end
  before_action only: [:index] do
    T.bind(self, Orgs::Settings::BillingController)
    redirect_to_vnext(entity: current_organization, tab: params[:tab])
  end


  javascript_bundle :"billing-settings"
  stylesheet_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Iam,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::SecurityOverviewAnalytics,
    ApplicationRecord::Notify,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot, only: [:index], optional: true

  def index
    owner = current_organization_for_member_or_billing
    ActiveRecord::Base.connected_to(role: :writing) { owner.expire_stale_coupon }

    tab = params[:tab]

    if owner.business&.customer&.is_vnext_native? || show_vnext_billing_banner?(owner)
      render("settings/organization/billing_vnext", locals: { selected_tab: tab }) && return
    end

    if this_organization.billed_via_billing_platform? && tab.nil?
      redirect_to organization_settings_billing_url(current_organization)
      return
    end

    return render_404 if tab == "spending_limit" && !Billing::Budget.configurable?(owner)
    sponsors_tab = Billing::Settings::SponsorsOverviewComponent::HistoryTab.try_deserialize(params[:sponsorships_tab])
    sponsors_tab ||= Billing::Settings::SponsorsOverviewComponent::HistoryTab::Current

    if pjax? && pjax_container == "#sponsors-section-pjax-container"
      render Billing::Settings::SponsorsOverviewComponent.new(user_or_org: current_organization, active_tab: sponsors_tab)
    else
      owner = current_organization_for_member_or_billing.with_billing_data_caching
      selected_link =
        if owner.billed_via_billing_platform?
          (tab.presence || :subscriptions).to_sym
        else
          :organization_billing_settings
        end

      invitations = []
      if owner.business.nil?
        invitations = owner
          .business_invitations
          .pending_acceptance
          .includes(:business, :inviter)
      end

      render "settings/organization/billing", locals: {
        account: owner,
        invitations: invitations,
        selected_tab: tab, sponsors_tab: sponsors_tab, selected_link: selected_link,
      }
    end
  end

  private

  def show_vnext_billing_banner?(owner)
    return false unless owner.business&.billed_via_billing_platform?
    return true if owner.delegate_billing_to_business?
    return true if owner.feature_flag_enabled?(:vnext_billing_banner_for_enterprise_orgs, default: false)
    owner.business.feature_flag_enabled?(:vnext_billing_banner_for_enterprise_orgs, default: false)
  end

  def check_proxima_billing_status
    # Meuse is not supported in Proxima, so unless a customer is billed through vnext, we aren't billing them and we should hide the billing settings.
    render_404 if GitHub.multi_tenant_enterprise? && !current_organization.billable_owner.billed_via_billing_platform?
  end
end
