# typed: true
# frozen_string_literal: true

# Controller getting Actions, Packages, and Shared Storage usage for organizations
class Orgs::BillingSettings::SharedProductsUsageController < Orgs::Controller
  include GitHub::Memoizer

  before_action :login_required
  before_action :org_billing_management_only
  before_action :ensure_billing_enabled

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql5,
    only: [:show_shared_storage, :show_actions, :show_packages, :show_packages_storage]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show_shared_storage],
    optional: true

  def show_actions # rubocop:todo GitHub/UseRestfulActions
    has_business = org.business.present?
    render(Billing::Settings::Actions::ActionsUsageComponent.new(
      account: org,
      spending_limit_enabled: view.spending_limit_enabled?,
      spending_limit_path: view.spending_limit_path,
      usage_moved_to_vnext: has_business && product_moved_to_vnext?(org.business, :actions),
      vnext_usage_link: has_business ? enterprise_billing_usage_path(org.business.slug) : ""
    ), layout: false)
  end

  def show_packages # rubocop:todo GitHub/UseRestfulActions
    render(Billing::Settings::Packages::PackagesUsageComponent.new(
      account: org,
      spending_limit_enabled: view.spending_limit_enabled?,
      spending_limit_path: view.spending_limit_path
    ), layout: false)
  end

  def show_shared_storage # rubocop:todo GitHub/UseRestfulActions
    if org.delegate_billing_to_business?
      render partial: "billing_settings/github_storage_usage_lite", locals: { view: view, account: org }
    else
      render partial: "billing_settings/github_storage_usage", locals: { view: view }
    end
  end

  def show_packages_storage # rubocop:todo GitHub/UseRestfulActions
    usage = Billing::SharedStorageUsage.usage_quote(org)
    org_usage = BillingSettings::OverviewView::SharedStorageUsage.new(org, usage: usage)

    usage = Billing::SharedStorageUsage.usage_quote(org.business)
    business_usage = BillingSettings::OverviewView::SharedStorageUsage.new(org.business, usage: usage)

    has_error = org_usage.has_error? || business_usage.has_error?
    data = {
      org_usage: org_usage.estimated_monthly_private_gigabytes,
      other_orgs_usage: business_usage.estimated_monthly_private_gigabytes - org_usage.estimated_monthly_private_gigabytes,
      available_usage: business_usage.plan_included_megabytes_in_gigabytes - business_usage.estimated_monthly_private_gigabytes,
      quota: business_usage.plan_included_megabytes_in_gigabytes,
      business_usage: business_usage.estimated_monthly_private_gigabytes,
      business_usage_percentage: usage.included_usage_percentage
    } unless has_error

    render partial: "billing_settings/github_packages_storage_usage_lite", locals: {
      data: data,
      has_error: has_error,
    }
  end

  private

  memoize def org
    current_organization_for_member_or_billing
  end

  memoize def view
    ::BillingSettings::ProductUsageView.new(account: org, current_user: current_user)
  end

  def ensure_billing_enabled
    return render_404 unless GitHub.billing_enabled?
  end
end
