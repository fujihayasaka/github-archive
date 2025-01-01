# typed: true
# frozen_string_literal: true

class Businesses::BillingSettings::CodespacesUsageController < Businesses::BusinessController
  before_action :block_if_meuse_deprecated
  before_action :ensure_billing_enabled
  before_action :business_access_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    only: [:show_overview]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    only: [:show_org_usage]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show_overview, :show_org_usage], optional: true

  def show_org_usage # rubocop:todo GitHub/UseRestfulActions
    render(Billing::Settings::Codespaces::BusinessUsageComponent.new(
      organizations_codespaces_usage: organizations_codespaces_usage,
      number_of_organizations_without_codespaces_usage: organizations_without_codespaces_usage
    ), layout: false)
  end

  def show_overview # rubocop:todo GitHub/UseRestfulActions
    view = Businesses::BillingSettings::ShowView.new(current_user: current_user, business: this_business)
    render(Billing::Settings::Codespaces::UsageBodyComponent.new(
      account: this_business,
      show_spending: view.show_spending_limits_tab? || view.show_budgets_tab?,
      spending_limit_path: view.spending_limit_path
    ), layout: false)
  end

  private

  def organizations_codespaces_usage # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @organizations_codespaces_usage ||= begin
      response = client_wrapper.codespaces_monthly_usage_by_owner

      if response.is_a?(Billing::Api::ClientWrapper::BillingClientError)
        Failbot.report(response)
        return []
      end

      total_codespaces_usage_by_owner = response.total_codespaces_usage_by_owner
      org_hash = org_hash(total_codespaces_usage_by_owner.map { |u| u[:owner_id] })
      active_usage = total_codespaces_usage_by_owner.select { |u| !org_hash[u[:owner_id]].nil? }

      active_usage.each do |u|
        organization = org_hash[u[:owner_id]]
        u[:organization_name] = organization.name
        u[:manage_organization_href] = settings_org_billing_path(organization)
        u[:organization_avatar] = helpers.avatar_for(organization)
        u[:adminable] = organization.adminable_by?(current_user)
      end
    end
  end

  def organizations_without_codespaces_usage
    this_business.organizations.count - organizations_codespaces_usage.count
  end

  def org_hash(org_ids)
    this_business.organizations.where(id: org_ids).map { |o| [o.id, o] }.to_h
  end

  def client_wrapper # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @client_wrapper ||= Billing::Api::ClientWrapper.new(billable_owner: this_business)
  end

  def block_if_meuse_deprecated
    if FeatureFlag.vexi.enabled?(:billing_deprecate_meuse_components_part_two, current_user, default: false)
      render_404
    end
  end
end
