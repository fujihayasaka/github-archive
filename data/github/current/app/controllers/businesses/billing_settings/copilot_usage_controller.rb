# typed: true
# frozen_string_literal: true

class Businesses::BillingSettings::CopilotUsageController < Businesses::BusinessController
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
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  def show
    if Copilot::Business.new(this_business).copilot_standalone?
      render(Billing::Settings::Copilot::StandaloneUsageComponent.new(copilot_standalone_usage), layout: false)
    else
      render(Billing::Settings::CopilotForBusiness::BusinessUsageComponent.new(
        organizations_copilot_usage: organizations_copilot_usage,
        number_of_organizations_without_copilot_usage: organizations_without_copilot_usage
      ), layout: false)
    end
  end

  private

  def organizations_copilot_usage # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @organizations_copilot_usage if defined?(@organizations_copilot_usage)
    @organizations_copilot_usage = begin
      response = client_wrapper.copilot_monthly_usage_by_owner

      if response.is_a?(Billing::Api::ClientWrapper::BillingClientError)
        return []
      end

      total_copilot_usage_by_owner = response.total_copilot_usage_by_owner
      org_hash = org_hash(total_copilot_usage_by_owner.map { |u| u[:owner_id] })
      active_usage = total_copilot_usage_by_owner.select { |u| !org_hash[u[:owner_id]].nil? }

      active_usage.each do |u|
        organization = org_hash[u[:owner_id]]
        u[:organization_name] = organization.name
        u[:manage_organization_href] = settings_org_billing_path(organization)
        u[:organization_avatar] = helpers.avatar_for(organization)
        u[:adminable] = organization.adminable_by?(current_user)
      end
    end
  end

  memoize def copilot_standalone_usage
    begin
      response = client_wrapper.copilot_monthly_usage_by_owner

      if response.is_a?(Billing::Api::ClientWrapper::BillingClientError)
        return []
      end

      response.total_copilot_usage_by_owner
    end
  end

  def organizations_without_copilot_usage
    this_business.organizations.count - organizations_copilot_usage.count
  end

  def org_hash(org_ids)
    this_business.organizations.where(id: org_ids).map { |o| [o.id, o] }.to_h
  end

  def client_wrapper # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @client_wrapper if defined?(@client_wrapper)
    @client_wrapper = Billing::Api::ClientWrapper.new(billable_owner: this_business)
  end
end
