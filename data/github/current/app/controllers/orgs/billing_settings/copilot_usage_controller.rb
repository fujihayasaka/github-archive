# typed: true
# frozen_string_literal: true

class Orgs::BillingSettings::CopilotUsageController < Orgs::Controller
  before_action :login_required
  before_action :org_billing_management_only
  before_action :ensure_billing_enabled
  before_action :ensure_feature_enabled

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    only: [:show]

  def show
    response = billing_platform_client.get_all_pricing
    copilot_pricing = nil

    unless response.is_a?(::Billing::Platform::Api::Error)
      copilot_pricing = response[:pricings].find do |pricing|
        pricing[:sku] == "copilot_for_business"
      end
    end

    render(Billing::Settings::CopilotForBusiness::UsageBodyComponent.new(
      account: organization,
      copilot_pricing: copilot_pricing,
      show_spending: !organization.delegate_billing_to_business?,
    ), layout: false)
  end

  private

  memoize def organization
    current_organization_for_member_or_billing
  end

  def ensure_feature_enabled
    render_404 unless Copilot::Organization.new(organization).has_copilot_for_business?
  end

  sig { returns(Billing::Platform::Api::Client) }
  def billing_platform_client
    Billing::Platform::Api::Client.new
  end
end
